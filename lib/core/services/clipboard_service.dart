import 'package:flutter/services.dart';

/// Provides a platform-backed clipboard clear that calls
/// [ClipboardManager.clearPrimaryClip()] on Android (API 28+) instead of
/// writing an empty string, which would leave a visible blank entry in
/// clipboard history managers.
class ClipboardService {
  static const _channel = MethodChannel('com.kmd.kmd_volt/clipboard');

  /// Clears the system clipboard.
  ///
  /// On Android this invokes the native [clearPrimaryClip()] call.  On older
  /// API levels (< 28) the native side falls back to overwriting with empty
  /// text, which is functionally equivalent to what the old Dart-only
  /// implementation did but is now executed via the same code path.
  static Future<void> clear() async {
    try {
      await _channel.invokeMethod<void>('clearClipboard');
    } on PlatformException {
      // Fallback: overwrite with empty string if the channel fails for any
      // reason (e.g. running on iOS or a test environment).
      await Clipboard.setData(const ClipboardData(text: ''));
    }
  }
}
