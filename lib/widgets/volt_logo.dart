import 'package:flutter/material.dart';
import '../core/theme.dart';

class VoltLogo extends StatelessWidget {
  final double size;

  const VoltLogo({super.key, this.size = 56});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: VoltTheme.primary.withOpacity(0.12),
        borderRadius: BorderRadius.circular(size * 0.22),
        border: Border.all(
          color: VoltTheme.primary.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.bolt,
          color: VoltTheme.primary,
          size: size * 0.56,
        ),
      ),
    );
  }
}
