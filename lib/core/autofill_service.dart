import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'models/entry_model.dart';

class AutofillService {
  static const _channel = MethodChannel('com.kmd.kmd_volt/autofill');

  /// Notifies listeners when Android's autofill service has captured credentials
  /// from a login form and wants KMD Volt to save them.
  /// The map contains: title, username, password, url.
  static final ValueNotifier<Map<String, String>?> saveNotifier =
      ValueNotifier(null);

  /// Asks the native side if there is a pending autofill save (credentials
  /// captured by VoltAutofillService.onSaveRequest). If found, sets
  /// [saveNotifier] so the HomeScreen can navigate to the new-entry screen.
  static Future<void> checkPendingSave() async {
    try {
      final raw = await _channel.invokeMethod<Map>('getPendingAutofillSave');
      if (raw != null && raw.isNotEmpty) {
        saveNotifier.value = raw.map(
          (k, v) => MapEntry(k.toString(), v?.toString() ?? ''),
        );
      }
    } catch (_) {}
  }

  /// Pushes vault entries to Android SharedPreferences so the AutofillService
  /// can read them without needing the Flutter app open.
  /// Only stores: title, username, password, url — nothing else.
  static Future<void> syncEntries(List<EntryModel> entries) async {
    try {
      final data = entries
          .map((e) => {
                'title': e.title,
                'username': e.username,
                'password': e.password,
                'url': e.url,
              })
          .toList();

      await _channel.invokeMethod('syncVaultEntries', {
        'entries': jsonEncode(data),
      });
    } catch (_) {
      // Silently fail — autofill is optional
    }
  }

  /// Clears vault data from SharedPreferences when the vault is locked.
  static Future<void> lockVault() async {
    try {
      await _channel.invokeMethod('lockVault');
    } catch (_) {}
  }

  /// Returns true if KMD Volt is currently set as the system autofill provider.
  static Future<bool> isEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('isAutofillEnabled') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens Android Settings so the user can select KMD Volt as autofill provider.
  static Future<void> openSettings() async {
    try {
      await _channel.invokeMethod('openAutofillSettings');
    } catch (_) {}
  }
}
