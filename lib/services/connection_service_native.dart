import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/constants/app_constants.dart';
import 'connection_service_base.dart';

/// Callback for received protocol messages.
typedef MessageCallback = void Function(String type, String data);

/// Native TCP connection service that routes through Tor SOCKS5 proxy.
class ConnectionServiceNative extends ConnectionServiceBase {
  Socket? _socket;
  ServerSocket? _serverSocket;
  StreamSubscription<Uint8List>? _socketSubscription;
  final _messageController =
      StreamController<MapEntry<String, String>>.broadcast();
  bool _isConnected = false;
  StringBuffer _lineBuffer = StringBuffer();
  int? _actualPort;

  // Buffered reader state — used during SOCKS5 handshake so we never
  // subscribe to a Socket stream more than once.
  final List<int> _readBuffer = [];
  Completer<void>? _readCompleter;
  int _readTarget = 0;
  bool _handshakeComplete = false;

  @override
  Stream<MapEntry<String, String>> get messageStream =>
      _messageController.stream;
  @override
  bool get isConnected => _isConnected;
  @override
  int? get serverSocketPort => _actualPort;

  // ────────────────────────────── Socket listener ──────────────────────────

  /// Set up a **single** listener on [socket] for its entire lifetime.
  /// During the SOCKS5 handshake incoming bytes are buffered for
  /// [_readBytes]; after the handshake they are routed to the
  /// line-based protocol parser.
  void _setupSocketListener(Socket socket) {
    _socketSubscription?.cancel();
    _socketSubscription = socket.listen(
      (data) {
        if (!_handshakeComplete) {
          // Handshake phase — accumulate in buffer.
          _readBuffer.addAll(data);
          if (_readCompleter != null &&
              !_readCompleter!.isCompleted &&
              _readBuffer.length >= _readTarget) {
            _readCompleter!.complete();
          }
        } else {
          // Protocol phase — parse messages.
          _processIncomingData(utf8.decode(data, allowMalformed: true));
        }
      },
      onError: (error) {
        if (!_handshakeComplete &&
            _readCompleter != null &&
            !_readCompleter!.isCompleted) {
          _readCompleter!.completeError(error);
        }
        debugPrint('ConnectionService: Socket error: $error');
        _isConnected = false;
        _messageController.add(const MapEntry('ERROR', 'Connection error'));
      },
      onDone: () {
        if (!_handshakeComplete &&
            _readCompleter != null &&
            !_readCompleter!.isCompleted) {
          _readCompleter!.completeError(
            Exception('Socket closed during handshake'),
          );
        }
        debugPrint('ConnectionService: Socket closed');
        _isConnected = false;
        _messageController.add(const MapEntry('DISCONNECTED', ''));
      },
    );
  }

  // ────────────────────────────── Incoming ──────────────────────────────────

  /// Listen for incoming connections on the hidden service port.
  @override
  Future<void> listen({int? port}) async {
    // Always clean up stale sockets from previous sessions so we never
    // silently return with an old, unusable server socket.
    if (_serverSocket != null) {
      debugPrint(
        'ConnectionService: Closing stale server socket before re-listen',
      );
      try {
        await _serverSocket!.close();
      } catch (_) {}
      _serverSocket = null;
    }
    if (_socket != null) {
      debugPrint(
        'ConnectionService: Closing stale client socket before re-listen',
      );
      await _socketSubscription?.cancel();
      _socketSubscription = null;
      try {
        await _socket!.close();
      } catch (_) {}
      _socket = null;
      _isConnected = false;
    }

    final targetPort = port ?? AppConstants.listenPort;
    _serverSocket = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      targetPort,
      shared: true,
    );
    _actualPort = _serverSocket!.port;

    debugPrint('ConnectionService: Listening on port $_actualPort');

