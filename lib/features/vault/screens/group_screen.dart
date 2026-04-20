import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import '../../../core/theme.dart';
import '../../../core/models/group_model.dart';
import '../../../core/group_icons.dart';
import '../../../providers/vault_provider.dart';
import '../widgets/entry_list_tile.dart';
import 'entry_edit_screen.dart';

class GroupScreen extends StatelessWidget {
  final GroupModel group;

  const GroupScreen({super.key, required this.group});

  @override
  Widget build(BuildContext context) {
    final svgPath = groupSvgFromCode(group.iconCode);
    final vault = context.watch<VaultProvider>();
    final entries = vault.entries
        .where((e) => e.groupId == group.id)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            SvgPicture.asset(
              svgPath,
              width: 20,
              height: 20,
            ),
            const SizedBox(width: 10),
            Text(group.name),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => EntryEditScreen(groupId: group.id),
              ),
            ),
          ),
        ],
      ),
      body: entries.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SvgPicture.asset(
                    svgPath,
                    width: 48,
                    height: 48,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Sin entradas en este grupo',
                    style: TextStyle(color: VoltTheme.textMuted, fontSize: 15),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EntryEditScreen(groupId: group.id),
                      ),
                    ),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Agregar entrada'),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: entries.length,
              separatorBuilder: (context, idx) =>
                  const Divider(height: 1, indent: 72),
              itemBuilder: (context, i) => EntryListTile(
                entry: entries[i],
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EntryEditScreen(entry: entries[i]),
                  ),
                ),
              ),
            ),
    );
  }
}
