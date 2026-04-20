import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/services/clipboard_service.dart';
import '../../../core/theme.dart';
import '../../../core/models/entry_model.dart';

const int _kClearSeconds = 12;

class EntryListTile extends StatefulWidget {
  final EntryModel entry;
  final VoidCallback onTap;
  final bool showGroup;

  const EntryListTile({
    super.key,
    required this.entry,
    required this.onTap,
    this.showGroup = false,
  });

  @override
  State<EntryListTile> createState() => _EntryListTileState();
}

class _EntryListTileState extends State<EntryListTile> {
  Timer? _clearTimer;
  Timer? _countdownTimer;
  int? _countdown; // null = idle, N = seconds remaining before clipboard clears

  @override
  void dispose() {
    _clearTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _copyPassword() {
    // Cancel any running timers before starting a new copy
    _clearTimer?.cancel();
    _countdownTimer?.cancel();

    Clipboard.setData(ClipboardData(text: widget.entry.password));
    setState(() => _countdown = _kClearSeconds);

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '🔐 Contraseña de "${widget.entry.title}" copiada · '
          'el portapapeles se limpiará en ${_kClearSeconds}s',
        ),
        duration: const Duration(seconds: _kClearSeconds),
      ),
    );

    // Tick down every second so the button shows the remaining time
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        if (_countdown != null && _countdown! > 1) {
          _countdown = _countdown! - 1;
        } else {
          _countdown = null;
          t.cancel();
        }
      });
    });

    // Actually wipe the clipboard when the countdown hits zero
    _clearTimer = Timer(const Duration(seconds: _kClearSeconds), () {
      ClipboardService.clear();
    });
  }

  String _initials() {
    final t = widget.entry.title.trim();
    if (t.isEmpty) return '?';
    if (t.length == 1) return t.toUpperCase();
    return t.substring(0, 2).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final counting = _countdown != null;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: VoltTheme.primary.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: VoltTheme.primary.withOpacity(0.2),
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          _initials(),
          style: const TextStyle(
            color: VoltTheme.primary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      title: Text(
        widget.entry.title,
        style: const TextStyle(
          color: VoltTheme.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        widget.entry.username.isNotEmpty
            ? widget.entry.username
            : widget.entry.url,
        style: const TextStyle(
          color: VoltTheme.textMuted,
          fontSize: 12,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.entry.isFavorite)
            const Icon(Icons.star, color: VoltTheme.warning, size: 16),
          const SizedBox(width: 4),
          // Copy button — shows countdown while clipboard is pending clear
          SizedBox(
            width: 36,
            height: 36,
            child: counting
                ? Tooltip(
                    message: 'Portapapeles se limpiará pronto',
                    child: Center(
                      child: Text(
                        '$_countdown',
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
                    onPressed: _copyPassword,
                    tooltip: 'Copiar contraseña',
                    style: IconButton.styleFrom(
                      foregroundColor: VoltTheme.textMuted,
                    ),
                  ),
          ),
        ],
      ),
      onTap: widget.onTap,
    );
  }
}
