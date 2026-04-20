import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../crypto/crypto_service.dart';
import '../models/entry_model.dart';
import '../models/group_model.dart';

class DatabaseService {
  static DatabaseService? _instance;
  static Database? _db;

  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _saltKey         = 'kmd_volt_salt';
  static const _hashKey         = 'kmd_volt_hash';
  static const _biometricKey    = 'kmd_volt_biometric_enabled';
  static const _dbPasswordKey   = 'kmd_volt_db_password';

  // PIN
  static const _pinHashKey      = 'kmd_pin_hash';
  static const _pinSaltKey      = 'kmd_pin_salt';
  static const _pinEnabledKey   = 'kmd_pin_enabled';
  static const _pinVaultKeyKey  = 'kmd_pin_vaultkey';

  // Auto-lock timeout
  static const _lockTimeoutKey  = 'kmd_lock_timeout';

  // Cached AES key derived from the stored DB password.
  static Uint8List? _cachedDbKey;

  DatabaseService._();

  static DatabaseService get instance {
    _instance ??= DatabaseService._();
    return _instance!;
  }

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  // ─── DB key helpers ─────────────────────────────────────────────────────────

  /// Returns (and caches) the 32-byte AES key used for field-level encryption.
  /// The key material is a random 64-char hex string persisted in the Android
  /// Keystore via flutter_secure_storage (EncryptedSharedPreferences).
  static Future<Uint8List> _getDbKey() async {
    if (_cachedDbKey != null) return _cachedDbKey!;
    var hex = await _secureStorage.read(key: _dbPasswordKey);
    if (hex == null) {
      final rng = Random.secure();
      final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
      hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      await _secureStorage.write(key: _dbPasswordKey, value: hex);
    }
    _cachedDbKey = Uint8List.fromList(
      List.generate(
        32,
        (i) => int.parse(hex!.substring(i * 2, i * 2 + 2), radix: 16),
      ),
    );
    return _cachedDbKey!;
  }

  // ─── Field-level AES-256-CBC encryption ────────────────────────────────────
  //
  // Format stored in the DB:  "enc:{ciphertext_b64}|{iv_b64}"
  // Legacy plaintext values (from a previous install) are returned as-is.

  static String _encryptField(String value, Uint8List key) {
    if (value.isEmpty) return value;
    final result = CryptoService.encrypt(value, key);
    return 'enc:${result['ciphertext']}|${result['iv']}';
  }

  static String _decryptField(String value, Uint8List key) {
    if (!value.startsWith('enc:')) return value; // plaintext / empty
    final rest = value.substring(4);
    final sep  = rest.indexOf('|');
    if (sep == -1) return value;
    final ciphertext = rest.substring(0, sep);
    final iv         = rest.substring(sep + 1);
    try {
      return CryptoService.decrypt(ciphertext, iv, key);
    } catch (_) {
      return '';
    }
  }

  /// Encrypts the sensitive fields of a DB row before writing.
  static Map<String, dynamic> _encryptRow(
    Map<String, dynamic> row,
    Uint8List key,
  ) {
    final out = Map<String, dynamic>.from(row);
    for (final field in ['password', 'notes']) {
      final v = out[field] as String? ?? '';
      out[field] = _encryptField(v, key);
    }
    return out;
  }

  /// Decrypts the sensitive fields of a DB row after reading.
  static Map<String, dynamic> _decryptRow(
    Map<String, dynamic> row,
    Uint8List key,
  ) {
    final out = Map<String, dynamic>.from(row);
    for (final field in ['password', 'notes']) {
      final v = out[field] as String? ?? '';
      out[field] = _decryptField(v, key);
    }
    return out;
  }

  // ─── DB initialisation ──────────────────────────────────────────────────────

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path   = join(dbPath, 'kmd_volt.db');

    // If an old SQLCipher-format file exists it cannot be read by plain sqflite.
    // Delete it so the app starts fresh (backup/restore can recover data).
    if (File(path).existsSync()) {
      try {
        // A plain SQLite file starts with "SQLite format 3\000".
        final header = File(path).readAsBytesSync().sublist(0, 16);
        final magic  = String.fromCharCodes(header.sublist(0, 15));
        if (!magic.startsWith('SQLite format 3')) {
          await File(path).delete();
        }
      } catch (_) {
        await File(path).delete();
      }
    }

