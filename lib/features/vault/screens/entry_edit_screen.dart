import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/services/clipboard_service.dart';
import '../../../core/theme.dart';
import '../../../core/models/entry_model.dart';
import '../../../providers/vault_provider.dart';

class EntryEditScreen extends StatefulWidget {
  final EntryModel? entry;
  final String? groupId;

  // Pre-filled values used when creating an entry from an autofill save request.
  final String? initialTitle;
  final String? initialUsername;
  final String? initialPassword;
  final String? initialUrl;

  const EntryEditScreen({
    super.key,
    this.entry,
    this.groupId,
    this.initialTitle,
    this.initialUsername,
    this.initialPassword,
    this.initialUrl,
  });

  @override
  State<EntryEditScreen> createState() => _EntryEditScreenState();
}

class _EntryEditScreenState extends State<EntryEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _passwordCtrl;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _notesCtrl;

  bool _obscurePassword = true;
  bool _isFavorite = false;
  late String _groupId;
  bool _saving = false;

  // ── Clipboard countdown display (actual clear is managed by ClipboardService)
  Timer? _usernameCountdownTimer;
  int? _usernameCountdown;

  Timer? _passwordCountdownTimer;
  int? _passwordCountdown;

  bool get _isEditing => widget.entry != null;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _titleCtrl    = TextEditingController(text: e?.title    ?? widget.initialTitle    ?? '');
    _usernameCtrl = TextEditingController(text: e?.username ?? widget.initialUsername ?? '');
    _passwordCtrl = TextEditingController(text: e?.password ?? widget.initialPassword ?? '');
    _urlCtrl      = TextEditingController(text: e?.url      ?? widget.initialUrl      ?? '');
    _notesCtrl    = TextEditingController(text: e?.notes    ?? '');
    _isFavorite = e?.isFavorite ?? false;
    _groupId = e?.groupId ?? widget.groupId ?? '';
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _urlCtrl.dispose();
    _notesCtrl.dispose();
    _usernameCountdownTimer?.cancel();
    _passwordCountdownTimer?.cancel();
    // NOTE: do NOT cancel the ClipboardService timer here — it must survive
    // widget disposal so the clipboard is cleared even after the user navigates
    // away to paste the password in another app.
    super.dispose();
  }

  void _copyUsername() {
    _usernameCountdownTimer?.cancel();
    // copySecure handles the actual timed clear at the service level.
    ClipboardService.copySecure(_usernameCtrl.text);
    setState(() => _usernameCountdown = ClipboardService.kClearSeconds);

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '👤 Usuario copiado · portapapeles se limpiará en ${ClipboardService.kClearSeconds}s',
        ),
        duration: Duration(seconds: ClipboardService.kClearSeconds),
      ),
    );

    _usernameCountdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        if (_usernameCountdown != null && _usernameCountdown! > 1) {
          _usernameCountdown = _usernameCountdown! - 1;
        } else {
          _usernameCountdown = null;
          t.cancel();
        }
      });
    });
  }

  void _copyPassword() {
    _passwordCountdownTimer?.cancel();
    ClipboardService.copySecure(_passwordCtrl.text);
    setState(() => _passwordCountdown = ClipboardService.kClearSeconds);

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '🔐 Contraseña copiada · portapapeles se limpiará en ${ClipboardService.kClearSeconds}s',
        ),
        duration: Duration(seconds: ClipboardService.kClearSeconds),
      ),
    );

    _passwordCountdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        if (_passwordCountdown != null && _passwordCountdown! > 1) {
          _passwordCountdown = _passwordCountdown! - 1;
        } else {
          _passwordCountdown = null;
          t.cancel();
        }
      });
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final vault = context.read<VaultProvider>();

    if (_isEditing) {
      final updated = widget.entry!.copyWith(
        title: _titleCtrl.text.trim(),
        username: _usernameCtrl.text.trim(),
        password: _passwordCtrl.text,
        url: _urlCtrl.text.trim(),
        notes: _notesCtrl.text.trim(),
        isFavorite: _isFavorite,
        groupId: _groupId,
      );
      await vault.updateEntry(updated);
    } else {
      final entry = EntryModel(
        groupId: _groupId,
        title: _titleCtrl.text.trim(),
        username: _usernameCtrl.text.trim(),
        password: _passwordCtrl.text,
        url: _urlCtrl.text.trim(),
        notes: _notesCtrl.text.trim(),
        isFavorite: _isFavorite,
      );
      await vault.addEntry(entry);
    }

    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar entrada'),
        content: Text(
          '¿Eliminar "${widget.entry!.title}"? Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Eliminar',
              style: TextStyle(color: VoltTheme.danger),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await context.read<VaultProvider>().deleteEntry(widget.entry!.id);
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _openGenerator() async {
    final password = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _GeneratorSheet(),
    );
    if (password != null && mounted) {
      _passwordCtrl.text = password;
    }
  }

  @override
  Widget build(BuildContext context) {
    final vault = context.watch<VaultProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Editar entrada' : 'Nueva entrada'),
        actions: [
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: VoltTheme.danger),
              onPressed: _delete,
            ),
          IconButton(
            icon: const Icon(Icons.check, color: VoltTheme.primary),
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Group selector
              if (vault.groups.isNotEmpty) ...[
                const _SectionLabel('GRUPO'),
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(
                    color: VoltTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: VoltTheme.border),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _groupId.isEmpty
                          ? vault.groups.first.id
                          : _groupId,
                      dropdownColor: VoltTheme.surfaceVariant,
                      isExpanded: true,
                      style: const TextStyle(
                        color: VoltTheme.textPrimary,
                        fontSize: 14,
                      ),
                      items: vault.groups
                          .map((g) => DropdownMenuItem(
                                value: g.id,
                                child: Text(g.name),
                              ))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _groupId = v ?? _groupId),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Title
              const _SectionLabel('TÍTULO'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _titleCtrl,
                style: const TextStyle(color: VoltTheme.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'ej. Facebook, Gmail...',
                  prefixIcon: Icon(Icons.label_outline),
                ),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Campo requerido' : null,
              ),

              const SizedBox(height: 16),

              // Username
              const _SectionLabel('USUARIO / EMAIL'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _usernameCtrl,
                style: const TextStyle(color: VoltTheme.textPrimary),
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: 'usuario@email.com',
                  prefixIcon: const Icon(Icons.person_outline),
                  suffixIcon: _usernameCtrl.text.isNotEmpty
                      ? (_usernameCountdown != null
                          ? Tooltip(
                              message: 'Portapapeles se limpiará pronto',
                              child: Padding(
                                padding: const EdgeInsets.only(right: 12),
                                child: Text(
                                  '$_usernameCountdown',
                                  style: const TextStyle(
                                    color: VoltTheme.warning,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            )
                          : IconButton(
                              icon: const Icon(Icons.copy_outlined, size: 18),
                              onPressed: _copyUsername,
                            ))
                      : null,
                ),
              ),

              const SizedBox(height: 16),

              // Password
              const _SectionLabel('CONTRASEÑA'),
              const SizedBox(height: 6),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _passwordCtrl,
                builder: (context, value, child) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      child!,
                      _PasswordStrengthBar(strength: _calcStrength(value.text)),
                    ],
                  );
                },
                child: TextFormField(
                  controller: _passwordCtrl,
                  obscureText: _obscurePassword,
                style: const TextStyle(
                  color: VoltTheme.textPrimary,
                  fontFamily: 'monospace',
                  letterSpacing: 1,
                ),
                decoration: InputDecoration(
                  hintText: 'Contraseña',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 20,
                        ),
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                      ),
                      _passwordCountdown != null
                          ? Tooltip(
                              message: 'Portapapeles se limpiará pronto',
                              child: SizedBox(
                                width: 36,
                                child: Center(
                                  child: Text(
                                    '$_passwordCountdown',
                                    style: const TextStyle(
                                      color: VoltTheme.warning,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            )
                          : IconButton(
                              icon: const Icon(Icons.copy_outlined, size: 18),
                              onPressed: _copyPassword,
                            ),
                      IconButton(
                        icon: const Icon(Icons.casino_outlined, size: 18),
                        onPressed: _openGenerator,
                        tooltip: 'Generar',
                      ),
                    ],
                  ),
                ),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Campo requerido' : null,
                ),
              ),

              const SizedBox(height: 16),

              // URL
              const _SectionLabel('URL / SITIO WEB'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _urlCtrl,
                style: const TextStyle(color: VoltTheme.textPrimary),
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  hintText: 'https://...',
                  prefixIcon: Icon(Icons.link_outlined),
                ),
              ),

              const SizedBox(height: 16),

              // Notes
              const _SectionLabel('NOTAS'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _notesCtrl,
                style: const TextStyle(color: VoltTheme.textPrimary),
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Información adicional...',
                  prefixIcon: Padding(
                    padding: EdgeInsets.only(bottom: 56),
                    child: Icon(Icons.notes_outlined),
                  ),
                  alignLabelWithHint: true,
                ),
              ),

              const SizedBox(height: 16),

              // Favorite toggle
              Container(
                decoration: BoxDecoration(
                  color: VoltTheme.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: VoltTheme.border),
                ),
                child: SwitchListTile(
                  title: const Text(
                    'Marcar como favorito',
                    style: TextStyle(
                      color: VoltTheme.textPrimary,
                      fontSize: 14,
                    ),
                  ),
                  secondary: const Icon(Icons.star_outline,
                      color: VoltTheme.warning),
                  value: _isFavorite,
                  onChanged: (v) => setState(() => _isFavorite = v),
                ),
              ),

              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(_isEditing ? 'Guardar cambios' : 'Crear entrada'),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Password strength helpers ────────────────────────────────────────────────

