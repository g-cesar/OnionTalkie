import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web/web.dart' as web;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/constants/app_constants.dart';
import 'connection_service_base.dart';

/// Web implementation of ConnectionService using WebSocket.
///
/// On the web, raw TCP sockets are not available. This implementation
/// communicates via WebSocket, either directly to a relay server that
/// bridges traffic to the Tor network, or to a WebSocket-to-TCP proxy.
///
/// The relay server URL is read from SharedPreferences ('relay_server_url').
class ConnectionServiceWeb extends ConnectionServiceBase {
  WebSocketChannel? _channel;
  final _messageController =
      StreamController<MapEntry<String, String>>.broadcast();
  bool _isConnected = false;
  StringBuffer _lineBuffer = StringBuffer();

  @override
  Stream<MapEntry<String, String>> get messageStream =>
      _messageController.stream;
  @override
  bool get isConnected => _isConnected;

  /// Listen for incoming connections via relay.
  @override
  Future<void> listen() async {
    // Clean up stale connection from previous session
    if (_channel != null) {
      debugPrint('ConnectionServiceWeb: Closing stale channel before re-listen');
      try { await _channel!.sink.close(); } catch (_) {}
      _channel = null;
      _isConnected = false;
    }

    // On web, the relay server handles incoming connections.
    // We connect to the relay and tell it to listen on our behalf.
    final relayUrl = await _getRelayUrl();
    if (relayUrl == null) {
      throw Exception('Relay server URL not configured');
    }

    debugPrint('ConnectionServiceWeb: Connecting to relay for listen mode...');

    try {
      _channel = WebSocketChannel.connect(
        Uri.parse('$relayUrl/listen'),
      );
      await _channel!.ready;
      _setupListener();
      debugPrint('ConnectionServiceWeb: Listening via relay');
    } catch (e) {
      debugPrint('ConnectionServiceWeb: Failed to connect to relay: $e');
      rethrow;
    }
  }

  /// Connect to a remote .onion address via relay.
  @override
  Future<void> connect(String onionAddress) async {
    if (_channel != null) {
      debugPrint('ConnectionServiceWeb: Already connected');
      await disconnect();
    }

    final targetHost =
        onionAddress.replaceAll(RegExp(r'^https?://'), '').trim();
    final relayUrl = await _getRelayUrl();

    if (relayUrl == null) {
      throw Exception('Relay server URL not configured');
    }

    debugPrint(
        'ConnectionServiceWeb: Connecting to $targetHost via relay...');

    try {
      _channel = WebSocketChannel.connect(
        Uri.parse('$relayUrl/connect?target=$targetHost&port=${AppConstants.listenPort}'),
      );
      await _channel!.ready;
      _setupListener();
      debugPrint('ConnectionServiceWeb: Connected to $targetHost via relay');
    } catch (e) {
      debugPrint('ConnectionServiceWeb: Connection failed: $e');
      rethrow;
    }
  }

  void _setupListener() {
    _isConnected = true;
    _lineBuffer = StringBuffer();

    _channel!.stream.listen(
      (data) {
        _processIncomingData(data.toString());
      },
      onError: (error) {
        debugPrint('ConnectionServiceWeb: WebSocket error: $error');
        _isConnected = false;
        _messageController.add(const MapEntry('ERROR', 'Connection error'));
      },
      onDone: () {
        debugPrint('ConnectionServiceWeb: WebSocket closed');
        _isConnected = false;
        _messageController.add(const MapEntry('DISCONNECTED', ''));
      },
    );
  }

  /// Process incoming data and parse line-based protocol messages.
  void _processIncomingData(String data) {
    _lineBuffer.write(data);
    final buffer = _lineBuffer.toString();
    final lines = buffer.split('\n');

    _lineBuffer = StringBuffer(lines.last);

    for (int i = 0; i < lines.length - 1; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      _parseProtocolMessage(line);
    }
  }

