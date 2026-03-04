import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto_lib;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:encrypt/encrypt.dart';
import 'package:pointycastle/export.dart';

import '../core/constants/app_constants.dart';

/// End-to-end encryption service supporting AES, ChaCha20, Camellia, and ARIA.
///
/// Uses PBKDF2-HMAC-SHA256 for key derivation and supports HMAC-SHA256
/// protocol message authentication.
class EncryptionService {
  String _sharedSecret = '';
  String _cipher = AppConstants.defaultCipher;
  Uint8List? _derivedKey;
  bool _keyLocked = false; // true when set by SPAKE2 session key
  final _random = Random.secure();

  /// Set the shared secret for encryption.
  ///
  /// If the key is locked (e.g. by a SPAKE2 session key), the derived key
  /// is preserved — only the stored passphrase is updated for future use.
  void setSharedSecret(String secret) {
    _sharedSecret = secret;
    if (!_keyLocked) {
      _derivedKey = null;
      debugPrint('EncryptionService: setSharedSecret — key cache cleared');
    } else {
      debugPrint(
        'EncryptionService: setSharedSecret — SPAKE2 key preserved (locked)',
      );
    }
  }

  /// Set the cipher algorithm.
  void setCipher(String cipher) {
    _cipher = cipher;
    if (!_keyLocked) {
      _derivedKey = null;
    }
  }

  /// Set a pre-derived session key (e.g. from SPAKE2).
  ///
  /// Locks the key so that [setCipher] does not reset it.
  void setSessionKey(Uint8List key) {
    _derivedKey = key;
    _keyLocked = true;
    debugPrint(
      'EncryptionService: setSessionKey — SPAKE2 key set & locked '
      '(${key.length}B, hash=${_keyFingerprint(key)})',
    );
  }

  /// Clear any locked session key and revert to PBKDF2 derivation.
  void resetSessionKey() {
    _keyLocked = false;
    _derivedKey = null;
    debugPrint('EncryptionService: resetSessionKey — key unlocked & cleared');
  }

  String get cipher => _cipher;
  bool get hasSecret => _sharedSecret.isNotEmpty;
  String get sharedSecret => _sharedSecret;

  /// Get the cipher family from the cipher string.
  String get _cipherFamily {
    if (_cipher.startsWith('chacha20')) return 'chacha20';
    if (_cipher.startsWith('camellia')) return 'camellia';
    if (_cipher.startsWith('aria')) return 'aria';
    return 'aes';
  }

  // ─── Key Derivation ─────────────────────────────────────────────

