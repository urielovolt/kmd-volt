import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';


class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _loading = false;

  int get _strength {
    final p = _passwordController.text;
    int score = 0;
    if (p.length >= 8) score++;
    if (p.length >= 12) score++;
    if (RegExp(r'[A-Z]').hasMatch(p)) score++;
    if (RegExp(r'[0-9]').hasMatch(p)) score++;
    if (RegExp(r'[!@#\$%^&*(),.?":{}|<>_\-]').hasMatch(p)) score++;
    return score;
  }

  Color get _strengthColor {
    switch (_strength) {
      case 0:
      case 1:
        return VoltTheme.danger;
      case 2:
      case 3:
        return VoltTheme.warning;
      default:
        return VoltTheme.success;
    }
  }

  String get _strengthLabel {
    switch (_strength) {
      case 0:
      case 1:
        return 'Muy débil';
      case 2:
        return 'Débil';
      case 3:
        return 'Regular';
      case 4:
        return 'Fuerte';
      default:
        return 'Muy fuerte';
    }
  }

  Future<void> _setup() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final ok = await context
        .read<AuthProvider>()
        .setupMasterPassword(_passwordController.text);

    if (!ok && mounted) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error al configurar contraseña')),
      );
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                const Center(
                  child: Image(
                    image: AssetImage('assets/icons/app_icon.png'),
                    width: 160,
                    height: 160,
                  ),
                ),
                const SizedBox(height: 32),
                const Text(
                  'Bienvenido a KMD Volt',
                  style: TextStyle(
                    fontSize: 26,
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
                const SizedBox(height: 8),
                const Text(
                  'Crea tu contraseña maestra. Esta contraseña protege todo tu vault. Recuérdala bien — no hay forma de recuperarla.',
                  style: TextStyle(
                    color: VoltTheme.textSecondary,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 36),

                // Password field
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  style: const TextStyle(color: VoltTheme.textPrimary),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Contraseña maestra',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Campo requerido';
                    if (v.length < 8) return 'Mínimo 8 caracteres';
                    return null;
                  },
                ),

                if (_passwordController.text.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      ...List.generate(5, (i) => Expanded(
                        child: Container(
                          height: 4,
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            color: i < _strength
                                ? _strengthColor
                                : VoltTheme.border,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      )),
                      const SizedBox(width: 8),
                      Text(
                        _strengthLabel,
                        style: TextStyle(
                          color: _strengthColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 16),

                // Confirm field
                TextFormField(
                  controller: _confirmController,
                  obscureText: _obscureConfirm,
                  style: const TextStyle(color: VoltTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Confirmar contraseña',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirm
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Campo requerido';
                    if (v != _passwordController.text) {
                      return 'Las contraseñas no coinciden';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: VoltTheme.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: VoltTheme.primary.withOpacity(0.2)),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline,
                          color: VoltTheme.primaryLight, size: 16),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Tu vault se cifra localmente con AES-256. Nadie más puede acceder a tus contraseñas.',
                          style: TextStyle(
                            color: VoltTheme.primaryLight,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _setup,
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Crear Vault'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
