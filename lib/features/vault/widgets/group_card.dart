import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../core/theme.dart';
import '../../../core/models/group_model.dart';
import '../../../core/group_icons.dart';

class GroupCard extends StatelessWidget {
  final GroupModel group;
  final int count;
  final VoidCallback onTap;

  const GroupCard({
    super.key,
    required this.group,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final svgPath = groupSvgFromCode(group.iconCode);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: VoltTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: VoltTheme.border),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SvgPicture.asset(
              svgPath,
              width: 28,
              height: 28,
            ),
            const Spacer(),
            Text(
              group.name,
              style: const TextStyle(
                color: VoltTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              '$count ${count == 1 ? 'entrada' : 'entradas'}',
              style: const TextStyle(
                color: VoltTheme.textMuted,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
