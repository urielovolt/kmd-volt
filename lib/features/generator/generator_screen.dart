import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme.dart';

class GeneratorScreen extends StatefulWidget {
  const GeneratorScreen({super.key});

  @override
  State<GeneratorScreen> createState() => _GeneratorScreenState();
}

class _GeneratorScreenState extends State<GeneratorScreen> {
  int _length = 16;
  bool _upper = true;
  bool _lower = true;
  bool _numbers = true;
  bool _symbols = true;
  bool _excludeAmbiguous = false;
  String _generated = '';
  final List<String> _history = [];
  final _random = Random.secure();

  @override
  void initState() {
    super.initState();
    _generate();
  }

  void _generate() {
    const upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    const lower = 'abcdefghijklmnopqrstuvwxyz';
    const numbers = '0123456789';
    const symbols = '!@#\$%^&*()_+-=[]{}|;:,.<>?';
    const ambiguous = 'Il1O0o';

    String chars = '';
    if (_upper) chars += upper;
    if (_lower) chars += lower;
    if (_numbers) chars += numbers;
    if (_symbols) chars += symbols;
    if (chars.isEmpty) chars = lower + numbers;

    if (_excludeAmbiguous) {
      chars = chars.split('').where((c) => !ambiguous.contains(c)).join();
    }

    final password = List.generate(
      _length,
      (_) => chars[_random.nextInt(chars.length)],
    ).join();

    setState(() {
      if (_generated.isNotEmpty && !_history.contains(_generated)) {
        _history.insert(0, _generated);
        if (_history.length > 10) _history.removeLast();
      }
      _generated = password;
    });
  }

  int get _strength {
    final p = _generated;
    int score = 0;
    if (p.length >= 8) score++;
    if (p.length >= 12) score++;
    if (p.length >= 16) score++;
    if (RegExp(r'[A-Z]').hasMatch(p)) score++;
    if (RegExp(r'[0-9]').hasMatch(p)) score++;
    if (RegExp(r'[!@#\$%^&*()]').hasMatch(p)) score++;
    return score.clamp(0, 5);
  }

  Color get _strengthColor {
    if (_strength <= 2) return VoltTheme.danger;
    if (_strength <= 3) return VoltTheme.warning;
    return VoltTheme.success;
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

  void _copy() {
    Clipboard.setData(ClipboardData(text: _generated));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Contraseña copiada al portapapeles'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),

            // Generated password display
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: VoltTheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: VoltTheme.border),
              ),
              child: Column(
                children: [
                  SelectableText(
                    _generated,
                    style: const TextStyle(
                      color: VoltTheme.textPrimary,
                      fontSize: 18,
                      fontFamily: 'monospace',
                      letterSpacing: 2,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      ...List.generate(
                        5,
                        (i) => Expanded(
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
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _strengthLabel,
                        style: TextStyle(
                          color: _strengthColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _copy,
                          icon: const Icon(Icons.copy_outlined, size: 16),
                          label: const Text('Copiar'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: VoltTheme.textPrimary,
                            side: const BorderSide(color: VoltTheme.border),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _generate,
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('Generar'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            _sectionLabel('OPCIONES'),
            const SizedBox(height: 12),

            // Length slider
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: VoltTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: VoltTheme.border),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Longitud',
                        style: TextStyle(
                          color: VoltTheme.textPrimary,
                          fontSize: 14,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: VoltTheme.primary.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$_length',
                          style: const TextStyle(
                            color: VoltTheme.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: _length.toDouble(),
                    min: 6,
                    max: 64,
                    divisions: 58,
                    activeColor: VoltTheme.primary,
                    inactiveColor: VoltTheme.border,
                    onChanged: (v) {
                      setState(() => _length = v.toInt());
                      _generate();
                    },
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('6',
                          style: TextStyle(
                              color: VoltTheme.textMuted, fontSize: 11)),
                      const Text('64',
                          style: TextStyle(
                              color: VoltTheme.textMuted, fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Character options
            Container(
              decoration: BoxDecoration(
                color: VoltTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: VoltTheme.border),
              ),
              child: Column(
                children: [
                  _optionTile('Mayúsculas  A–Z', Icons.text_fields, _upper,
                      (v) {
                    setState(() => _upper = v);
                    _generate();
                  }),
                  _divider(),
                  _optionTile('Minúsculas  a–z', Icons.text_fields_outlined,
                      _lower, (v) {
                    setState(() => _lower = v);
                    _generate();
                  }),
                  _divider(),
                  _optionTile('Números  0–9', Icons.tag, _numbers, (v) {
                    setState(() => _numbers = v);
                    _generate();
                  }),
                  _divider(),
                  _optionTile('Símbolos  !@#\$...', Icons.code, _symbols, (v) {
                    setState(() => _symbols = v);
                    _generate();
                  }),
                  _divider(),
                  _optionTile(
                    'Excluir caracteres ambiguos  (I l 1 O 0)',
                    Icons.block,
                    _excludeAmbiguous,
                    (v) {
                      setState(() => _excludeAmbiguous = v);
                      _generate();
                    },
                    subtitle: 'Evita confusiones al leer',
                  ),
                ],
              ),
            ),

            if (_history.isNotEmpty) ...[
              const SizedBox(height: 24),
              _sectionLabel('HISTORIAL'),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: VoltTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: VoltTheme.border),
                ),
                child: Column(
                  children: _history
                      .asMap()
                      .entries
                      .map(
                        (e) => Column(
                          children: [
                            if (e.key > 0) _divider(),
                            ListTile(
                              title: Text(
                                e.value,
                                style: const TextStyle(
                                  color: VoltTheme.textSecondary,
                                  fontFamily: 'monospace',
                                  fontSize: 13,
                                  letterSpacing: 1,
                                ),
                              ),
                              trailing: IconButton(
                                icon:
                                    const Icon(Icons.copy_outlined, size: 16),
                                onPressed: () {
                                  Clipboard.setData(
                                      ClipboardData(text: e.value));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Copiada'),
                                      duration: Duration(seconds: 1),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      )
                      .toList(),
                ),
              ),
            ],

            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: const TextStyle(
          color: VoltTheme.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      );

  Widget _divider() =>
      const Divider(height: 1, indent: 16, endIndent: 16);

  Widget _optionTile(
    String label,
    IconData icon,
    bool value,
    ValueChanged<bool> onChanged, {
    String? subtitle,
  }) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      title: Text(
        label,
        style: const TextStyle(
          color: VoltTheme.textPrimary,
          fontSize: 13,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: const TextStyle(
                  color: VoltTheme.textMuted, fontSize: 11),
            )
          : null,
      secondary: Icon(icon, color: VoltTheme.primary, size: 20),
      dense: true,
    );
  }
}
