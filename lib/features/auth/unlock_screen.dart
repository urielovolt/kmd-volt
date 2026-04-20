import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';

class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key});

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _controller = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  bool _showPin = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      if (auth.biometricEnabled) _tryBiometric();
    });
  }

  Future<void> _tryBiometric() async {
    // Guard: do nothing if a biometric request is already in flight.
    // The initState post-frame callback and a quick button tap can otherwise
    // both call this at the same time, firing two concurrent authenticate()
    // calls and confusing Android's BiometricPrompt.
    if (_loading) return;
    setState(() => _loading = true);
    await context.read<AuthProvider>().unlockWithBiometric();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _unlock() async {
    if (_controller.text.isEmpty) return;
    setState(() => _loading = true);
    final ok =
        await context.read<AuthProvider>().unlockWithPassword(_controller.text);
    if (!ok && mounted) {
      setState(() => _loading = false);
    }
  }

  void _togglePinMode() {
    setState(() {
      _showPin = !_showPin;
      _controller.clear();
      context.read<AuthProvider>().clearError();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: _showPin
              ? _PinEntry(onBack: _togglePinMode)
              : _PasswordEntry(
                  controller: _controller,
                  obscure: _obscure,
                  loading: _loading,
                  auth: auth,
                  onToggleObscure: () =>
                      setState(() => _obscure = !_obscure),
                  onUnlock: _unlock,
                  onBiometric: _tryBiometric,
                  onSwitchToPin: auth.pinEnabled ? _togglePinMode : null,
                ),
        ),
      ),
    );
  }
}

// ─── Password entry ───────────────────────────────────────────────────────────

class _PasswordEntry extends StatelessWidget {
  final TextEditingController controller;
  final bool obscure;
  final bool loading;
  final AuthProvider auth;
  final VoidCallback onToggleObscure;
  final VoidCallback onUnlock;
  final VoidCallback onBiometric;
  final VoidCallback? onSwitchToPin;

  const _PasswordEntry({
    required this.controller,
    required this.obscure,
    required this.loading,
    required this.auth,
    required this.onToggleObscure,
    required this.onUnlock,
    required this.onBiometric,
    required this.onSwitchToPin,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 40),
        const Center(
          child: Image(
            image: AssetImage('assets/icons/app_icon.png'),
            width: 160,
            height: 160,
          ),
        ),
        const SizedBox(height: 32),
        const Text(
          'KMD Volt',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: VoltTheme.textPrimary,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'By: @urielovolt',
          style: TextStyle(
            color: VoltTheme.primary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Ingresa tu contraseña maestra para acceder',
          style: TextStyle(
            color: VoltTheme.textSecondary,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 36),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          autofocus: true,
          style: const TextStyle(color: VoltTheme.textPrimary),
          onFieldSubmitted: (_) => onUnlock(),
          decoration: InputDecoration(
            labelText: 'Contraseña maestra',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(
                obscure
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
              onPressed: onToggleObscure,
            ),
          ),
        ),
        if (auth.error != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: VoltTheme.danger.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: VoltTheme.danger.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline,
                    color: VoltTheme.danger, size: 16),
                const SizedBox(width: 8),
                Text(
                  auth.error!,
                  style: const TextStyle(
                    color: VoltTheme.danger,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: loading ? null : onUnlock,
            child: loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Desbloquear'),
          ),
        ),
        if (auth.biometricEnabled && auth.biometricAvailable) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: loading ? null : onBiometric,
              icon: const Icon(Icons.fingerprint, color: VoltTheme.primary),
              label: const Text(
                'Usar huella digital',
                style: TextStyle(color: VoltTheme.primary),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: VoltTheme.primary, width: 1),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
        if (onSwitchToPin != null) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: loading ? null : onSwitchToPin,
              icon: const Icon(Icons.pin_outlined, color: VoltTheme.textSecondary),
              label: const Text(
                'Usar PIN',
                style: TextStyle(color: VoltTheme.textSecondary),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: VoltTheme.border, width: 1),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
        const Spacer(),
        Center(
          child: Text(
            'Tu vault está cifrado con AES-256',
            style: TextStyle(
              color: VoltTheme.textMuted.withOpacity(0.7),
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── PIN entry screen ─────────────────────────────────────────────────────────

class _PinEntry extends StatefulWidget {
  final VoidCallback onBack;

  const _PinEntry({required this.onBack});

  @override
  State<_PinEntry> createState() => _PinEntryState();
}

class _PinEntryState extends State<_PinEntry> {
  String _pin = '';
  bool _loading = false;
  String? _error;
  static const int _pinLength = 6;

  void _onDigit(String d) {
    if (_pin.length >= _pinLength) return;
    setState(() {
      _pin += d;
      _error = null;
    });
    if (_pin.length == _pinLength) _submit();
  }

  void _onDelete() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _submit() async {
    setState(() => _loading = true);
    final auth = context.read<AuthProvider>();
    final ok = await auth.unlockWithPin(_pin);
    if (!ok && mounted) {
      setState(() {
        _loading = false;
        _error = auth.error ?? 'PIN incorrecto';
        _pin = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 24),
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: VoltTheme.textSecondary),
            onPressed: widget.onBack,
          ),
        ),
        const SizedBox(height: 24),
        const Icon(Icons.pin_outlined, size: 48, color: VoltTheme.primary),
        const SizedBox(height: 16),
        const Text(
          'Ingresa tu PIN',
          style: TextStyle(
            color: VoltTheme.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${_pinLength} dígitos',
          style: const TextStyle(color: VoltTheme.textMuted, fontSize: 13),
        ),
        const SizedBox(height: 32),

        // PIN dots
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_pinLength, (i) {
            final filled = i < _pin.length;
            return Container(
              width: 16,
              height: 16,
              margin: const EdgeInsets.symmetric(horizontal: 8),
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

        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: const TextStyle(color: VoltTheme.danger, fontSize: 13),
          ),
        ],

        const SizedBox(height: 40),

        // Numeric keypad
        if (_loading)
          const CircularProgressIndicator()
        else
          _buildKeypad(),

        const Spacer(),
      ],
    );
  }

  Widget _buildKeypad() {
    const digits = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', '⌫'],
    ];

    return Column(
      children: digits.map((row) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: row.map((label) {
            if (label.isEmpty) {
              return const SizedBox(width: 80, height: 64);
            }
            final isDelete = label == '⌫';
            return GestureDetector(
              onTap: isDelete ? _onDelete : () => _onDigit(label),
              child: Container(
                width: 80,
                height: 64,
                margin: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: isDelete
                      ? Colors.transparent
                      : VoltTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                  border: isDelete
                      ? null
                      : Border.all(color: VoltTheme.border),
                ),
                alignment: Alignment.center,
                child: Text(
                  label,
                  style: TextStyle(
                    color: isDelete
                        ? VoltTheme.textSecondary
                        : VoltTheme.textPrimary,
                    fontSize: isDelete ? 20 : 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          }).toList(),
        );
      }).toList(),
    );
  }
}