    return openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE groups (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        icon_code TEXT,
        sort_order INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE entries (
        id TEXT PRIMARY KEY,
        group_id TEXT NOT NULL,
        title TEXT NOT NULL,
        username TEXT DEFAULT '',
        password TEXT NOT NULL,
        url TEXT DEFAULT '',
        notes TEXT DEFAULT '',
        icon_code TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        is_favorite INTEGER DEFAULT 0,
        FOREIGN KEY (group_id) REFERENCES groups(id) ON DELETE CASCADE
      )
    ''');
  }

  // ─── Master Password ────────────────────────────────────────────────────────

  Future<bool> hasMasterPassword() async {
    final hash = await _secureStorage.read(key: _hashKey);
    return hash != null;
  }

  Future<void> setMasterPassword(String password) async {
    final salt = CryptoService.generateSalt();
    final hash = CryptoService.hashPassword(password, salt);

    await _secureStorage.write(key: _saltKey, value: base64.encode(salt));
    await _secureStorage.write(key: _hashKey, value: hash);

    // Seed default groups on first setup
    final db    = await database;
    final count = await db.rawQuery('SELECT COUNT(*) as c FROM groups');
    if ((count.first['c'] as int) == 0) {
      for (final group in GroupModel.defaults) {
        await db.insert('groups', group.toDb());
      }
    }
  }

  Future<bool> verifyMasterPassword(String password) async {
    final saltB64   = await _secureStorage.read(key: _saltKey);
    final storedHash = await _secureStorage.read(key: _hashKey);
    if (saltB64 == null || storedHash == null) return false;
    final salt = Uint8List.fromList(base64.decode(saltB64));
    return CryptoService.verifyPassword(password, salt, storedHash);
  }

  Future<Uint8List?> getDerivedKey(String password) async {
    final saltB64 = await _secureStorage.read(key: _saltKey);
    if (saltB64 == null) return null;
    final salt = Uint8List.fromList(base64.decode(saltB64));
    return CryptoService.deriveKey(password, salt);
  }

  // ─── Biometric ──────────────────────────────────────────────────────────────

  Future<bool> isBiometricEnabled() async {
    final val = await _secureStorage.read(key: _biometricKey);
    return val == 'true';
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    await _secureStorage.write(key: _biometricKey, value: enabled.toString());
  }

  Future<void> saveBiometricVaultKey(Uint8List vaultKey) async {
    await _secureStorage.write(
      key: 'kmd_bio_vaultkey',
      value: base64.encode(vaultKey),
    );
  }

  Future<Uint8List?> getBiometricVaultKey() async {
    final val = await _secureStorage.read(key: 'kmd_bio_vaultkey');
    if (val == null) return null;
    return Uint8List.fromList(base64.decode(val));
  }

  Future<void> clearBiometricVaultKey() async {
    await _secureStorage.delete(key: 'kmd_bio_vaultkey');
  }

  // Legacy — kept for compatibility
  Future<void> storeMasterPasswordForBiometric(
    String password,
    Uint8List vaultKey,
  ) async {
    final encrypted = CryptoService.encrypt(password, vaultKey);
    await _secureStorage.write(
      key: 'kmd_bio_cipher',
      value: jsonEncode(encrypted),
    );
  }

  Future<String?> getMasterPasswordViaBiometric(Uint8List vaultKey) async {
    final data = await _secureStorage.read(key: 'kmd_bio_cipher');
    if (data == null) return null;
    final map = jsonDecode(data) as Map<String, dynamic>;
    return CryptoService.decrypt(
      map['ciphertext'] as String,
      map['iv'] as String,
      vaultKey,
    );
  }

  // ─── Groups ─────────────────────────────────────────────────────────────────

  Future<List<GroupModel>> getGroups() async {
    final db   = await database;
    final rows = await db.query('groups', orderBy: 'sort_order ASC');
    return rows.map(GroupModel.fromDb).toList();
  }

  Future<void> insertGroup(GroupModel group) async {
    final db = await database;
    await db.insert('groups', group.toDb(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateGroup(GroupModel group) async {
    final db = await database;
    await db.update('groups', group.toDb(),
        where: 'id = ?', whereArgs: [group.id]);
  }

  Future<void> deleteGroup(String id) async {
    final db = await database;
    await db.delete('groups', where: 'id = ?', whereArgs: [id]);
  }

  // ─── Entries ─────────────────────────────────────────────────────────────────

  Future<List<EntryModel>> getEntries({String? groupId}) async {
    final db  = await database;
    final key = await _getDbKey();
    final rows = groupId != null
        ? await db.query('entries',
            where: 'group_id = ?',
            whereArgs: [groupId],
            orderBy: 'updated_at DESC')
        : await db.query('entries', orderBy: 'updated_at DESC');
    return rows.map((r) => EntryModel.fromDb(_decryptRow(r, key))).toList();
  }

  Future<List<EntryModel>> searchEntries(String query) async {
    final db  = await database;
    final key = await _getDbKey();
    // Search on non-encrypted columns (title, username, url).
    final rows = await db.query(
      'entries',
      where: 'title LIKE ? OR username LIKE ? OR url LIKE ?',
      whereArgs: ['%$query%', '%$query%', '%$query%'],
      orderBy: 'updated_at DESC',
    );
    return rows.map((r) => EntryModel.fromDb(_decryptRow(r, key))).toList();
  }

  Future<List<EntryModel>> getFavorites() async {
    final db  = await database;
    final key = await _getDbKey();
    final rows = await db.query('entries',
        where: 'is_favorite = 1', orderBy: 'updated_at DESC');
    return rows.map((r) => EntryModel.fromDb(_decryptRow(r, key))).toList();
  }

  Future<void> insertEntry(EntryModel entry) async {
    final db  = await database;
    final key = await _getDbKey();
    await db.insert('entries', _encryptRow(entry.toDb(), key),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateEntry(EntryModel entry) async {
    final db  = await database;
    final key = await _getDbKey();
    await db.update('entries', _encryptRow(entry.toDb(), key),
        where: 'id = ?', whereArgs: [entry.id]);
  }

  Future<void> deleteEntry(String id) async {
    final db = await database;
    await db.delete('entries', where: 'id = ?', whereArgs: [id]);
  }

  // ─── Backup / Restore ───────────────────────────────────────────────────────

  Future<Map<String, dynamic>> exportVault(Uint8List vaultKey) async {
    final groups  = await getGroups();
    final entries = await getEntries(); // already decrypted

    final data = {
      'version':    1,
      'exportedAt': DateTime.now().toIso8601String(),
      'groups':     groups.map((g) => g.toJson()).toList(),
      'entries':    entries.map((e) => e.toJson()).toList(),
    };

    final encrypted = CryptoService.encryptVault(data, vaultKey);
    return {'encrypted': encrypted};
  }

  Future<void> importVault(
    Map<String, dynamic> backup,
    Uint8List vaultKey,
  ) async {
    final encrypted = backup['encrypted'] as String;
    final data      = CryptoService.decryptVault(encrypted, vaultKey);

    final groups = (data['groups'] as List)
        .map((g) => GroupModel.fromJson(g as Map<String, dynamic>))
        .toList();
    final entries = (data['entries'] as List)
        .map((e) => EntryModel.fromJson(e as Map<String, dynamic>))
        .toList();

    // Use insertGroup / insertEntry so field encryption is applied.
    for (final g in groups) {
      await insertGroup(g);
    }
    for (final e in entries) {
      await insertEntry(e);
    }
  }

  // ─── PIN ────────────────────────────────────────────────────────────────────

  Future<bool> hasPinEnabled() async {
    final val = await _secureStorage.read(key: _pinEnabledKey);
    return val == 'true';
  }

  Future<void> setPin(String pin) async {
    final salt = CryptoService.generateSalt();
    final hash = CryptoService.hashPassword(pin, salt);
    await _secureStorage.write(key: _pinSaltKey, value: base64.encode(salt));
    await _secureStorage.write(key: _pinHashKey, value: hash);
    await _secureStorage.write(key: _pinEnabledKey, value: 'true');
  }

  Future<bool> verifyPin(String pin) async {
    final saltB64    = await _secureStorage.read(key: _pinSaltKey);
    final storedHash = await _secureStorage.read(key: _pinHashKey);
    if (saltB64 == null || storedHash == null) return false;
    final salt = Uint8List.fromList(base64.decode(saltB64));
    return CryptoService.verifyPassword(pin, salt, storedHash);
  }

  Future<void> clearPin() async {
    await _secureStorage.delete(key: _pinHashKey);
    await _secureStorage.delete(key: _pinSaltKey);
    await _secureStorage.write(key: _pinEnabledKey, value: 'false');
  }

  Future<void> savePinVaultKey(Uint8List vaultKey) async {
    await _secureStorage.write(
      key: _pinVaultKeyKey,
      value: base64.encode(vaultKey),
    );
  }

  Future<Uint8List?> getPinVaultKey() async {
    final val = await _secureStorage.read(key: _pinVaultKeyKey);
    if (val == null) return null;
    return Uint8List.fromList(base64.decode(val));
  }

  Future<void> clearPinVaultKey() async {
    await _secureStorage.delete(key: _pinVaultKeyKey);
  }

  // ─── Auto-lock timeout ───────────────────────────────────────────────────────

  Future<int?> getLockTimeoutMinutes() async {
    final val = await _secureStorage.read(key: _lockTimeoutKey);
    if (val == null || val == '0') return 0;
    if (val == 'never') return null;
    return int.tryParse(val) ?? 0;
  }

  Future<void> setLockTimeoutMinutes(int? minutes) async {
    final val = minutes == null ? 'never' : minutes.toString();
    await _secureStorage.write(key: _lockTimeoutKey, value: val);
  }

  // ─── Reset ──────────────────────────────────────────────────────────────────

  Future<void> resetAll() async {
    _cachedDbKey = null;
    await _secureStorage.deleteAll();
    final db = await database;
    await db.delete('entries');
    await db.delete('groups');
  }
}
