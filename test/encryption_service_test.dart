import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:onion_talkie/services/encryption_service.dart';

void main() {
  group('EncryptionService HMAC Tests', () {
    late EncryptionService encryptionService;

    setUp(() {
      encryptionService = EncryptionService();
    });

    test('getHmacKey returns empty string when no key is set', () {
      expect(encryptionService.getHmacKey(), isEmpty);
    });

    test('getHmacKey returns a valid hex string after setting session key', () {
      final sessionKey = Uint8List.fromList(List.generate(32, (i) => i));
      encryptionService.setSessionKey(sessionKey);

      final hmacKey = encryptionService.getHmacKey();
      expect(hmacKey, isNotEmpty);
      expect(hmacKey.length, equals(64)); // SHA256 hex string length
    });

    test('getHmacKey is stable for the same session key', () {
      final sessionKey = Uint8List.fromList(List.generate(32, (i) => i));
      encryptionService.setSessionKey(sessionKey);

      final key1 = encryptionService.getHmacKey();
      final key2 = encryptionService.getHmacKey();

      expect(key1, equals(key2));
    });

    test('getHmacKey changes when session key changes', () {
      final sessionKey1 = Uint8List.fromList(List.generate(32, (i) => i));
      final sessionKey2 = Uint8List.fromList(List.generate(32, (i) => i + 1));

      encryptionService.setSessionKey(sessionKey1);
      final key1 = encryptionService.getHmacKey();

      encryptionService.setSessionKey(sessionKey2);
      final key2 = encryptionService.getHmacKey();

      expect(key1, isNot(equals(key2)));
    });
  });
}