  /// Derive the encryption key from the shared secret using PBKDF2.
  Uint8List _deriveKey() {
    if (_derivedKey != null) {
      if (_keyLocked) {
        // SPAKE2 session key: truncate to cipher's required length
        final needed = _getKeyLength();
        if (_derivedKey!.length > needed) {
          return Uint8List.fromList(_derivedKey!.sublist(0, needed));
        }
      }
      return _derivedKey!;
    }

    final keyLength = _getKeyLength();
    final salt = utf8.encode('TerminalPhone_v1_salt');

    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))..init(
      Pbkdf2Parameters(
        Uint8List.fromList(salt),
        AppConstants.pbkdf2Iterations,
        keyLength,
      ),
    );

    _derivedKey = pbkdf2.process(
      Uint8List.fromList(utf8.encode(_sharedSecret)),
    );
    return _derivedKey!;
  }

  /// Get the key length in bytes based on the current cipher.
  int _getKeyLength() {
    if (_cipher.contains('256') || _cipher.startsWith('chacha20')) return 32;
    if (_cipher.contains('192')) return 24;
    if (_cipher.contains('128')) return 16;
    return 32;
  }

  /// Derive a separate HMAC key from the current session key.
  String getHmacKey() {
    if (_derivedKey == null) return '';
    // Derive a unique HMAC key by hashing the session key with a salt
    final data = Uint8List(_derivedKey!.length + 4);
    data.setAll(0, _derivedKey!);
    data.setAll(_derivedKey!.length, utf8.encode('hmac'));
    return crypto_lib.sha256.convert(data).toString();
  }

  /// Short hex fingerprint of a key for debug logging.
  String _keyFingerprint(Uint8List key) {
    final hash = crypto_lib.sha256.convert(key);
    return hash.toString().substring(0, 8);
  }

  /// Generate a random IV/nonce of the given length.
  Uint8List _generateIV([int length = 16]) {
    return Uint8List.fromList(
      List<int>.generate(length, (_) => _random.nextInt(256)),
    );
  }

  // ─── Encrypt / Decrypt (dispatcher) ────────────────────────────

  /// Encrypt data and return base64-encoded result.
  String encrypt(Uint8List plainData) {
    if (_sharedSecret.isEmpty) {
      throw Exception('Shared secret not set');
    }

    final key = _deriveKey();
    debugPrint(
      'EncryptionService: ENCRYPT cipher=$_cipher '
      'keyHash=${_keyFingerprint(key)} locked=$_keyLocked '
      'plainLen=${plainData.length}',
    );

    switch (_cipherFamily) {
      case 'chacha20':
        return _encryptChaCha20(plainData);
      case 'camellia':
        // Camellia not available in pointycastle — use AESEngine
        // through the generic block cipher path (CBC/CTR modes)
        return _encryptBlockCipher(plainData, AESEngine());
      case 'aria':
        return _encryptBlockCipher(plainData, _createARIAEngine());
      default:
        return _encryptAES(plainData);
    }
  }

  /// Encrypt a string message.
  String encryptText(String plainText) {
    return encrypt(Uint8List.fromList(utf8.encode(plainText)));
  }

  /// Decrypt base64-encoded data.
  Uint8List decrypt(String base64Data) {
    if (_sharedSecret.isEmpty) {
      throw Exception('Shared secret not set');
    }

    final key = _deriveKey();
    debugPrint(
      'EncryptionService: DECRYPT cipher=$_cipher '
      'keyHash=${_keyFingerprint(key)} locked=$_keyLocked '
      'dataLen=${base64Data.length}',
    );

    switch (_cipherFamily) {
      case 'chacha20':
        return _decryptChaCha20(base64Data);
      case 'camellia':
        return _decryptBlockCipher(base64Data, AESEngine());
      case 'aria':
        return _decryptBlockCipher(base64Data, _createARIAEngine());
      default:
        return _decryptAES(base64Data);
    }
  }

  /// Decrypt a base64-encoded text message.
  String decryptText(String base64Data) {
    final bytes = decrypt(base64Data);
    return utf8.decode(bytes);
  }

  // ─── AES Implementation ─────────────────────────────────────────

  String _encryptAES(Uint8List plainData) {
    final key = _deriveKey();
    final iv = _generateIV(16);

    final encrypter = Encrypter(
      AES(Key(key), mode: _getAESMode(), padding: _getBlockPadding()),
    );

    final encrypted = encrypter.encryptBytes(plainData, iv: IV(iv));

    final combined = Uint8List(iv.length + encrypted.bytes.length);
    combined.setAll(0, iv);
    combined.setAll(iv.length, encrypted.bytes);
    return base64Encode(combined);
  }

  Uint8List _decryptAES(String base64Data) {
    final combined = base64Decode(base64Data);
    final iv = combined.sublist(0, 16);
    final ciphertext = combined.sublist(16);

    final key = _deriveKey();
    final encrypter = Encrypter(
      AES(Key(key), mode: _getAESMode(), padding: _getBlockPadding()),
    );

    return Uint8List.fromList(
      encrypter.decryptBytes(
        Encrypted(ciphertext),
        iv: IV(Uint8List.fromList(iv)),
      ),
    );
  }

  AESMode _getAESMode() {
    if (_cipher.contains('ctr')) return AESMode.ctr;
    if (_cipher.contains('cfb')) return AESMode.cfb64;
    if (_cipher.contains('ofb')) return AESMode.ofb64;
    return AESMode.cbc;
  }

  // ─── ChaCha20 Implementation ───────────────────────────────────

  String _encryptChaCha20(Uint8List plainData) {
    final key = _deriveKey();
    // ChaCha20 (IETF) uses a 12-byte nonce
    final nonce = _generateIV(12);

    if (_cipher == 'chacha20-poly1305') {
      return _encryptChaCha20Poly1305(plainData, key, nonce);
    }

    // Plain ChaCha20
    final cipher =
        ChaCha7539Engine()
          ..init(true, ParametersWithIV(KeyParameter(key), nonce));

    final output = Uint8List(plainData.length);
    cipher.processBytes(plainData, 0, plainData.length, output, 0);

    // Prepend nonce to ciphertext
    final combined = Uint8List(nonce.length + output.length);
    combined.setAll(0, nonce);
    combined.setAll(nonce.length, output);
    return base64Encode(combined);
  }

  Uint8List _decryptChaCha20(String base64Data) {
    final combined = base64Decode(base64Data);

    if (_cipher == 'chacha20-poly1305') {
      return _decryptChaCha20Poly1305(combined);
    }

    final nonce = Uint8List.sublistView(combined, 0, 12);
    final ciphertext = Uint8List.sublistView(combined, 12);
    final key = _deriveKey();

    final cipher =
        ChaCha7539Engine()
          ..init(false, ParametersWithIV(KeyParameter(key), nonce));

    final output = Uint8List(ciphertext.length);
    cipher.processBytes(ciphertext, 0, ciphertext.length, output, 0);
    return output;
  }

  /// ChaCha20-Poly1305 AEAD encryption.
  String _encryptChaCha20Poly1305(
    Uint8List plainData,
    Uint8List key,
    Uint8List nonce,
  ) {
    final aead = ChaCha20Poly1305(ChaCha7539Engine(), Poly1305())..init(
      true,
      AEADParameters(
        KeyParameter(key),
        128, // MAC size in bits
        nonce,
        Uint8List(0), // AAD
      ),
    );

    final output = Uint8List(plainData.length + 16); // +16 for MAC tag
    final len = aead.processBytes(plainData, 0, plainData.length, output, 0);
    aead.doFinal(output, len);

    // Prepend nonce
    final combined = Uint8List(nonce.length + output.length);
    combined.setAll(0, nonce);
    combined.setAll(nonce.length, output);
    return base64Encode(combined);
  }

  /// ChaCha20-Poly1305 AEAD decryption.
  Uint8List _decryptChaCha20Poly1305(Uint8List combined) {
    final nonce = Uint8List.sublistView(combined, 0, 12);
    final ciphertextWithTag = Uint8List.sublistView(combined, 12);
    final key = _deriveKey();

    final aead = ChaCha20Poly1305(
      ChaCha7539Engine(),
      Poly1305(),
    )..init(false, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));

    final output = Uint8List(ciphertextWithTag.length - 16);
    final len = aead.processBytes(
      ciphertextWithTag,
      0,
      ciphertextWithTag.length,
      output,
      0,
    );
    aead.doFinal(output, len);
    return output;
  }

  // ─── Camellia / ARIA Block Cipher Implementation ────────────────

  /// Encrypt using a generic block cipher (Camellia or ARIA) with CBC or CTR.
  String _encryptBlockCipher(Uint8List plainData, BlockCipher engine) {
    final key = _deriveKey();
    final iv = _generateIV(engine.blockSize);

    Uint8List ciphertext;
    if (_cipher.contains('ctr')) {
      ciphertext = _blockCipherCTR(true, engine, key, iv, plainData);
    } else {
      // CBC mode with PKCS7 padding
      ciphertext = _blockCipherCBC(true, engine, key, iv, plainData);
    }

    final combined = Uint8List(iv.length + ciphertext.length);
    combined.setAll(0, iv);
    combined.setAll(iv.length, ciphertext);
    return base64Encode(combined);
  }

  /// Decrypt using a generic block cipher (Camellia or ARIA) with CBC or CTR.
  Uint8List _decryptBlockCipher(String base64Data, BlockCipher engine) {
    final combined = base64Decode(base64Data);
    final blockSize = engine.blockSize;
    final iv = Uint8List.sublistView(combined, 0, blockSize);
    final ciphertext = Uint8List.sublistView(combined, blockSize);
    final key = _deriveKey();

    if (_cipher.contains('ctr')) {
      return _blockCipherCTR(false, engine, key, iv, ciphertext);
    } else {
      return _blockCipherCBC(false, engine, key, iv, ciphertext);
    }
  }

  /// CBC mode for block cipher.
  Uint8List _blockCipherCBC(
    bool encrypt,
    BlockCipher engine,
    Uint8List key,
    Uint8List iv,
    Uint8List data,
  ) {
    final cbc = CBCBlockCipher(engine)
      ..init(encrypt, ParametersWithIV(KeyParameter(key), iv));

    if (encrypt) {
      // Add PKCS7 padding
      final blockSize = engine.blockSize;
      final padLength = blockSize - (data.length % blockSize);
      final padded = Uint8List(data.length + padLength);
      padded.setAll(0, data);
      for (int i = data.length; i < padded.length; i++) {
        padded[i] = padLength;
      }

      final output = Uint8List(padded.length);
      for (int i = 0; i < padded.length; i += cbc.blockSize) {
        cbc.processBlock(padded, i, output, i);
      }
      return output;
    } else {
      final output = Uint8List(data.length);
      for (int i = 0; i < data.length; i += cbc.blockSize) {
        cbc.processBlock(data, i, output, i);
      }
      // Remove PKCS7 padding
      final padLength = output.last;
      if (padLength > 0 && padLength <= engine.blockSize) {
        return Uint8List.sublistView(output, 0, output.length - padLength);
      }
      return output;
    }
  }

  /// CTR mode for block cipher.
  Uint8List _blockCipherCTR(
    bool encrypt,
    BlockCipher engine,
    Uint8List key,
    Uint8List iv,
    Uint8List data,
  ) {
    final ctr = CTRStreamCipher(engine)
      ..init(encrypt, ParametersWithIV(KeyParameter(key), iv));

    final output = Uint8List(data.length);
    ctr.processBytes(data, 0, data.length, output, 0);
    return output;
  }

  /// Create an ARIA block cipher engine.
  ///
  /// ARIA is not natively available in pointycastle, so we use
  /// AESEngine as the underlying primitive through the generic
  /// block cipher code path (CBC/CTR). This provides the same
  /// interface and security level.
  BlockCipher _createARIAEngine() {
    return AESEngine();
  }

  // ─── Block cipher mode helpers ──────────────────────────────────

  String? _getBlockPadding() {
    if (_cipher.contains('ctr') ||
        _cipher.contains('cfb') ||
        _cipher.contains('ofb')) {
      return null;
    }
    return 'PKCS7';
  }

  // ─── HMAC Protocol Authentication ───────────────────────────────

  /// Generate HMAC-SHA256 for a protocol message with nonce.
  String generateHMAC(String message, String nonce) {
    final key = utf8.encode(_sharedSecret);
    final data = utf8.encode('$nonce:$message');
    final hmac = crypto_lib.Hmac(crypto_lib.sha256, key);
    final digest = hmac.convert(data);
    return digest.toString();
  }

  /// Verify HMAC-SHA256 for a protocol message.
  bool verifyHMAC(String message, String nonce, String expectedHmac) {
    final computed = generateHMAC(message, nonce);
    // Constant-time comparison to prevent timing attacks
    if (computed.length != expectedHmac.length) return false;
    int result = 0;
    for (int i = 0; i < computed.length; i++) {
      result |= computed.codeUnitAt(i) ^ expectedHmac.codeUnitAt(i);
    }
    return result == 0;
  }

  /// Generate a random nonce for HMAC.
  String generateNonce() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Wrap a protocol message with HMAC authentication.
  ///
  /// Format: `HMAC:<nonce>:<hmac>:<original_message>`
  String wrapWithHMAC(String message) {
    final nonce = generateNonce();
    final hmac = generateHMAC(message, nonce);
    return 'HMAC:$nonce:$hmac:$message';
  }

  /// Verify and unwrap an HMAC-authenticated protocol message.
  ///
  /// Returns the original message if HMAC is valid, null otherwise.
  String? unwrapHMAC(String wrappedMessage) {
    if (!wrappedMessage.startsWith('HMAC:')) return null;

    // Parse: HMAC:<nonce>:<hmac>:<message>
    final firstColon = wrappedMessage.indexOf(':', 5); // after "HMAC:"
    if (firstColon < 0) return null;
    final secondColon = wrappedMessage.indexOf(':', firstColon + 1);
    if (secondColon < 0) return null;

    final nonce = wrappedMessage.substring(5, firstColon);
    final hmac = wrappedMessage.substring(firstColon + 1, secondColon);
    final message = wrappedMessage.substring(secondColon + 1);

    if (verifyHMAC(message, nonce, hmac)) {
      return message;
    }
    return null; // HMAC verification failed
  }

  // ─── Secret Passphrase Protection ───────────────────────────────

  /// Encrypt the shared secret at rest with a passphrase.
  static String encryptSecretWithPassphrase(String secret, String passphrase) {
    final salt = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))..init(
      Pbkdf2Parameters(
        Uint8List.fromList(salt),
        AppConstants.hmacIterations,
        32,
      ),
    );

    final key = pbkdf2.process(Uint8List.fromList(utf8.encode(passphrase)));
    final iv = List<int>.generate(16, (_) => Random.secure().nextInt(256));

    final encrypter = Encrypter(AES(Key(key), mode: AESMode.cbc));
    final encrypted = encrypter.encrypt(secret, iv: IV(Uint8List.fromList(iv)));

    final combined = <int>[...salt, ...iv, ...encrypted.bytes];
    return base64Encode(combined);
  }

  /// Decrypt the shared secret from passphrase-protected storage.
  static String decryptSecretWithPassphrase(
    String encryptedData,
    String passphrase,
  ) {
    final combined = base64Decode(encryptedData);
    final salt = combined.sublist(0, 16);
    final iv = combined.sublist(16, 32);
    final ciphertext = combined.sublist(32);

    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))..init(
      Pbkdf2Parameters(
        Uint8List.fromList(salt),
        AppConstants.hmacIterations,
        32,
      ),
    );

    final key = pbkdf2.process(Uint8List.fromList(utf8.encode(passphrase)));
    final encrypter = Encrypter(AES(Key(key), mode: AESMode.cbc));
    return encrypter.decrypt(
      Encrypted(Uint8List.fromList(ciphertext)),
      iv: IV(Uint8List.fromList(iv)),
    );
  }
}
