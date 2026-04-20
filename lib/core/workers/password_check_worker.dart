import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:workmanager/workmanager.dart';

// ─── Secure-storage key constants ────────────────────────────────────────────

/// Whether password-age notifications are enabled (stored as 'true'/'false').
const kNotifEnabledKey = 'kmd_notif_enabled';

/// How many days before a password is considered outdated (stored as a string
/// integer, default '90').
const kNotifThresholdDaysKey = 'kmd_notif_threshold_days';

// ─── Notification channel constants ──────────────────────────────────────────

const _channelId   = 'password_health';
const _channelName = 'Salud de contraseñas';
const _channelDesc = 'Alertas sobre contraseñas que necesitan actualizarse';
const _notifId     = 42;

// ─── WorkManager task identifiers ────────────────────────────────────────────

/// Unique name used to register / cancel the periodic WorkManager task.
const _uniqueTaskName = 'password_age_check';

/// Task name passed to [Workmanager.executeTask].
const kPasswordAgeTaskName = 'password_age_check';

// ─── callbackDispatcher (top-level, vm:entry-point) ──────────────────────────

/// Entry point called by WorkManager on a background Dart isolate.
///
/// Must be a top-level function annotated with [pragma('vm:entry-point')] so
/// that the Dart VM can locate it when the app is not running in the foreground.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName != kPasswordAgeTaskName) return true;

    try {
      WidgetsFlutterBinding.ensureInitialized();

      const storage = FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
      );

      // Bail out early if the user has disabled notifications.
      final enabled = await storage.read(key: kNotifEnabledKey);
      if (enabled != 'true') return true;

      // Read the configured threshold (defaults to 90 days).
      final daysStr  = await storage.read(key: kNotifThresholdDaysKey) ?? '90';
      final days     = int.tryParse(daysStr) ?? 90;

      // Resolve the database path (same logic as DatabaseService._initDb).
      final dbsPath = await getDatabasesPath();
      final dbPath  = p.join(dbsPath, 'kmd_volt.db');

      // Open the database (read-only check on updated_at — no decryption needed).
      late Database db;
      try {
        db = await openDatabase(dbPath);
      } catch (_) {
        return true; // DB not accessible in background — skip silently
      }

      // Count entries whose password hasn't been changed within [days] days.
      // We only inspect `updated_at` (a plain integer ms-since-epoch) so no
      // per-field decryption is required.
      final threshold = DateTime.now()
          .subtract(Duration(days: days))
          .millisecondsSinceEpoch;

      final rows = await db.rawQuery(
        "SELECT COUNT(*) AS cnt FROM entries "
        "WHERE updated_at < ? AND password != ''",
        [threshold],
      );
      await db.close();

      final count = (rows.isNotEmpty ? rows.first['cnt'] as int? : null) ?? 0;
      if (count <= 0) return true;

      // ── Show notification ─────────────────────────────────────────────────

      final plugin = FlutterLocalNotificationsPlugin();

      await plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );

      // Ensure the channel exists (idempotent on subsequent calls).
      await plugin
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

      final body = count == 1
          ? '1 contraseña lleva más de $days días sin cambiar. Toca para revisar.'
          : '$count contraseñas llevan más de $days días sin cambiar. Toca para revisar.';

      await plugin.show(
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
    } catch (_) {
      // Never crash WorkManager — a thrown exception marks the task as FAILED
      // and WorkManager may retry with exponential back-off.
    }

    return true;
  });
}

// ─── PasswordCheckWorker ──────────────────────────────────────────────────────

/// Manages the WorkManager periodic task that checks for outdated passwords.
class PasswordCheckWorker {
  PasswordCheckWorker._();

  /// Registers (or replaces) a daily periodic task that checks password age.
  ///
  /// WorkManager enforces a minimum interval of 15 minutes; the actual
  /// execution window for a 24-hour task is at the OS's discretion (battery
  /// optimisation, etc.).
  static Future<void> register() async {
    await Workmanager().registerPeriodicTask(
      _uniqueTaskName,
      kPasswordAgeTaskName,
      frequency: const Duration(hours: 24),
      constraints: Constraints(
        networkType: NetworkType.notRequired,
        requiresBatteryNotLow: false,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
    );
  }

  /// Cancels the periodic task.  Safe to call even if no task is registered.
  static Future<void> cancel() async {
    await Workmanager().cancelByUniqueName(_uniqueTaskName);
  }
}
