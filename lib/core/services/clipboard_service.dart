import 'package:flutter/services.dart';

/// Provides secure clipboard operations via the native Android clipboard API.
///
/// - [copySecure]: copies text marked as sensitive so keyboard apps (Gboard,
///   etc.) hide it from their clipboard history on Android 13+.
/// - [clear]: calls [ClipboardManager.clearPrimaryClip()] to remove the
///   current clipboard content without leaving a blank entry in history.
class ClipboardService {
  static const _channel = MethodChannel('com.kmd.kmd_volt/clipboard');

  /// Copies [text] to the clipboard marked as sensitive.
  ///
  /// On Android 13+ (API 33) the system and Gboard / most modern keyboards
  /// will NOT store this in their clipboard history, preventing the password
  /// from appearing in the keyboard's clipboard panel.
  /// On older versions a normal copy is performed (no API available to hide
  /// content from third-party keyboard history on those versions).
  static Future<void> copySecure(String text) async {
    try {
      await _channel.invokeMethod<void>('copySecure', {'text': text});
    } on PlatformException {
      // Fallback to Flutter's standard copy if the channel is unavailable.
      await Clipboard.setData(ClipboardData(text: text));
    }
  }

  /// Clears the system clipboard.
  ///
  /// On Android this invokes the native [clearPrimaryClip()] call.  On older
  /// API levels (< 28) the native side falls back to overwriting with empty
  /// text.
  static Future<void> clear() async {
    try {
      await _channel.invokeMethod<void>('clearClipboard');
    } on PlatformException {
      await Clipboard.setData(const ClipboardData(text: ''));
    }
  }
}
