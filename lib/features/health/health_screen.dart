import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/models/entry_model.dart';
import '../../providers/vault_provider.dart';
import '../vault/screens/entry_edit_screen.dart';

class HealthScreen extends StatelessWidget {
  const HealthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vault = context.watch<VaultProvider>();
    final entries = vault.entries;

    if (entries.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.health_and_safety_outlined,
                color: VoltTheme.textMuted, size: 48),
            SizedBox(height: 12),
            Text(
              'Sin entradas para analizar',
              style: TextStyle(color: VoltTheme.textMuted, fontSize: 15),
            ),
          ],
        ),
      );
    }

    final analysis = _analyze(entries);
    final score = _score(analysis);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),

          // Score card
          _ScoreCard(score: score, total: entries.length),

          const SizedBox(height: 24),

          // Weak passwords
          if (analysis.weak.isNotEmpty) ...[
            _sectionLabel('CONTRASEÑAS DÉBILES', VoltTheme.danger,
                Icons.warning_amber_outlined, analysis.weak.length),
            const SizedBox(height: 8),
            _EntryGroup(
              entries: analysis.weak,
              subtitle: (e) => _strengthLabel(_passwordStrength(e.password)),
              color: VoltTheme.danger,
            ),
            const SizedBox(height: 20),
          ],

          // Duplicate passwords
          if (analysis.duplicates.isNotEmpty) ...[
            _sectionLabel('CONTRASEÑAS REPETIDAS', VoltTheme.warning,
                Icons.copy_outlined, analysis.duplicates.length),
            const SizedBox(height: 8),
            _EntryGroup(
              entries: analysis.duplicates,
              subtitle: (e) => 'Misma contraseña en otras entradas',
              color: VoltTheme.warning,
            ),
            const SizedBox(height: 20),
          ],

          // Old passwords
          if (analysis.old.isNotEmpty) ...[
            _sectionLabel('SIN ACTUALIZAR (+90 días)', VoltTheme.accentGold,
                Icons.schedule_outlined, analysis.old.length),
            const SizedBox(height: 8),
            _EntryGroup(
              entries: analysis.old,
              subtitle: (e) {
                final days =
                    DateTime.now().difference(e.updatedAt).inDays;
                return 'Hace $days días';
              },
              color: VoltTheme.accentGold,
            ),
            const SizedBox(height: 20),
          ],

          // No password entries
          if (analysis.noPassword.isNotEmpty) ...[
            _sectionLabel('SIN CONTRASEÑA', VoltTheme.textMuted,
                Icons.lock_open_outlined, analysis.noPassword.length),
            const SizedBox(height: 8),
            _EntryGroup(
              entries: analysis.noPassword,
              subtitle: (_) => 'Agregar contraseña recomendado',
              color: VoltTheme.textMuted,
            ),
            const SizedBox(height: 20),
          ],

          // All good
          if (analysis.weak.isEmpty &&
              analysis.duplicates.isEmpty &&
              analysis.old.isEmpty &&
              analysis.noPassword.isEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: VoltTheme.success.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: VoltTheme.success.withOpacity(0.3)),
              ),
              child: const Column(
                children: [
                  Icon(Icons.verified_outlined,
                      color: VoltTheme.success, size: 40),
                  SizedBox(height: 12),
                  Text(
                    '¡Todo en orden!',
                    style: TextStyle(
                      color: VoltTheme.success,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Todas tus contraseñas están en buen estado.',
                    style: TextStyle(
                      color: VoltTheme.textSecondary,
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _sectionLabel(
      String text, Color color, IconData icon, int count) {
    return Row(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  _Analysis _analyze(List<EntryModel> entries) {
    final weak = <EntryModel>[];
    final duplicates = <EntryModel>[];
    final old = <EntryModel>[];
    final noPassword = <EntryModel>[];

    final passwordCount = <String, int>{};
    for (final e in entries) {
      if (e.password.isNotEmpty) {
        passwordCount[e.password] = (passwordCount[e.password] ?? 0) + 1;
      }
    }

    final now = DateTime.now();

    for (final e in entries) {
      if (e.password.isEmpty) {
        noPassword.add(e);
        continue;
      }
      if (_passwordStrength(e.password) < 3) weak.add(e);
      if ((passwordCount[e.password] ?? 0) > 1) duplicates.add(e);
      if (now.difference(e.updatedAt).inDays > 90) old.add(e);
    }

    return _Analysis(
      weak: weak,
      duplicates: duplicates,
      old: old,
      noPassword: noPassword,
    );
  }

  int _score(_Analysis a) {
    int issues = a.weak.length + a.duplicates.length + a.noPassword.length;
    if (issues == 0) return 100;
    return (100 - (issues * 10)).clamp(0, 100);
  }

  static int _passwordStrength(String p) {
    if (p.isEmpty) return 0;
    int score = 0;
    if (p.length >= 8) score++;
    if (p.length >= 12) score++;
    if (RegExp(r'[A-Z]').hasMatch(p)) score++;
    if (RegExp(r'[0-9]').hasMatch(p)) score++;
    if (RegExp(r'[!@#\$%^&*()_\-+=\[\]{}|;:,.<>?]').hasMatch(p)) score++;
    return score;
  }

  static String _strengthLabel(int s) {
    switch (s) {
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
}

class _Analysis {
  final List<EntryModel> weak;
  final List<EntryModel> duplicates;
  final List<EntryModel> old;
  final List<EntryModel> noPassword;

  _Analysis({
    required this.weak,
    required this.duplicates,
    required this.old,
    required this.noPassword,
  });
}

// ─── Score Card ──────────────────────────────────────────────────────────────

class _ScoreCard extends StatelessWidget {
  final int score;
  final int total;

  const _ScoreCard({required this.score, required this.total});

  Color get _color {
    if (score >= 80) return VoltTheme.success;
    if (score >= 50) return VoltTheme.warning;
    return VoltTheme.danger;
  }

  String get _label {
    if (score >= 80) return 'Buena seguridad';
    if (score >= 50) return 'Seguridad regular';
    return 'Seguridad baja';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: VoltTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: VoltTheme.border),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Puntuación de seguridad',
                    style: TextStyle(
                      color: VoltTheme.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _label,
                    style: TextStyle(
                      color: _color,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '$total contraseñas analizadas',
                    style: const TextStyle(
                      color: VoltTheme.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              SizedBox(
                width: 70,
                height: 70,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: score / 100,
                      strokeWidth: 6,
                      backgroundColor: VoltTheme.border,
                      valueColor: AlwaysStoppedAnimation(_color),
                    ),
                    Text(
                      '$score',
                      style: TextStyle(
                        color: _color,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Entry Group ─────────────────────────────────────────────────────────────

class _EntryGroup extends StatelessWidget {
  final List<EntryModel> entries;
  final String Function(EntryModel) subtitle;
  final Color color;

  const _EntryGroup({
    required this.entries,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: VoltTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: VoltTheme.border),
      ),
      child: Column(
        children: entries.asMap().entries.map((e) {
          final idx = e.key;
          final entry = e.value;
          return Column(
            children: [
              if (idx > 0)
                const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    entry.title.isNotEmpty
                        ? entry.title.substring(0, 1).toUpperCase()
                        : '?',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                title: Text(
                  entry.title,
                  style: const TextStyle(
                    color: VoltTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: Text(
                  subtitle(entry),
                  style: TextStyle(color: color, fontSize: 12),
                ),
                trailing: const Icon(
                  Icons.arrow_forward_ios,
                  color: VoltTheme.textMuted,
                  size: 14,
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EntryEditScreen(entry: entry),
                  ),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}
