import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/autofill_service.dart';
import '../../core/security_service.dart';
import '../../core/services/notification_service.dart';
import '../../core/workers/password_check_worker.dart';
import '../../providers/auth_provider.dart';
import '../../providers/vault_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _autofillEnabled = false;
  bool _secureScreen    = true;

  // ── Notification settings ─────────────────────────────────────────────────
  bool _notifEnabled    = false;
  int  _notifDays       = 90;

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _notifDayOptions = [30, 60, 90, 180];

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final autofill    = await AutofillService.isEnabled();
    final secure      = await SecurityService.isSecureScreen();
    final notifStr    = await _storage.read(key: kNotifEnabledKey);
    final notifDayStr = await _storage.read(key: kNotifThresholdDaysKey);
    if (mounted) {
      setState(() {
        _autofillEnabled = autofill;
        _secureScreen    = secure;
        _notifEnabled    = notifStr == 'true';
        _notifDays       = int.tryParse(notifDayStr ?? '90') ?? 90;
      });
    }
  }

  // ── Notification toggle ───────────────────────────────────────────────────

  Future<void> _toggleNotifications(bool value) async {
    if (value) {
      // Request the OS permission first.
      await NotificationService.requestPermission();
      await _storage.write(key: kNotifEnabledKey, value: 'true');
      await _storage.write(
        key: kNotifThresholdDaysKey,
        value: _notifDays.toString(),
      );
      await PasswordCheckWorker.register();
    } else {
      await _storage.write(key: kNotifEnabledKey, value: 'false');
      await PasswordCheckWorker.cancel();
    }
    if (mounted) setState(() => _notifEnabled = value);
  }

  Future<void> _pickNotifDays() async {
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Actualización cada…'),
        children: _notifDayOptions.map((d) {
          final isSelected = d == _notifDays;
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, d),
            child: Row(
              children: [
                Expanded(child: Text('$d días')),
                if (isSelected)
                  const Icon(Icons.check, color: VoltTheme.primary, size: 18),
              ],
            ),
          );
        }).toList(),
      ),
    );
    if (picked == null || picked == _notifDays) return;
    await _storage.write(
      key: kNotifThresholdDaysKey,
      value: picked.toString(),
    );
    if (_notifEnabled) {
      // Re-register so the new threshold is used on the next worker run.
      await PasswordCheckWorker.register();
    }
    if (mounted) setState(() => _notifDays = picked);
  }

  // ─── Biometric ────────────────────────────────────────────────────────────

  Future<void> _toggleBiometric(AuthProvider auth) async {
    if (auth.biometricEnabled) {
      final confirmed = await _confirm(
        title: 'Desactivar huella',
        body: '¿Desactivar el desbloqueo con huella digital?',
        destructive: true,
        confirmLabel: 'Desactivar',
      );
      if (confirmed) await auth.disableBiometric();
    } else {
      final password = await _askMasterPassword();
      if (password == null) return;
      final ok = await auth.enableBiometric(password);
      if (mounted) _showResult(ok, ok ? 'Huella digital activada' : auth.error);
      if (!ok) auth.clearError();
    }
  }

  // ─── PIN ──────────────────────────────────────────────────────────────────

  Future<void> _togglePin(AuthProvider auth) async {
    if (auth.pinEnabled) {
      final confirmed = await _confirm(
        title: 'Desactivar PIN',
        body: '¿Desactivar el desbloqueo con PIN?',
        destructive: true,
        confirmLabel: 'Desactivar',
      );
      if (confirmed) {
        await auth.disablePin();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('PIN desactivado')),
          );
        }
      }
    } else {
      await _setupPin(auth);
    }
  }

  Future<void> _setupPin(AuthProvider auth) async {
    // Step 1: ask master password
    final password = await _askMasterPassword(
      title: 'Confirmar identidad',
      hint: 'Contraseña maestra',
    );
    if (password == null) return;

    // Step 2: choose a 6-digit PIN
    final pin = await _choosePinDialog();
    if (pin == null) return;

    final ok = await auth.setupPin(pin, password);
    if (mounted) {
      _showResult(ok, ok ? 'PIN activado' : auth.error);
      if (!ok) auth.clearError();
    }
  }

  Future<String?> _choosePinDialog() async {
    String pin = '';
    String confirm = '';
    int step = 0; // 0 = enter PIN, 1 = confirm PIN
    String? error;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSt) {
          void onDigit(String d) {
            if (step == 0) {
              if (pin.length < 6) {
                setSt(() { pin += d; error = null; });
                if (pin.length == 6) setSt(() => step = 1);
              }
            } else {
              if (confirm.length < 6) {
                setSt(() { confirm += d; error = null; });
                if (confirm.length == 6) {
                  if (pin == confirm) {
                    Navigator.pop(ctx, pin);
                  } else {
                    setSt(() {
                      confirm = '';
                      error = 'Los PINs no coinciden';
                    });
                  }
                }
              }
            }
          }

          void onDelete() {
            setSt(() {
              if (step == 0 && pin.isNotEmpty) {
                pin = pin.substring(0, pin.length - 1);
              } else if (step == 1 && confirm.isNotEmpty) {
                confirm = confirm.substring(0, confirm.length - 1);
              }
            });
          }

          final current = step == 0 ? pin : confirm;
          return AlertDialog(
            title: Text(step == 0 ? 'Elige un PIN de 6 dígitos' : 'Confirma tu PIN'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Dots
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(6, (i) {
                    final filled = i < current.length;
                    return Container(
                      width: 14,
                      height: 14,
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: filled ? VoltTheme.primary : Colors.transparent,
                        border: Border.all(
                          color: filled ? VoltTheme.primary : VoltTheme.border,
                          width: 2,
                        ),
                      ),
                    );
                  }),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: const TextStyle(color: VoltTheme.danger, fontSize: 12)),
                ],
                const SizedBox(height: 16),
                // Keypad
                ...[
                  ['1', '2', '3'],
                  ['4', '5', '6'],
                  ['7', '8', '9'],
                  ['', '0', '⌫'],
                ].map((row) {
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: row.map((label) {
                      if (label.isEmpty) {
                        return const SizedBox(width: 64, height: 48);
                      }
                      return GestureDetector(
                        onTap: label == '⌫' ? onDelete : () => onDigit(label),
                        child: Container(
                          width: 64,
                          height: 48,
                          margin: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: label == '⌫'
                                ? Colors.transparent
                                : VoltTheme.surfaceVariant,
                            borderRadius: BorderRadius.circular(10),
                            border: label == '⌫'
                                ? null
                                : Border.all(color: VoltTheme.border),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            label,
                            style: TextStyle(
                              color: label == '⌫'
                                  ? VoltTheme.textSecondary
                                  : VoltTheme.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  );
                }),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
            ],
          );
        });
      },
    );
  }

  // ─── Auto-lock timeout ────────────────────────────────────────────────────

  Future<void> _pickTimeout(AuthProvider auth) async {
    const options = [
      (label: 'Inmediatamente', minutes: 0),
      (label: '1 minuto', minutes: 1),
      (label: '5 minutos', minutes: 5),
      (label: '15 minutos', minutes: 15),
      (label: '30 minutos', minutes: 30),
      (label: '1 hora', minutes: 60),
      (label: 'Nunca', minutes: -1), // -1 sentinel for null
    ];

    final picked = await showDialog<int?>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Bloqueo automático'),
        children: options.map((o) {
          final isSelected = o.minutes == -1
              ? auth.lockTimeoutMinutes == null
              : auth.lockTimeoutMinutes == o.minutes;
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, o.minutes),
            child: Row(
              children: [
                Expanded(child: Text(o.label)),
                if (isSelected)
                  const Icon(Icons.check, color: VoltTheme.primary, size: 18),
              ],
            ),
          );
        }).toList(),
      ),
    );

    if (picked == null) return;
    await auth.setLockTimeout(picked == -1 ? null : picked);
  }

  String _timeoutLabel(int? minutes) {
    if (minutes == null) return 'Nunca';
    if (minutes == 0) return 'Inmediatamente';
    if (minutes == 1) return '1 minuto';
    if (minutes < 60) return '$minutes minutos';
    return '1 hora';
  }

  // ─── Change master password ───────────────────────────────────────────────

  Future<void> _changePassword(AuthProvider auth) async {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cambiar contraseña maestra'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: currentCtrl,
              obscureText: true,
              style: const TextStyle(color: VoltTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Contraseña actual',
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: newCtrl,
              obscureText: true,
              style: const TextStyle(color: VoltTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Nueva contraseña',
                prefixIcon: Icon(Icons.lock_open_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmCtrl,
              obscureText: true,
              style: const TextStyle(color: VoltTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Confirmar nueva contraseña',
                prefixIcon: Icon(Icons.lock_open_outlined),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cambiar'),
          ),
        ],
      ),
    );

    if (result != true) return;

    if (newCtrl.text != confirmCtrl.text) {
      _showResult(false, 'Las contraseñas nuevas no coinciden');
      return;
    }
    if (newCtrl.text.length < 8) {
      _showResult(false, 'La contraseña debe tener al menos 8 caracteres');
      return;
    }

    final isValid = await auth.unlockWithPassword(currentCtrl.text);
    if (!isValid) {
      if (mounted) _showResult(false, 'Contraseña actual incorrecta');
      return;
    }

    await auth.setupMasterPassword(newCtrl.text);
    if (mounted) _showResult(true, 'Contraseña maestra actualizada');
  }

  // ─── Reset vault ──────────────────────────────────────────────────────────

  Future<void> _resetVault(AuthProvider auth, VaultProvider vault) async {
    final password = await _askMasterPassword();
    if (password == null) return;

    final isValid = await auth.unlockWithPassword(password);
    if (!isValid) {
      if (mounted) _showResult(false, 'Contraseña incorrecta');
      return;
    }

    final confirmed = await _confirm(
      title: '⚠️ Borrar vault',
      body:
          'ADVERTENCIA: Esta acción eliminará TODAS tus contraseñas permanentemente. No hay forma de recuperarlas a menos que tengas un respaldo.\n\n¿Estás seguro?',
      destructive: true,
      confirmLabel: 'Borrar todo',
    );

    if (confirmed && mounted) {
      vault.clear();
      auth.lock();
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  Future<String?> _askMasterPassword({
    String title = 'Confirmar contraseña',
    String hint = 'Contraseña maestra',
  }) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          autofocus: true,
          style: const TextStyle(color: VoltTheme.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: const Icon(Icons.lock_outline),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    bool destructive = false,
    String confirmLabel = 'Confirmar',
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body, style: const TextStyle(height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: destructive
                ? TextButton.styleFrom(foregroundColor: VoltTheme.danger)
                : null,
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result == true;
  }

  void _showResult(bool ok, String? message) {
    if (!mounted || message == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: ok ? VoltTheme.success : VoltTheme.danger,
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final vault = context.read<VaultProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Configuración')),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),

            // ── AUTOCOMPLETAR ─────────────────────────────────────────────
            _sectionHeader('AUTOCOMPLETAR CONTRASEÑAS'),
            _card([
              ListTile(
                leading: Icon(
                  Icons.password,
                  color: _autofillEnabled
                      ? VoltTheme.success
                      : VoltTheme.textMuted,
                ),
                title: const Text('KMD Volt como gestor de contraseñas'),
                subtitle: Text(
                  _autofillEnabled
                      ? 'Activo — KMD Volt sugiere contraseñas en apps y navegadores'
                      : 'Inactivo — toca para activar',
                  style: TextStyle(
                    color: _autofillEnabled
                        ? VoltTheme.success
                        : VoltTheme.textSecondary,
                  ),
                ),
                trailing: _autofillEnabled
                    ? const Icon(Icons.check_circle, color: VoltTheme.success)
                    : const Icon(Icons.arrow_forward_ios,
                        color: VoltTheme.textMuted, size: 16),
                onTap: () async {
                  await AutofillService.openSettings();
                  await Future.delayed(const Duration(seconds: 1));
                  await _loadStatus();
                },
              ),
              if (!_autofillEnabled) ...[
                const Divider(height: 1, indent: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: VoltTheme.primary.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: VoltTheme.primary.withOpacity(0.2)),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cómo activarlo:',
                        style: TextStyle(
                          color: VoltTheme.primaryLight,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        '1. Toca el ítem de arriba\n'
                        '2. En Ajustes de Android, selecciona "KMD Volt"\n'
                        '3. Regresa a la app\n'
                        '4. Al iniciar sesión en cualquier app, KMD Volt sugerirá tus contraseñas',
                        style: TextStyle(
                          color: VoltTheme.textSecondary,
                          fontSize: 12,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ]),

            const SizedBox(height: 24),

            // ── SEGURIDAD ─────────────────────────────────────────────────
            _sectionHeader('SEGURIDAD'),
            _card([
              // Biometric
              ListTile(
                leading: const Icon(Icons.fingerprint, color: VoltTheme.primary),
                title: const Text('Desbloqueo con huella'),
                subtitle: Text(
                  auth.biometricAvailable
                      ? (auth.biometricEnabled ? 'Activado' : 'Desactivado')
                      : 'No disponible en este dispositivo',
                ),
                trailing: auth.biometricAvailable
                    ? Switch(
                        value: auth.biometricEnabled,
                        onChanged: (_) => _toggleBiometric(auth),
                      )
                    : null,
              ),
              const Divider(height: 1, indent: 16),

              // PIN
              ListTile(
                leading: const Icon(Icons.pin_outlined, color: VoltTheme.primary),
                title: const Text('Desbloqueo con PIN'),
                subtitle: Text(
                  auth.pinEnabled ? 'Activado — 6 dígitos' : 'Desactivado',
                ),
                trailing: Switch(
                  value: auth.pinEnabled,
                  onChanged: (_) => _togglePin(auth),
                ),
              ),
              const Divider(height: 1, indent: 16),

              // Auto-lock timeout
              ListTile(
                leading: const Icon(Icons.timer_outlined, color: VoltTheme.primary),
                title: const Text('Bloqueo automático'),
                subtitle: Text(_timeoutLabel(auth.lockTimeoutMinutes)),
                trailing: const Icon(Icons.chevron_right,
                    color: VoltTheme.textMuted),
                onTap: () => _pickTimeout(auth),
              ),
              const Divider(height: 1, indent: 16),

              // Screen security (FLAG_SECURE)
              ListTile(
                leading: const Icon(Icons.screenshot_monitor_outlined,
                    color: VoltTheme.primary),
                title: const Text('Seguridad de pantalla'),
                subtitle: Text(
                  _secureScreen
                      ? 'Captura de pantalla bloqueada'
                      : 'Captura de pantalla permitida',
                  style: TextStyle(
                    color: _secureScreen
                        ? VoltTheme.textSecondary
                        : VoltTheme.warning,
                  ),
                ),
                trailing: Switch(
                  value: _secureScreen,
                  onChanged: (v) async {
                    await SecurityService.setSecureScreen(v);
                    setState(() => _secureScreen = v);
                  },
                ),
              ),
              const Divider(height: 1, indent: 16),

              // Change master password
              ListTile(
                leading: const Icon(Icons.key_outlined, color: VoltTheme.primary),
                title: const Text('Cambiar contraseña maestra'),
                trailing: const Icon(Icons.chevron_right,
                    color: VoltTheme.textMuted),
                onTap: () => _changePassword(auth),
              ),
            ]),

            const SizedBox(height: 24),

            // ── NOTIFICACIONES ────────────────────────────────────────────
            _sectionHeader('NOTIFICACIONES'),
            _card([
              ListTile(
                leading: Icon(
                  Icons.notifications_outlined,
                  color: _notifEnabled
                      ? VoltTheme.primary
                      : VoltTheme.textMuted,
                ),
                title: const Text('Contraseñas antiguas'),
                subtitle: Text(
                  _notifEnabled
                      ? 'Avisar si una contraseña lleva más de $_notifDays días sin cambiar'
                      : 'Desactivado',
                  style: TextStyle(
                    color: _notifEnabled
                        ? VoltTheme.textSecondary
                        : VoltTheme.textMuted,
                  ),
                ),
                trailing: Switch(
                  value: _notifEnabled,
                  onChanged: _toggleNotifications,
                ),
              ),
              if (_notifEnabled) ...[
                const Divider(height: 1, indent: 16),
                ListTile(
                  leading: const Icon(
                    Icons.schedule_outlined,
                    color: VoltTheme.primary,
                  ),
                  title: const Text('Umbral de antigüedad'),
                  subtitle: Text('$_notifDays días'),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: VoltTheme.textMuted,
                  ),
                  onTap: _pickNotifDays,
                ),
              ],
            ]),

            const SizedBox(height: 24),

            // ── VAULT INFO ────────────────────────────────────────────────
            _sectionHeader('VAULT'),
            _card([
              const ListTile(
                leading: Icon(Icons.info_outline, color: VoltTheme.primary),
                title: Text('Cifrado'),
                subtitle: Text('AES-256-CBC con PBKDF2'),
              ),
              const Divider(height: 1, indent: 16),
              const ListTile(
                leading: Icon(Icons.storage, color: VoltTheme.primary),
                title: Text('Almacenamiento'),
                subtitle: Text('Local — solo en este dispositivo'),
              ),
              const Divider(height: 1, indent: 16),
              Consumer<VaultProvider>(
                builder: (ctx, v, _) => ListTile(
                  leading: const Icon(Icons.numbers, color: VoltTheme.primary),
                  title: const Text('Entradas guardadas'),
                  trailing: Text(
                    '${v.entries.length}',
                    style: const TextStyle(
                      color: VoltTheme.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ]),

            const SizedBox(height: 24),

            // ── ACERCA DE ─────────────────────────────────────────────────
            _sectionHeader('ACERCA DE'),
            _card([
              const ListTile(
                leading: Icon(Icons.bolt, color: VoltTheme.primary),
                title: Text('KMD Volt'),
                subtitle: Text('v1.0.0 — Gestor personal de contraseñas'),
              ),
              const Divider(height: 1, indent: 16),
              const ListTile(
                leading: Icon(Icons.lock_outline, color: VoltTheme.textMuted),
                title: Text('Privacidad'),
                subtitle: Text('Tus datos nunca salen de tu dispositivo'),
              ),
              const Divider(height: 1, indent: 16),
              const ListTile(
                leading: Icon(Icons.code, color: VoltTheme.textMuted),
                title: Text('Desarrollado por'),
                subtitle: Text(
                  '@urielovolt',
                  style: TextStyle(
                    color: VoltTheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ]),

            const SizedBox(height: 24),

            // ── ZONA DE PELIGRO ───────────────────────────────────────────
            _sectionHeader('ZONA DE PELIGRO'),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: VoltTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: VoltTheme.danger.withOpacity(0.3)),
              ),
              child: ListTile(
                leading: const Icon(Icons.delete_forever, color: VoltTheme.danger),
                title: const Text(
                  'Borrar vault completo',
                  style: TextStyle(color: VoltTheme.danger),
                ),
                subtitle: const Text(
                  'Elimina todas las contraseñas de forma permanente',
                ),
                onTap: () => _resetVault(auth, vault),
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Text(
        text,
        style: const TextStyle(
          color: VoltTheme.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _card(List<Widget> children) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: VoltTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: VoltTheme.border),
      ),
      child: Column(children: children),
    );
  }
}