int _calcStrength(String p) {
  if (p.isEmpty) return 0;
  int score = 0;
  if (p.length >= 8) score++;
  if (p.length >= 12) score++;
  if (RegExp(r'[A-Z]').hasMatch(p)) score++;
  if (RegExp(r'[0-9]').hasMatch(p)) score++;
  if (RegExp(r'[!@#\$%^&*()_\-+=\[\]{}|;:,.<>?]').hasMatch(p)) score++;
  return score;
}

class _PasswordStrengthBar extends StatelessWidget {
  final int strength; // 0–5

  const _PasswordStrengthBar({required this.strength});

  Color get _color {
    if (strength <= 1) return VoltTheme.danger;
    if (strength == 2) return VoltTheme.warning;
    if (strength == 3) return VoltTheme.accentGold;
    return VoltTheme.success;
  }

  String get _label {
    if (strength == 0) return '';
    if (strength <= 1) return 'Muy débil';
    if (strength == 2) return 'Débil';
    if (strength == 3) return 'Regular';
    if (strength == 4) return 'Fuerte';
    return 'Muy fuerte';
  }

  @override
  Widget build(BuildContext context) {
    if (strength == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 2, right: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: List.generate(5, (i) {
              return Expanded(
                child: Container(
                  height: 3,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: i < strength ? _color : VoltTheme.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 4),
          Text(
            _label,
            style: TextStyle(
              color: _color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: VoltTheme.textMuted,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.1,
      ),
    );
  }
}

// Bottom sheet generator
class _GeneratorSheet extends StatefulWidget {
  const _GeneratorSheet();

  @override
  State<_GeneratorSheet> createState() => _GeneratorSheetState();
}

class _GeneratorSheetState extends State<_GeneratorSheet> {
  int _length = 16;
  bool _upper = true;
  bool _lower = true;
  bool _numbers = true;
  bool _symbols = true;
  String _generated = '';

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

    String chars = '';
    if (_upper) chars += upper;
    if (_lower) chars += lower;
    if (_numbers) chars += numbers;
    if (_symbols) chars += symbols;
    if (chars.isEmpty) chars = lower;

    final rng = Random.secure();
    final sb = StringBuffer();
    for (int i = 0; i < _length; i++) {
      sb.write(chars[rng.nextInt(chars.length)]);
    }

    setState(() => _generated = sb.toString());
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      builder: (_, ctrl) => SingleChildScrollView(
        controller: ctrl,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: VoltTheme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Generador de contraseña',
              style: TextStyle(
                color: VoltTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: VoltTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: VoltTheme.border),
              ),
              child: Text(
                _generated,
                style: const TextStyle(
                  color: VoltTheme.primary,
                  fontSize: 16,
                  fontFamily: 'monospace',
                  letterSpacing: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Longitud: ',
                    style: TextStyle(color: VoltTheme.textSecondary)),
                Text(
                  '$_length',
                  style: const TextStyle(
                      color: VoltTheme.primary, fontWeight: FontWeight.w700),
                ),
                Expanded(
                  child: Slider(
                    value: _length.toDouble(),
                    min: 8,
                    max: 32,
                    divisions: 24,
                    activeColor: VoltTheme.primary,
                    onChanged: (v) {
                      setState(() => _length = v.toInt());
                      _generate();
                    },
                  ),
                ),
              ],
            ),
            _toggle('Mayúsculas (A-Z)', _upper, (v) {
              setState(() => _upper = v);
              _generate();
            }),
            _toggle('Minúsculas (a-z)', _lower, (v) {
              setState(() => _lower = v);
              _generate();
            }),
            _toggle('Números (0-9)', _numbers, (v) {
              setState(() => _numbers = v);
              _generate();
            }),
            _toggle('Símbolos (!@#\$...)', _symbols, (v) {
              setState(() => _symbols = v);
              _generate();
            }),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _generate,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Regenerar'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: VoltTheme.textSecondary,
                      side: const BorderSide(color: VoltTheme.border),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context, _generated),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Usar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(color: VoltTheme.textSecondary, fontSize: 13)),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}
