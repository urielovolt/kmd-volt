import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// ─── Background tap handler (must be a top-level function) ───────────────────

/// Called when a notification is tapped while the app is fully terminated.
/// Runs in a background isolate — cannot touch UI.  The pending route is
/// surfaced on the next foreground launch via [NotificationService.init].
@pragma('vm:entry-point')
void onBackgroundNotificationTap(NotificationResponse response) {
  // No UI access here; launch-from-notification is handled in init().
}

// ─── NotificationService ─────────────────────────────────────────────────────

/// Wraps [FlutterLocalNotificationsPlugin] for KMD Volt.
///
/// Usage:
/// ```dart
/// await NotificationService.init();          // once, in main()
/// await NotificationService.requestPermission();
/// await NotificationService.showPasswordAgeAlert(3, 90);
/// ```
///
/// UI widgets that want to react to notification taps should listen to
/// [NotificationService.routeNotifier].
class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  // ── Channel constants ───────────────────────────────────────────────────────

  static const String _channelId   = 'password_health';
  static const String _channelName = 'Salud de contraseñas';
  static const String _channelDesc =
      'Alertas sobre contraseñas que necesitan actualizarse';

  /// Stable notification ID for the password-age alert.
  static const int _notifId = 42;

  // ── Route notifier ──────────────────────────────────────────────────────────

  /// Widgets can listen to this notifier to react when a notification tap
  /// requests navigation to a named route.
  ///
  /// The listener is responsible for resetting the value to `null` after
  /// handling it so that subsequent events are not ignored.
  static final ValueNotifier<String?> routeNotifier =
      ValueNotifier<String?>(null);

  // ── Initialization ──────────────────────────────────────────────────────────

  /// Initialises the plugin, creates the Android notification channel, and
  /// checks whether the app was launched by tapping a notification.
  ///
  /// Must be called once from [main] before [runApp].
  static Future<void> init() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    await _plugin.initialize(
      const InitializationSettings(android: androidSettings),
      onDidReceiveNotificationResponse: _onForegroundTap,
      onDidReceiveBackgroundNotificationResponse: onBackgroundNotificationTap,
    );

    // Ensure the notification channel exists on Android.
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDesc,
            importance: Importance.high,
          ),
        );

    // If the app was launched by tapping a notification (was killed), surface
    // the route now so HomeScreen can pick it up in initState.
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true) {
      final payload = launchDetails!.notificationResponse?.payload;
      if (payload == 'health') {
        routeNotifier.value = 'health';
      }
    }
  }

  // ── Permission ──────────────────────────────────────────────────────────────

  /// Requests the POST_NOTIFICATIONS runtime permission (Android 13+).
  static Future<void> requestPermission() async {
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  // ── Show notification ───────────────────────────────────────────────────────

  /// Shows a high-priority notification informing the user that [count]
  /// passwords haven't been changed in more than [days] days.
  ///
  /// Tapping the notification sets [routeNotifier] to `'health'`.
  static Future<void> showPasswordAgeAlert(int count, int days) async {
    final body = count == 1
        ? '1 contraseña lleva más de $days días sin cambiar. Toca para revisar.'
        : '$count contraseñas llevan más de $days días sin cambiar. Toca para revisar.';

    await _plugin.show(
      _notifId,
      'KMD Volt — Contraseñas antiguas',
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          styleInformation: BigTextStyleInformation(body),
        ),
      ),
      payload: 'health',
    );
  }

  // ── Private helpers ─────────────────────────────────────────────────────────

  static void _onForegroundTap(NotificationResponse response) {
    if (response.payload == 'health') {
      routeNotifier.value = 'health';
    }
  }
}
