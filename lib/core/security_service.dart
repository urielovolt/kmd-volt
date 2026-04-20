import 'package:flutter/services.dart';

/// Bridges Flutter to the Android security MethodChannel.
/// Controls FLAG_SECURE (prevents screenshots and recent-apps thumbnails).
class SecurityService {
  static const _channel = MethodChannel('com.kmd.kmd_volt/security');

  /// Enable or disable FLAG_SECURE. Persisted across restarts.
  /// Defaults to enabled (true) on first launch.
  static Future<void> setSecureScreen(bool enabled) async {
    try {
      await _channel.invokeMethod('setSecureScreen', {'enabled': enabled});
    } catch (_) {}
  }

  /// Returns whether FLAG_SECURE is currently enabled.
  static Future<bool> isSecureScreen() async {
    try {
      return await _channel.invokeMethod<bool>('isSecureScreen') ?? true;
    } catch (_) {
      return true;
    }
  }
}
