import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import '../core/database/database_service.dart';

enum AuthState { initial, unauthenticated, authenticated, needsSetup }

class AuthProvider extends ChangeNotifier {
  final _db = DatabaseService.instance;
  final _localAuth = LocalAuthentication();

  AuthState _state = AuthState.initial;
  Uint8List? _vaultKey;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  bool _pinEnabled = false;
  // Prevents concurrent authenticate() calls — two overlapping calls confuse
  // Android's BiometricPrompt and require the user to retry.
  bool _isAuthenticating = false;

  // Set to true immediately after any successful unlock so that onAppResumed()
  // does not trigger an instant re-lock caused by the lifecycle event that fires
  // when the biometric prompt (or any system dialog) dismisses.
  bool _justAuthenticated = false;

  /// Auto-lock timeout: 0 = lock immediately on background, null = never.
  int? _lockTimeoutMinutes = 0;

  /// Recorded when the app goes to background (paused lifecycle state).
  DateTime? _pausedAt;

  String? _error;

  // ─── Getters ──────────────────────────────────────────────────────────────

  AuthState get state => _state;
  Uint8List? get vaultKey => _vaultKey;
  bool get biometricAvailable => _biometricAvailable;
  bool get biometricEnabled => _biometricEnabled;
  bool get pinEnabled => _pinEnabled;
  bool get isAuthenticated => _state == AuthState.authenticated;
  int? get lockTimeoutMinutes => _lockTimeoutMinutes;
  String? get error => _error;

  // ─── Initialization ───────────────────────────────────────────────────────

  Future<void> initialize() async {
    final deviceSupported = await _localAuth.isDeviceSupported();
    final canCheck = await _localAuth.canCheckBiometrics;
    _biometricAvailable = deviceSupported || canCheck;
    _biometricEnabled = await _db.isBiometricEnabled();
    _pinEnabled = await _db.hasPinEnabled();
    _lockTimeoutMinutes = await _db.getLockTimeoutMinutes();

    final hasPassword = await _db.hasMasterPassword();
    _state = hasPassword ? AuthState.unauthenticated : AuthState.needsSetup;
    notifyListeners();
  }

  // ─── Master Password ──────────────────────────────────────────────────────

  Future<bool> setupMasterPassword(String password) async {
    try {
      _error = null;
      await _db.setMasterPassword(password);
      _vaultKey = await _db.getDerivedKey(password);
      _state = AuthState.authenticated;
      _justAuthenticated = true;
      _pausedAt = null;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Error al configurar contraseña maestra';
      notifyListeners();
      return false;
    }
  }

  Future<bool> unlockWithPassword(String password) async {
    try {
      _error = null;
      final valid = await _db.verifyMasterPassword(password);
      if (!valid) {
        _error = 'Contraseña incorrecta';
        notifyListeners();
        return false;
      }
      _vaultKey = await _db.getDerivedKey(password);
      _state = AuthState.authenticated;
      _justAuthenticated = true;
      _pausedAt = null;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Error al verificar contraseña';
      notifyListeners();
      return false;
    }
  }

  // ─── Biometric ────────────────────────────────────────────────────────────

  Future<bool> unlockWithBiometric() async {
    if (!_biometricEnabled) return false;
    // Prevent two concurrent authenticate() calls. Without this guard, a
    // post-frame auto-trigger and a simultaneous button tap can both reach
    // _localAuth.authenticate() at once, causing Android's BiometricPrompt
    // to abort the first attempt and forcing the user to try again.
    if (_isAuthenticating) return false;
    _isAuthenticating = true;

    try {
      _error = null;
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Desbloquea KMD Volt con tu huella',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );

      if (!authenticated) {
        _error = 'Autenticación cancelada';
        notifyListeners();
        return false;
      }

      final sessionKey = await _db.getBiometricVaultKey();
      if (sessionKey == null) {
        _error = 'Sesión expirada. Usa tu contraseña maestra.';
        _biometricEnabled = false;
        await _db.setBiometricEnabled(false);
        notifyListeners();
        return false;
      }

      _vaultKey = sessionKey;
      _state = AuthState.authenticated;
      _justAuthenticated = true;
      _pausedAt = null;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Error en autenticación biométrica';
      notifyListeners();
      return false;
    } finally {
      // Always release the lock so future attempts can proceed.
      _isAuthenticating = false;
    }
  }

