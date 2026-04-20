import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/vault_provider.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _exporting = false;
  bool _importing = false;
  String? _lastBackupPath;

  Future<void> _export() async {
    final auth = context.read<AuthProvider>();
    final vault = context.read<VaultProvider>();

    if (auth.vaultKey == null) return;

    setState(() => _exporting = true);

    try {
      final json = await vault.exportToJson(auth.vaultKey!);
      final dir = await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
      final timestamp =
          DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final file = File('${dir.path}/kmd_volt_backup_$timestamp.volt');
      await file.writeAsString(json);

      setState(() => _lastBackupPath = file.path);

      if (mounted) {
        // Share the file
        await Share.shareXFiles(
          [XFile(file.path)],
          text: 'Respaldo KMD Volt',
          subject: 'kmd_volt_backup_$timestamp.volt',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al exportar: $e')),
        );
      }
    }

    if (mounted) setState(() => _exporting = false);
  }

  Future<void> _import() async {
    final auth = context.read<AuthProvider>();
    final vault = context.read<VaultProvider>();

    if (auth.vaultKey == null) return;

    setState(() => _importing = true);

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) {
        setState(() => _importing = false);
        return;
      }

      final file = File(result.files.single.path!);
      final json = await file.readAsString();

      // Confirm import
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Restaurar respaldo'),
          content: const Text(
            'Las entradas del respaldo se agregarán a tu vault actual. Las entradas con el mismo ID se sobrescribirán.\n\n¿Continuar?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Restaurar'),
            ),
          ],
        ),
      );

      if (confirmed != true) {
        setState(() => _importing = false);
        return;
      }

      await vault.importFromJson(json, auth.vaultKey!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Vault restaurado exitosamente'),
            backgroundColor: VoltTheme.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al restaurar: $e'),
            backgroundColor: VoltTheme.danger,
          ),
        );
      }
    }

    if (mounted) setState(() => _importing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Respaldo y restaurar')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info banner
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: VoltTheme.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: VoltTheme.primary.withOpacity(0.2)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.security_outlined,
                      color: VoltTheme.primaryLight, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Los respaldos están cifrados con tu contraseña maestra. Solo tú puedes restaurarlos.',
                      style: TextStyle(
                        color: VoltTheme.primaryLight,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),
            _sectionLabel('EXPORTAR'),
            const SizedBox(height: 12),

            Container(
              decoration: BoxDecoration(
                color: VoltTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: VoltTheme.border),
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Crear respaldo',
                    style: TextStyle(
                      color: VoltTheme.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Exporta tu vault cifrado como archivo .volt. Puedes guardarlo en tu laptop, Google Drive o cualquier lugar seguro.',
                    style: TextStyle(
                      color: VoltTheme.textSecondary,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  if (_lastBackupPath != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: VoltTheme.success.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: VoltTheme.success.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_outline,
                              color: VoltTheme.success, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _lastBackupPath!.split('/').last,
                              style: const TextStyle(
                                color: VoltTheme.success,
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _exporting ? null : _export,
                      icon: _exporting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.upload_outlined, size: 18),
                      label: Text(_exporting ? 'Exportando...' : 'Exportar y compartir'),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            _sectionLabel('RESTAURAR'),
            const SizedBox(height: 12),

            Container(
              decoration: BoxDecoration(
                color: VoltTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: VoltTheme.border),
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Restaurar desde respaldo',
                    style: TextStyle(
                      color: VoltTheme.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Selecciona un archivo .volt de respaldo para restaurar tus contraseñas. Necesitas la misma contraseña maestra con la que fue creado.',
                    style: TextStyle(
                      color: VoltTheme.textSecondary,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _importing ? null : _import,
                      icon: _importing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: VoltTheme.primary,
                              ),
                            )
                          : const Icon(Icons.download_outlined, size: 18),
                      label: Text(
                        _importing ? 'Restaurando...' : 'Seleccionar archivo',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: VoltTheme.primary,
                        side: const BorderSide(color: VoltTheme.primary),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            _sectionLabel('CÓMO HACER UN RESPALDO EN TU LAPTOP'),
            const SizedBox(height: 12),

            Container(
              decoration: BoxDecoration(
                color: VoltTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: VoltTheme.border),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _step('1', 'Exporta tu vault desde esta pantalla'),
                  _step('2',
                      'Comparte el archivo .volt por USB, correo o WhatsApp'),
                  _step('3', 'Guarda el archivo en tu laptop en un lugar seguro'),
                  _step('4',
                      'Para restaurar, transfiere el archivo de vuelta al celular y usa "Restaurar desde respaldo"'),
                ],
              ),
            ),

            const SizedBox(height: 40),
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

  Widget _step(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: VoltTheme.primary.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              number,
              style: const TextStyle(
                color: VoltTheme.primary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: VoltTheme.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