    _serverSocket!.listen((socket) {
      if (_isConnected) {
        debugPrint(
          'ConnectionService: Ignoring incoming connection from '
          '${socket.remoteAddress.address} while already connected',
        );
        socket.destroy();
        return;
      }
      debugPrint(
        'ConnectionService: Incoming connection from '
        '${socket.remoteAddress.address}',
      );
      _acceptSocket(socket);
    });
  }

  /// Handle incoming sockets. We do not immediately lock `_isConnected` because
  /// Tor periodically sends probes that connect and disconnect without sending data.
  /// We wait for the first valid protocol message (`ID` or `SPAKE2_PUB`) before
  /// promoting the socket to the active session.
  void _acceptSocket(Socket socket) {
    debugPrint(
      'ConnectionService: Incoming socket from ${socket.remoteAddress.address} (waiting for data)',
    );

    final tempBuffer = StringBuffer();
    StreamSubscription<Uint8List>? tempSub;

    tempSub = socket.listen(
      (data) {
        if (_isConnected && _socket != socket) {
          // Another incoming socket proved itself first.
          tempSub?.cancel();
          socket.destroy();
          return;
        }

        final text = utf8.decode(data, allowMalformed: true);

        if (!_isConnected) {
          tempBuffer.write(text);
          final accumulated = tempBuffer.toString();

          if (accumulated.contains(AppConstants.protoId) ||
              accumulated.contains(AppConstants.protoSpake2Pub)) {
            // This socket sent valid protocol data. Promote it!
            _socketSubscription?.cancel();
            _socketSubscription = tempSub;
            _socket = socket;
            _isConnected = true;
            _handshakeComplete = true; // SOCKS5 not needed for incoming
            _lineBuffer = tempBuffer;

            debugPrint(
              'ConnectionService: Incoming socket promoted to active connection',
            );
            _processIncomingData(''); // Process the accumulated data
          } else if (accumulated.length > 2048) {
            // Drop suspected garbage or port scanner
            tempSub?.cancel();
            socket.destroy();
          }
        } else if (_socket == socket) {
          // Normal active processing
          _processIncomingData(text);
        }
      },
      onError: (error) {
        if (_socket == socket) {
          debugPrint('ConnectionService: Socket error: $error');
          _isConnected = false;
          _messageController.add(const MapEntry('ERROR', 'Connection error'));
        }
        tempSub?.cancel();
        socket.destroy();
      },
      onDone: () {
        if (_socket == socket) {
          debugPrint('ConnectionService: Socket closed');
          _isConnected = false;
          _messageController.add(const MapEntry('DISCONNECTED', ''));
        }
        tempSub?.cancel();
        socket.destroy();
      },
    );
  }

  // ────────────────────────────── Outgoing ──────────────────────────────────

  /// Connect to a remote .onion address through Tor SOCKS5 proxy.
  @override
  Future<void> connect(String onionAddress) async {
    if (_socket != null) {
      debugPrint('ConnectionService: Already connected, disconnecting first');
      await disconnect();
    }

    final targetHost =
        onionAddress.replaceAll(RegExp(r'^https?://'), '').trim();

    debugPrint(
      'ConnectionService: Connecting to $targetHost through Tor SOCKS5...',
    );

    try {
      // Connect to Tor SOCKS5 proxy (with timeout so we don't hang
      // when the local Tor daemon isn't responding).
      _socket = await Socket.connect(
        AppConstants.torSocksHost,
        AppConstants.torSocksPort,
        timeout: const Duration(seconds: 15),
      );

      // Prepare single listener BEFORE sending any data.
      _handshakeComplete = false;
      _readBuffer.clear();
      _setupSocketListener(_socket!);

      // SOCKS5 handshake (uses _readBytes which pulls from the buffer).
      await _socks5Handshake(targetHost, AppConstants.listenPort);

      // Switch to protocol mode.
      _handshakeComplete = true;
      _isConnected = true;
      _lineBuffer = StringBuffer();

      debugPrint('ConnectionService: Connected to $targetHost');
    } catch (e) {
      debugPrint('ConnectionService: Connection failed: $e');
      _socketSubscription?.cancel();
      _socketSubscription = null;
      await _socket?.close();
      _socket = null;
      rethrow;
    }
  }

  // ────────────────────────────── SOCKS5 ────────────────────────────────────

  /// Perform SOCKS5 handshake for connecting through Tor.
  Future<void> _socks5Handshake(String host, int port) async {
    // SOCKS5 greeting: version 5, 1 method (no auth)
    _socket!.add([0x05, 0x01, 0x00]);
    await _socket!.flush();

    // Read server response (2 bytes)
    final greeting = await _readBytes(2);
    if (greeting[0] != 0x05 || greeting[1] != 0x00) {
      throw Exception('SOCKS5 handshake failed: unexpected response');
    }

    // SOCKS5 connect request
    final hostBytes = utf8.encode(host);
    final request = <int>[
      0x05, // Version
      0x01, // Connect
      0x00, // Reserved
      0x03, // Domain name
      hostBytes.length,
      ...hostBytes,
      (port >> 8) & 0xFF,
      port & 0xFF,
    ];
    _socket!.add(request);
    await _socket!.flush();

    // Read connect response (minimum 10 bytes)
    final response = await _readBytes(10);
    if (response[0] != 0x05 || response[1] != 0x00) {
      final errorCode = response[1];
      throw Exception('SOCKS5 connect failed with code: $errorCode');
    }

    debugPrint('ConnectionService: SOCKS5 tunnel established');
  }

  /// Read exactly [count] bytes from the buffered socket data.
  /// The single listener in [_setupSocketListener] feeds [_readBuffer].
  Future<Uint8List> _readBytes(int count) async {
    // Data may already be in the buffer.
    if (_readBuffer.length >= count) {
      final result = Uint8List.fromList(_readBuffer.sublist(0, count));
      _readBuffer.removeRange(0, count);
      return result;
    }

    // Wait for enough data to arrive.
    _readTarget = count;
    _readCompleter = Completer<void>();

    await _readCompleter!.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () {
        throw TimeoutException('SOCKS5 read timeout');
      },
    );

    final result = Uint8List.fromList(_readBuffer.sublist(0, count));
    _readBuffer.removeRange(0, count);
    return result;
  }

  /// Process incoming data and parse line-based protocol messages.
  void _processIncomingData(String data) {
    _lineBuffer.write(data);
    final buffer = _lineBuffer.toString();
    final lines = buffer.split('\n');

    // Keep the last incomplete line in the buffer
    _lineBuffer = StringBuffer(lines.last);

    for (int i = 0; i < lines.length - 1; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      _parseProtocolMessage(line);
    }
  }

  /// Parse a single protocol message (with HMAC unwrapping).
  void _parseProtocolMessage(String line) {
    // Unwrap HMAC if present
    String actualLine = line;
    if (line.startsWith(AppConstants.protoHmacPrefix)) {
      final unwrapped = unwrapMessage(line);
      if (unwrapped == null) {
        debugPrint(
          'ConnectionService: HMAC verification failed, dropping message',
        );
        return;
      }
      actualLine = unwrapped;
    } else if (hmacEnabledFlag) {
      // HMAC is enabled but message is not signed — reject
      debugPrint(
        'ConnectionService: Unsigned message rejected (HMAC required)',
      );
      return;
    }

    if (actualLine.startsWith(AppConstants.protoId)) {
      _messageController.add(
        MapEntry('ID', actualLine.substring(AppConstants.protoId.length)),
      );
    } else if (actualLine.startsWith(AppConstants.protoCipher)) {
      _messageController.add(
        MapEntry(
          'CIPHER',
          actualLine.substring(AppConstants.protoCipher.length),
        ),
      );
    } else if (actualLine == AppConstants.protoPttStart) {
      _messageController.add(const MapEntry('PTT_START', ''));
    } else if (actualLine == AppConstants.protoPttStop) {
      _messageController.add(const MapEntry('PTT_STOP', ''));
    } else if (actualLine.startsWith(AppConstants.protoAudio)) {
      _messageController.add(
        MapEntry('AUDIO', actualLine.substring(AppConstants.protoAudio.length)),
      );
    } else if (actualLine.startsWith(AppConstants.protoMsg)) {
      _messageController.add(
        MapEntry('MSG', actualLine.substring(AppConstants.protoMsg.length)),
      );
    } else if (actualLine == AppConstants.protoHangup) {
      _messageController.add(const MapEntry('HANGUP', ''));
    } else if (actualLine == AppConstants.protoPing) {
      _messageController.add(const MapEntry('PING', ''));
    } else if (actualLine.startsWith(AppConstants.protoSpake2Pub)) {
      _messageController.add(
        MapEntry(
          'SPAKE2_PUB',
          actualLine.substring(AppConstants.protoSpake2Pub.length),
        ),
      );
    } else if (actualLine.startsWith(AppConstants.protoSpake2Confirm)) {
      _messageController.add(
        MapEntry(
          'SPAKE2_CONFIRM',
          actualLine.substring(AppConstants.protoSpake2Confirm.length),
        ),
      );
    } else if (actualLine.startsWith('ERROR:')) {
      debugPrint('ConnectionService: Remote error: $actualLine');
      _messageController.add(MapEntry('ERROR', actualLine.substring(6)));
    } else if (actualLine == 'CONNECTED') {
      // Relay tunnel notification — ignore on native
    } else {
      debugPrint('ConnectionService: Unknown message: $actualLine');
    }
  }

  /// Send a protocol message (HMAC-wrapped if enabled).
  @override
  void send(String message) {
    if (_socket != null && _isConnected) {
      final wrapped = wrapMessage(message);
      _socket!.write('$wrapped\n');
    }
  }

  /// Send caller ID.
  @override
  void sendId(String onionAddress) =>
      send('${AppConstants.protoId}$onionAddress');

  /// Send cipher info.
  @override
  void sendCipher(String cipher) => send('${AppConstants.protoCipher}$cipher');

  /// Send PTT start signal.
  @override
  void sendPttStart() => send(AppConstants.protoPttStart);

  /// Send PTT stop signal.
  @override
  void sendPttStop() => send(AppConstants.protoPttStop);

  /// Send encrypted audio data.
  @override
  void sendAudio(String base64Audio) =>
      send('${AppConstants.protoAudio}$base64Audio');

  /// Send encrypted text message.
  @override
  void sendMessage(String base64Msg) =>
      send('${AppConstants.protoMsg}$base64Msg');

  /// Send hangup signal.
  @override
  void sendHangup() => send(AppConstants.protoHangup);

  /// Send ping keepalive.
  @override
  void sendPing() => send(AppConstants.protoPing);

  /// Close the connection.
  @override
  Future<void> disconnect() async {
    try {
      sendHangup();
    } catch (_) {}

    _isConnected = false;
    _handshakeComplete = false;
    setHmac(enabled: false, key: '');
    _readBuffer.clear();
    await _socketSubscription?.cancel();
    _socketSubscription = null;
    await _socket?.close();
    _socket = null;
    await _serverSocket?.close();
    _serverSocket = null;
  }

  @override
  void dispose() {
    disconnect();
    _messageController.close();
  }
}

ConnectionServiceBase createConnectionService() => ConnectionServiceNative();