  void _parseProtocolMessage(String line) {
    // Unwrap HMAC if present
    String actualLine = line;
    if (line.startsWith(AppConstants.protoHmacPrefix)) {
      final unwrapped = unwrapMessage(line);
      if (unwrapped == null) {
        debugPrint('ConnectionServiceWeb: HMAC verification failed, dropping message');
        return;
      }
      actualLine = unwrapped;
    } else if (hmacEnabledFlag) {
      debugPrint('ConnectionServiceWeb: Unsigned message rejected (HMAC required)');
      return;
    }

    if (actualLine.startsWith(AppConstants.protoId)) {
      _messageController
          .add(MapEntry('ID', actualLine.substring(AppConstants.protoId.length)));
    } else if (actualLine.startsWith(AppConstants.protoCipher)) {
      _messageController.add(
          MapEntry('CIPHER', actualLine.substring(AppConstants.protoCipher.length)));
    } else if (actualLine == AppConstants.protoPttStart) {
      _messageController.add(const MapEntry('PTT_START', ''));
    } else if (actualLine == AppConstants.protoPttStop) {
      _messageController.add(const MapEntry('PTT_STOP', ''));
    } else if (actualLine.startsWith(AppConstants.protoAudio)) {
      _messageController.add(
          MapEntry('AUDIO', actualLine.substring(AppConstants.protoAudio.length)));
    } else if (actualLine.startsWith(AppConstants.protoMsg)) {
      _messageController
          .add(MapEntry('MSG', actualLine.substring(AppConstants.protoMsg.length)));
    } else if (actualLine == AppConstants.protoHangup) {
      _messageController.add(const MapEntry('HANGUP', ''));
    } else if (actualLine == AppConstants.protoPing) {
      _messageController.add(const MapEntry('PING', ''));
    } else if (actualLine.startsWith(AppConstants.protoSpake2Pub)) {
      _messageController.add(
          MapEntry('SPAKE2_PUB', actualLine.substring(AppConstants.protoSpake2Pub.length)));
    } else if (actualLine.startsWith(AppConstants.protoSpake2Confirm)) {
      _messageController.add(
          MapEntry('SPAKE2_CONFIRM', actualLine.substring(AppConstants.protoSpake2Confirm.length)));
    } else if (actualLine.startsWith('ERROR:')) {
      // Relay server error (e.g. SOCKS5 connection failed)
      debugPrint('ConnectionServiceWeb: Relay error: $actualLine');
      _messageController.add(MapEntry('ERROR', actualLine.substring(6)));
    } else if (actualLine == 'CONNECTED') {
      // Relay tunnel established — purely informational
      debugPrint('ConnectionServiceWeb: Relay tunnel established');
    } else {
      debugPrint('ConnectionServiceWeb: Unknown message: $actualLine');
    }
  }

  @override
  void send(String message) {
    if (_channel != null && _isConnected) {
      final wrapped = wrapMessage(message);
      _channel!.sink.add('$wrapped\n');
    }
  }

  @override
  void sendId(String onionAddress) =>
      send('${AppConstants.protoId}$onionAddress');
  @override
  void sendCipher(String cipher) =>
      send('${AppConstants.protoCipher}$cipher');
  @override
  void sendPttStart() => send(AppConstants.protoPttStart);
  @override
  void sendPttStop() => send(AppConstants.protoPttStop);
  @override
  void sendAudio(String base64Audio) =>
      send('${AppConstants.protoAudio}$base64Audio');
  @override
  void sendMessage(String base64Msg) =>
      send('${AppConstants.protoMsg}$base64Msg');
  @override
  void sendHangup() => send(AppConstants.protoHangup);
  @override
  void sendPing() => send(AppConstants.protoPing);

  @override
  Future<void> disconnect() async {
    try {
      sendHangup();
    } catch (_) {}

    _isConnected = false;
    await _channel?.sink.close();
    _channel = null;
  }

  @override
  void dispose() {
    disconnect();
    _messageController.close();
  }

  Future<String?> _getRelayUrl() async {
    // 1. Check if user manually configured a relay URL
    final prefs = await SharedPreferences.getInstance();
    final manual = prefs.getString('relay_server_url');
    if (manual != null && manual.isNotEmpty) {
      // Strip trailing '/ws' if present — the control channel (TorServiceWeb)
      // appends '/ws', but connection endpoints need the bare origin.
      var url = manual;
      if (url.endsWith('/ws')) {
        url = url.substring(0, url.length - 3);
      }
      return url;
    }

    // 2. Auto-detect from current page origin
    try {
      final loc = web.window.location;
      final protocol = loc.protocol == 'https:' ? 'wss' : 'ws';
      return '$protocol://${loc.host}';
    } catch (_) {
      return null;
    }
  }
}

ConnectionServiceBase createConnectionService() => ConnectionServiceWeb();
