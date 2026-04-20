import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;

class CryptoService {
  static const int _saltLength = 32;
  static const int _ivLength = 16;
  static const int _iterations = 100000;

  /// Derives a 256-bit key from master password + salt using PBKDF2-SHA256
  static Uint8List deriveKey(String password, Uint8List salt) {
    final passwordBytes = utf8.encode(password);
    var result = Uint8List(_saltLength);

    // PBKDF2 with HMAC-SHA256
    final hmac = Hmac(sha256, passwordBytes);
    final saltWithBlock = Uint8List(salt.length + 4);
    saltWithBlock.setRange(0, salt.length, salt);
    saltWithBlock[salt.length] = 0;
    saltWithBlock[salt.length + 1] = 0;
    saltWithBlock[salt.length + 2] = 0;
    saltWithBlock[salt.length + 3] = 1;

    var u = Uint8List.fromList(hmac.convert(saltWithBlock).bytes);
    result = Uint8List.fromList(u);

    for (int i = 1; i < _iterations; i++) {
      u = Uint8List.fromList(hmac.convert(u).bytes);
      for (int j = 0; j < result.length; j++) {
        result[j] ^= u[j];
      }
    }

    return result;
  }

  /// Generates a cryptographically secure random salt
  static Uint8List generateSalt() {
    final random = Random.secure();
    return Uint8List.fromList(
      List.generate(_saltLength, (_) => random.nextInt(256)),
    );
  }

  /// Generates a cryptographically secure random IV
  static Uint8List generateIV() {
    final random = Random.secure();
    return Uint8List.fromList(
      List.generate(_ivLength, (_) => random.nextInt(256)),
    );
  }

  /// Encrypts plaintext using AES-256-CBC with derived key
  static Map<String, String> encrypt(String plaintext, Uint8List key) {
    final iv = generateIV();
    final encKey = enc.Key(key);
    final encIV = enc.IV(iv);
    final encrypter = enc.Encrypter(enc.AES(encKey, mode: enc.AESMode.cbc));

    final encrypted = encrypter.encrypt(plaintext, iv: encIV);

    return {
      'ciphertext': encrypted.base64,
      'iv': base64.encode(iv),
    };
  }

  /// Decrypts ciphertext using AES-256-CBC
  static String decrypt(
    String ciphertext,
    String ivBase64,
    Uint8List key,
  ) {
    final iv = enc.IV(Uint8List.fromList(base64.decode(ivBase64)));
    final encKey = enc.Key(key);
    final encrypter = enc.Encrypter(enc.AES(encKey, mode: enc.AESMode.cbc));

    return encrypter.decrypt64(ciphertext, iv: iv);
  }

  /// Hashes master password for verification storage
  static String hashPassword(String password, Uint8List salt) {
    final key = deriveKey(password, salt);
    final hash = sha256.convert(key);
    return hash.toString();
  }

  /// Verifies master password against stored hash
  static bool verifyPassword(
    String password,
    Uint8List salt,
    String storedHash,
  ) {
    final hash = hashPassword(password, salt);
    return hash == storedHash;
  }

  // GCM nonce length (96 bits — optimal for AES-GCM)
  static const int _gcmNonceLength = 12;

  /// Encrypts a JSON map (vault backup data) using AES-256-GCM.
  ///
  /// GCM provides authenticated encryption — the authentication tag is
  /// embedded in the ciphertext by the `encrypt` package, so no separate
  /// HMAC/checksum is needed.  The output is versioned (version = 2) so that
  /// [decryptVault] can still import older AES-CBC backups (version = 1).
  static String encryptVault(Map<String, dynamic> data, Uint8List key) {
    final json = jsonEncode(data);

    final random = Random.secure();
    final nonce = Uint8List.fromList(
      List.generate(_gcmNonceLength, (_) => random.nextInt(256)),
    );

    final encKey = enc.Key(key);
    final encIV  = enc.IV(nonce);
    final encrypter = enc.Encrypter(enc.AES(encKey, mode: enc.AESMode.gcm));

    final encrypted = encrypter.encrypt(json, iv: encIV);

    final payload = {
      'ciphertext': encrypted.base64,
      'iv': base64.encode(nonce),
      'version': 2,          // AES-256-GCM with embedded auth tag
    };
    return base64.encode(utf8.encode(jsonEncode(payload)));
  }

  /// Decrypts an encrypted vault string back to a JSON map.
  ///
  /// Supports both the legacy AES-256-CBC format (version = 1) and the current
  /// AES-256-GCM format (version = 2), so old backups can still be imported.
  static Map<String, dynamic> decryptVault(
    String encryptedData,
    Uint8List key,
  ) {
    final payloadJson = utf8.decode(base64.decode(encryptedData));
    final payload = jsonDecode(payloadJson) as Map<String, dynamic>;
    final version = payload['version'] as int? ?? 1;

    final String json;

    if (version >= 2) {
      // AES-256-GCM (current format)
      final iv         = enc.IV(Uint8List.fromList(base64.decode(payload['iv'] as String)));
      final encKey     = enc.Key(key);
      final encrypter  = enc.Encrypter(enc.AES(encKey, mode: enc.AESMode.gcm));
      json = encrypter.decrypt64(payload['ciphertext'] as String, iv: iv);
    } else {
      // Legacy AES-256-CBC (version 1) — kept for backward compat
      json = decrypt(
        payload['ciphertext'] as String,
        payload['iv'] as String,
        key,
      );
    }

    return jsonDecode(json) as Map<String, dynamic>;
  }
}
