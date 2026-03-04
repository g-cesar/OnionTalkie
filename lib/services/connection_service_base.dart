import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto_lib;

import '../core/constants/app_constants.dart';

/// Abstract connection service interface (platform-agnostic).
///
/// Supports optional HMAC-SHA256 protocol message authentication.
abstract class ConnectionServiceBase {
  Stream<MapEntry<String, String>> get messageStream;
  bool get isConnected;
  int? get serverSocketPort => null;

  /// HMAC authentication state.
  bool hmacEnabledFlag = false;
  String hmacKey = '';

  bool get hmacEnabled => hmacEnabledFlag;

  /// Enable/disable HMAC authentication on protocol messages.
  void setHmac({required bool enabled, String key = ''}) {
    hmacEnabledFlag = enabled;
    hmacKey = key;
  }

  /// Wrap a message with HMAC if enabled, otherwise return as-is.
  String wrapMessage(String message) {
    if (!hmacEnabledFlag || hmacKey.isEmpty) return message;

    final nonce = _generateHmacNonce();
    final hmac = _computeHmac(message, nonce);
    return '${AppConstants.protoHmacPrefix}$nonce:$hmac:$message';
  }

  /// Unwrap and verify HMAC on a message. Returns the original message
  /// or null if verification fails.
  String? unwrapMessage(String message) {
    if (!message.startsWith(AppConstants.protoHmacPrefix)) {
      // Not HMAC-wrapped — accept if HMAC is not required
      return hmacEnabledFlag ? null : message;
    }

    final payload = message.substring(AppConstants.protoHmacPrefix.length);
    final firstColon = payload.indexOf(':');
    if (firstColon < 0) return null;
    final secondColon = payload.indexOf(':', firstColon + 1);
    if (secondColon < 0) return null;

    final nonce = payload.substring(0, firstColon);
    final receivedHmac = payload.substring(firstColon + 1, secondColon);
    final originalMessage = payload.substring(secondColon + 1);

    final computed = _computeHmac(originalMessage, nonce);

    // Constant-time comparison
    if (computed.length != receivedHmac.length) return null;
    int result = 0;
    for (int i = 0; i < computed.length; i++) {
      result |= computed.codeUnitAt(i) ^ receivedHmac.codeUnitAt(i);
    }
    if (result != 0) return null;

    return originalMessage;
  }

  String _computeHmac(String message, String nonce) {
    final key = utf8.encode(hmacKey);
    final data = utf8.encode('$nonce:$message');
    final hmac = crypto_lib.Hmac(crypto_lib.sha256, key);
    return hmac.convert(data).toString();
  }

  String _generateHmacNonce() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final data = utf8.encode('$now');
    return crypto_lib.sha256.convert(data).toString().substring(0, 32);
  }

  /// Listen for incoming connections.
  Future<void> listen({int? port});

  /// Connect to a remote .onion address.
  Future<void> connect(String onionAddress);

  /// Send a raw protocol message (HMAC-wrapped if enabled).
  void send(String message);

  /// Send caller ID.
  void sendId(String onionAddress);

  /// Send cipher info.
  void sendCipher(String cipher);

  /// Send PTT start signal.
  void sendPttStart();

  /// Send PTT stop signal.
  void sendPttStop();

  /// Send encrypted audio data.
  void sendAudio(String base64Audio);

  /// Send encrypted text message.
  void sendMessage(String base64Msg);

  /// Send hangup signal.
  void sendHangup();

  /// Send ping keepalive.
  void sendPing();

  /// Send SPAKE2 blinded public value.
  void sendSpake2Pub(String base64Value) =>
      send('${AppConstants.protoSpake2Pub}$base64Value');

  /// Send SPAKE2 key-confirmation MAC.
  void sendSpake2Confirm(String confirmHex) =>
      send('${AppConstants.protoSpake2Confirm}$confirmHex');

  /// Close the connection.
  Future<void> disconnect();

  void dispose();
}