  Future<bool> enableBiometric(String masterPassword) async {
    try {
      _error = null;
      final deviceSupported = await _localAuth.isDeviceSupported();
      if (!deviceSupported) {
        _error = 'Este dispositivo no soporta biometría';
        notifyListeners();
        return false;
      }

      final available = await _localAuth.getAvailableBiometrics();
      if (available.isEmpty) {
        _error = 'No hay huella registrada en Ajustes del dispositivo';
        notifyListeners();
        return false;
      }

      final valid = await _db.verifyMasterPassword(masterPassword);
      if (!valid) {
        _error = 'Contraseña maestra incorrecta';
        notifyListeners();
        return false;
      }

      final authenticated = await _localAuth.authenticate(
        localizedReason:
            'Confirma tu huella para activar el desbloqueo biométrico',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );

      if (!authenticated) {
        _error = 'Autenticación cancelada';
        notifyListeners();
        return false;
      }

      final vaultKey = await _db.getDerivedKey(masterPassword);
      if (vaultKey != null) {
        await _db.saveBiometricVaultKey(vaultKey);
      }

      await _db.setBiometricEnabled(true);
      _biometricAvailable = true;
      _biometricEnabled = true;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Error: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }

  Future<void> disableBiometric() async {
    await _db.setBiometricEnabled(false);
    await _db.clearBiometricVaultKey();
    _biometricEnabled = false;
    notifyListeners();
  }

  // ─── PIN ──────────────────────────────────────────────────────────────────

  /// Sets up a PIN using the master password for verification.
  Future<bool> setupPin(String pin, String masterPassword) async {
    try {
      _error = null;
      final valid = await _db.verifyMasterPassword(masterPassword);
      if (!valid) {
        _error = 'Contraseña maestra incorrecta';
        notifyListeners();
        return false;
      }

      await _db.setPin(pin);

      // Store vault key so PIN unlock works without the master password
      final vaultKey = await _db.getDerivedKey(masterPassword);
      if (vaultKey != null) {
        await _db.savePinVaultKey(vaultKey);
      }

      _pinEnabled = true;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Error al configurar PIN';
      notifyListeners();
      return false;
    }
  }

  Future<bool> unlockWithPin(String pin) async {
    try {
      _error = null;
      final valid = await _db.verifyPin(pin);
      if (!valid) {
        _error = 'PIN incorrecto';
        notifyListeners();
        return false;
      }

      final sessionKey = await _db.getPinVaultKey();
      if (sessionKey == null) {
        _error = 'PIN expirado. Usa tu contraseña maestra.';
        await _db.clearPin();
        await _db.clearPinVaultKey();
        _pinEnabled = false;
        notifyListeners();
        return false;
      }

      _vaultKey = sessionKey;
      _state = AuthState.authenticated;
      _justAuthenticated = true;
      _pausedAt = null;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Error al verificar PIN';
      notifyListeners();
      return false;
    }
  }

  Future<void> disablePin() async {
    await _db.clearPin();
    await _db.clearPinVaultKey();
    _pinEnabled = false;
    notifyListeners();
  }

  // ─── Auto-lock timeout ────────────────────────────────────────────────────

  /// Call from AppRouter when the app goes to background.
  /// If timeout is 0 (immediate), locks right away.
  /// Otherwise records the background time for later comparison.
  void onAppPaused() {
    if (_state != AuthState.authenticated) return;
    if (_lockTimeoutMinutes == 0) {
      lock();
    } else {
      _pausedAt = DateTime.now();
    }
  }

  /// Call from AppRouter when the app resumes from background.
  /// Locks the vault if the configured timeout has elapsed.
  void onAppResumed() {
    // If we just authenticated (e.g. biometric prompt dismissed), skip locking.
    // The lifecycle resumed event fires right after the system dialog closes —
    // without this guard the vault would lock again immediately.
    if (_justAuthenticated) {
      _justAuthenticated = false;
      return;
    }
    if (_state != AuthState.authenticated) return;
    if (_lockTimeoutMinutes == null) return; // never auto-lock
    if (_lockTimeoutMinutes == 0) {
      // Should have been locked on pause, but lock now as safety net.
      lock();
      return;
    }
    if (_pausedAt == null) return;
    final elapsed = DateTime.now().difference(_pausedAt!).inMinutes;
    if (elapsed >= _lockTimeoutMinutes!) {
      lock();
    }
    _pausedAt = null;
  }

  Future<void> setLockTimeout(int? minutes) async {
    await _db.setLockTimeoutMinutes(minutes);
    _lockTimeoutMinutes = minutes;
    notifyListeners();
  }

  // ─── Lock / Error ─────────────────────────────────────────────────────────

  void lock() {
    // Overwrite the key bytes in memory before dropping the reference so the
    // GC cannot observe a live key copy in the heap.
    if (_vaultKey != null) {
      _vaultKey!.fillRange(0, _vaultKey!.length, 0);
    }
    _vaultKey = null;
    _state = AuthState.unauthenticated;
    _error = null;
    _pausedAt = null;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
