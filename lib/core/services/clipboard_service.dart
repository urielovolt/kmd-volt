import 'dart:async';
import 'package:flutter/services.dart';

/// Provides secure clipboard operations via the native Android clipboard API.
///
/// Clipboard clearing is managed here at the service level (not inside widgets)
/// so that timers survive screen navigation and widget disposal.
///
/// Two-layer clearing strategy:
///   1. A Dart [Timer] tries to clear after [kClearSeconds] seconds — works
///      when the app is in the foreground.
///   2. [clearIfOverdue] should be called whenever the app comes back to the
///      foreground (see AppRouter) to catch cases where the timer fired while
///      the app was in the background (Android 10+ blocks clipboard writes from
///      background apps, so the first attempt may have silently failed).
class ClipboardService {
  static const _channel = MethodChannel('com.kmd.kmd_volt/clipboard');

  /// How many seconds until the clipboard is automatically cleared.
  static const int kClearSeconds = 12;

  // Global timer — survives widget disposal.
  static Timer? _clearTimer;
  static DateTime? _clearDeadline;

  /// Copies [text] to the clipboard marked as sensitive, then schedules an
  /// automatic clear after [kClearSeconds] seconds.
  ///
  /// On Android 13+ (API 33) the EXTRA_IS_SENSITIVE flag prevents Gboard and
  /// other modern keyboards from showing the content in their clipboard history.
  static Future<void> copySecure(String text) async {
    // Cancel any previous pending clear before starting a new one.
    _clearTimer?.cancel();
    _clearDeadline = DateTime.now().add(const Duration(seconds: kClearSeconds));

    try {
      await _channel.invokeMethod<void>('copySecure', {'text': text});
    } on PlatformException {
      await Clipboard.setData(ClipboardData(text: text));
    }

    // Attempt 1: clear after the deadline (succeeds when app is in foreground).
    _clearTimer = Timer(const Duration(seconds: kClearSeconds), () {
      clear();
      _clearTimer = null;
      _clearDeadline = null;
    });
  }

  /// Attempt 2: call this when the app resumes to the foreground.
  ///
  /// If the deadline has already passed (timer fired while in background and
  /// the native clear was silently blocked), this performs the clear now that
  /// the app has focus again.
  static Future<void> clearIfOverdue() async {
    final deadline = _clearDeadline;
    if (deadline != null && DateTime.now().isAfter(deadline)) {
      _clearTimer?.cancel();
      _clearTimer = null;
      _clearDeadline = null;
      await clear();
    }
  }

  /// Immediately cancels any pending auto-clear and wipes the clipboard.
  /// Call this when the vault is locked.
  static Future<void> clearAndCancel() async {
    _clearTimer?.cancel();
    _clearTimer = null;
    _clearDeadline = null;
    await clear();
  }

  /// Clears the system clipboard.
  ///
  /// On Android 28+ calls [clearPrimaryClip()].
  /// On older API levels overwrites with an empty string.
  static Future<void> clear() async {
    try {
      await _channel.invokeMethod<void>('clearClipboard');
    } on PlatformException {
      await Clipboard.setData(const ClipboardData(text: ''));
    }
  }
}
