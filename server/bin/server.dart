import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_static/shelf_static.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// ─── Configuration ──────────────────────────────────────────────────

const int defaultPort = 8080;
const int torSocksPort = 9050;
const int torControlPort = 9051;
const int hiddenServicePort = 7777;
const String torSocksHost = '127.0.0.1';

// ─── Main ───────────────────────────────────────────────────────────

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('port',
        abbr: 'p', defaultsTo: '$defaultPort', help: 'HTTP server port')
    ..addOption('host',
        abbr: 'H', defaultsTo: '0.0.0.0', help: 'Bind address (0.0.0.0 for LAN)')
    ..addOption('web-dir',
        abbr: 'w',
        defaultsTo: '../build/web',
        help: 'Path to Flutter web build output')
    ..addOption('tor-socks',
        defaultsTo: '$torSocksHost:$torSocksPort',
        help: 'Tor SOCKS5 proxy address')
    ..addOption('tor-data',
        defaultsTo: './tor_data', help: 'Tor data directory')
    ..addFlag('no-tor',
        defaultsTo: false,
        help: 'Don\'t auto-start Tor (assume it\'s already running)')
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show help');

  final results = parser.parse(arguments);
  if (results['help'] as bool) {
    print('OnionTalkie Local Server\n');
    print(parser.usage);
    exit(0);
  }

  final port = int.parse(results['port'] as String);
  final host = results['host'] as String;
  final webDir = results['web-dir'] as String;
  final torSocks = results['tor-socks'] as String;
  final torDataDir = results['tor-data'] as String;
  final noTor = results['no-tor'] as bool;

  final socksHost = torSocks.split(':')[0];
  final socksPort = int.parse(torSocks.split(':')[1]);

  // Resolve web directory
  final webDirResolved = Directory(webDir);
  if (!webDirResolved.existsSync()) {
    stderr.writeln('❌ Web directory not found: ${webDirResolved.absolute.path}');
    stderr.writeln('   Run "flutter build web --release" first.');
    exit(1);
  }

  print(r'''
   ___  _   _ ___ ___  _   _ 
  / _ \| \ | |_ _/ _ \| \ | |
 | | | |  \| || | | | |  \| |
 | |_| | |\  || | |_| | |\  |
  \___/|_| \_|___\___/|_| \_|  Talkie Server
  ''');

  // ── Start/check Tor ──
  String? onionAddress;
  Process? torProcess;

  if (!noTor) {
    final torBinary = await _findTorBinary();
    if (torBinary == null) {
      stderr.writeln('❌ Tor non trovato! Installa Tor e riprova.');
      stderr.writeln('   macOS:   brew install tor');
      stderr.writeln('   Linux:   sudo apt install tor');
      stderr.writeln('   Windows: https://www.torproject.org/download/');
      stderr.writeln('   Oppure avvia con --no-tor se Tor è già in esecuzione.');
      exit(1);
    }

    print('🧅 Avvio Tor...');
    final result = await _startTor(
      torBinary: torBinary,
      dataDir: torDataDir,
      socksPort: socksPort,
      controlPort: torControlPort,
      hiddenServicePort: hiddenServicePort,
      localListenPort: hiddenServicePort,
    );
    torProcess = result.process;
    onionAddress = result.onionAddress;
  } else {
    // Check if Tor is reachable
    print('🔍 Verifica connessione Tor SOCKS5 su $socksHost:$socksPort...');
    try {
      final sock = await Socket.connect(socksHost, socksPort,
          timeout: const Duration(seconds: 5));
      sock.destroy();
      print('✅ Tor SOCKS5 raggiungibile.');

      // Try to read onion address from existing Tor data
      onionAddress = await _readOnionAddress(torDataDir);
    } catch (_) {
      stderr
          .writeln('⚠️  Tor SOCKS5 non raggiungibile su $socksHost:$socksPort');
      stderr.writeln('   Assicurati che Tor sia in esecuzione.');
    }
  }

  if (onionAddress != null) {
    print('🧅 Indirizzo Onion: $onionAddress');
  }

  // ── Bridge state ──
  final bridge = TorBridge(
    socksHost: socksHost,
    socksPort: socksPort,
    onionAddress: onionAddress,
    hiddenServicePort: hiddenServicePort,
  );

  // ── Start incoming TCP listener (hidden service target) ──
  await bridge.startIncomingListener();

  // ── Build HTTP + WebSocket handler ──
  final staticHandler = createStaticHandler(
    webDirResolved.absolute.path,
    defaultDocument: 'index.html',
  );

  final cascade = shelf.Cascade()
      .add(_webSocketRouter(bridge))
      .add(staticHandler);

  final handler = const shelf.Pipeline()
      .addMiddleware(shelf.logRequests())
      .addMiddleware(_corsMiddleware())
      .addHandler(cascade.handler);

  // ── Start HTTP server ──
  final server = await shelf_io.serve(handler, host, port);
  server.autoCompress = true;

  final localIp = await _getLocalIp();
  print('');
  print('🌐 Server avviato:');
  print('   Locale:   http://localhost:$port');
  if (localIp != null) {
    print('   LAN:      http://$localIp:$port');
  }
  print('');
  print('📱 Apri l\'URL nel browser di qualsiasi dispositivo sulla rete locale.');
  print('   Il relay WebSocket è integrato — nessuna configurazione necessaria.');
  print('');
  print('   Premi Ctrl+C per arrestare.\n');

  // ── Handle shutdown ──
  ProcessSignal.sigint.watch().listen((_) async {
    print('\n🛑 Arresto in corso...');
    await bridge.dispose();
    torProcess?.kill();
    server.close(force: true);
    exit(0);
  });
  // SIGTERM for Docker / systemd
  if (!Platform.isWindows) {
    ProcessSignal.sigterm.watch().listen((_) async {
      await bridge.dispose();
      torProcess?.kill();
      server.close(force: true);
      exit(0);
    });
  }
}

// ═══════════════════════════════════════════════════════════════════════
// WebSocket routing — matches the protocol expected by the Flutter web app
// ═══════════════════════════════════════════════════════════════════════

shelf.Handler _webSocketRouter(TorBridge bridge) {
  return (shelf.Request request) {
    final path = request.url.path;

    // /ws — Control channel (TorServiceWeb connects here)
    if (path == 'ws' || path == '') {
      return webSocketHandler((WebSocketChannel ws, String? protocol) {
        bridge.handleControlSocket(ws);
      })(request);
    }

    // /listen — Incoming call listener (ConnectionServiceWeb.listen)
    if (path == 'listen') {
      return webSocketHandler((WebSocketChannel ws, String? protocol) {
        bridge.handleListenSocket(ws);
      })(request);
    }

    // /connect?target=xxx.onion&port=7777 — Outgoing call (ConnectionServiceWeb.connect)
    if (path == 'connect') {
      final target = request.url.queryParameters['target'];
      final port =
          int.tryParse(request.url.queryParameters['port'] ?? '') ?? 7777;
      if (target == null) {
        return shelf.Response.badRequest(body: 'Missing target parameter');
      }
      return webSocketHandler((WebSocketChannel ws, String? protocol) {
        bridge.handleConnectSocket(ws, target, port);
      })(request);
    }

    return shelf.Response.notFound('Not found');
  };
}

// ═══════════════════════════════════════════════════════════════════════
// TorBridge — bridges WebSocket ↔ TCP through Tor SOCKS5
// ═══════════════════════════════════════════════════════════════════════

/// Wraps a browser WebSocket waiting for an incoming call.
/// The original WS stream is consumed once (for cleanup detection);
/// a forwarded StreamController is used for bridging so we never
/// call .listen() twice on the same single-subscription stream.
class _ListenClient {
  final WebSocketChannel ws;
  final StreamController<dynamic> _forwarded = StreamController<dynamic>();

  Stream<dynamic> get incomingStream => _forwarded.stream;

  _ListenClient(this.ws);

  void addData(dynamic data) {
    if (!_forwarded.isClosed) _forwarded.add(data);
  }

  void close() {
    if (!_forwarded.isClosed) _forwarded.close();
  }
}

class TorBridge {
  final String socksHost;
  final int socksPort;
  String? onionAddress;
  final int hiddenServicePort;

  ServerSocket? _incomingServer;
  final List<_ListenClient> _listenClients = [];

  TorBridge({
    required this.socksHost,
    required this.socksPort,
    required this.onionAddress,
    required this.hiddenServicePort,
  });

  // ── Control socket (TorServiceWeb) ──

  void handleControlSocket(WebSocketChannel ws) {
    print('🔌 Control WebSocket connesso');

    ws.stream.listen(
      (message) {
        final msg = message.toString();

        if (msg.startsWith('CMD:START')) {
          // Tor is already running — just report progress
          Future.delayed(const Duration(milliseconds: 200), () {
            ws.sink.add('BOOTSTRAP:30');
          });
          Future.delayed(const Duration(milliseconds: 500), () {
            ws.sink.add('BOOTSTRAP:60');
          });
          Future.delayed(const Duration(milliseconds: 800), () {
            ws.sink.add('BOOTSTRAP:100');
          });
        } else if (msg == 'CMD:ONION') {
          if (onionAddress != null) {
            ws.sink.add('ONION:$onionAddress');
          } else {
            ws.sink.add('ERROR:Onion address not available');
          }
        } else if (msg == 'CMD:STOP') {
          ws.sink.add('STOPPED');
        } else if (msg == 'CMD:ROTATE') {
          ws.sink.add('ERROR:Rotation not supported in local mode. Restart Tor to get a new address.');
        }
      },
      onDone: () {
        print('🔌 Control WebSocket disconnesso');
      },
      onError: (e) {
        print('❌ Control WebSocket errore: $e');
      },
    );
  }

  // ── Listen socket (incoming calls) ──

  Future<void> startIncomingListener() async {
    try {
      _incomingServer = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        hiddenServicePort,
      );
      print('👂 In ascolto per chiamate in entrata sulla porta $hiddenServicePort');

      _incomingServer!.listen((Socket tcpSocket) {
        print('📞 Chiamata in entrata da ${tcpSocket.remoteAddress.address}');
        _bridgeIncomingToWebSocket(tcpSocket);
      });
    } catch (e) {
      print('⚠️  Impossibile avviare listener sulla porta $hiddenServicePort: $e');
      print('   Porta già in uso? Un\'altro istanza potrebbe essere in esecuzione.');
    }
  }

  void handleListenSocket(WebSocketChannel ws) {
    print('👂 Browser registrato per chiamate in entrata');
    final client = _ListenClient(ws);
    _listenClients.add(client);

    // Start a periodic WebSocket ping to prevent idle timeouts
    // (browsers, proxies and load balancers often close idle WS after
    // 30-60s).  We send a lightweight PING every 25 seconds.
    final keepAlive = Timer.periodic(
      const Duration(seconds: 25),
      (_) {
        try {
          ws.sink.add('PING\n');
        } catch (_) {}
      },
    );

    // Listen once — forward data to the StreamController so the bridge
    // can consume it later without a second .listen() on the WS stream.
    ws.stream.listen(
      (data) => client.addData(data),
      onDone: () {
        keepAlive.cancel();
        _listenClients.remove(client);
        client.close();
        print('👂 Browser rimosso dall\'ascolto');
      },
      onError: (_) {
        keepAlive.cancel();
        _listenClients.remove(client);
        client.close();
      },
    );
  }

  /// Bridge an incoming TCP connection (from Tor hidden service) to the
  /// first registered browser WebSocket client.
  void _bridgeIncomingToWebSocket(Socket tcpSocket) {
    if (_listenClients.isEmpty) {
      print('⚠️  Nessun browser in ascolto — rifiuto chiamata');
      tcpSocket.destroy();
      return;
    }

    // Take the first listen client and upgrade it to a bidirectional bridge
    final client = _listenClients.removeAt(0);
    print('🔗 Bridge TCP → WebSocket per chiamata in entrata');

    // TCP → WebSocket
    tcpSocket.listen(
      (data) {
        try {
          client.ws.sink.add(utf8.decode(data, allowMalformed: true));
        } catch (_) {}
      },
      onDone: () {
        try { client.ws.sink.close(); } catch (_) {}
        client.close();
        print('🔗 Chiamata in entrata terminata (TCP chiuso)');
      },
      onError: (_) {
        try { client.ws.sink.close(); } catch (_) {}
        client.close();
      },
    );

    // WebSocket → TCP (use the forwarded stream — never a second .listen()!)
    client.incomingStream.listen(
      (data) {
        try {
          tcpSocket.add(utf8.encode(data.toString()));
        } catch (_) {}
      },
      onDone: () {
        try { tcpSocket.destroy(); } catch (_) {}
        print('🔗 Chiamata in entrata terminata (WS chiuso)');
      },
      onError: (_) {
        try { tcpSocket.destroy(); } catch (_) {}
      },
    );
  }

  // ── Connect socket (outgoing calls via SOCKS5) ──

  void handleConnectSocket(WebSocketChannel ws, String target, int port) {
    print('📤 Connessione in uscita verso $target:$port via Tor SOCKS5...');
    _connectAndBridge(ws, target, port);
  }

  /// Open a SOCKS5 tunnel towards [target]:[port] and bridge it to [ws].
  ///
  /// Retries up to 3 times on SOCKS5 failure (Tor .onion circuits are
  /// inherently unreliable and frequently fail on the first attempt).
  /// Each attempt creates a fresh socket so we never double-listen on a
  /// single-subscription stream.
  Future<void> _connectAndBridge(
      WebSocketChannel ws, String target, int port) async {
    const maxAttempts = 3;

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      Socket? socket;
      try {
        socket = await Socket.connect(
          socksHost,
          socksPort,
          timeout: const Duration(seconds: 60),
        );

        // ── Single listener + buffered reader ──
        final readBuffer = <int>[];
        Completer<void>? dataReady;
        var handshakeComplete = false;

        socket.listen(
          (data) {
            if (!handshakeComplete) {
              readBuffer.addAll(data);
              if (dataReady != null && !dataReady!.isCompleted) {
                dataReady!.complete();
              }
            } else {
              // Bridge mode: TCP → WebSocket
              try {
                ws.sink.add(utf8.decode(data, allowMalformed: true));
              } catch (_) {}
            }
          },
          onDone: () {
            if (!handshakeComplete) {
              if (dataReady != null && !dataReady!.isCompleted) {
                dataReady!.completeError(
                    Exception('Socket closed during SOCKS5 handshake'));
              }
            } else {
              try { ws.sink.close(); } catch (_) {}
              print('📤 Connessione in uscita terminata (TCP chiuso)');
            }
          },
          onError: (e) {
            if (!handshakeComplete) {
              if (dataReady != null && !dataReady!.isCompleted) {
                dataReady!.completeError(e);
              }
            } else {
              try { ws.sink.close(); } catch (_) {}
            }
          },
        );

        // Helper: read exactly N bytes from the buffer
        Future<List<int>> readExact(int count) async {
          while (readBuffer.length < count) {
            dataReady = Completer<void>();
            await dataReady!.future.timeout(
              const Duration(seconds: 60),
              onTimeout: () =>
                  throw TimeoutException('SOCKS5 read timeout'),
            );
          }
          final result = readBuffer.sublist(0, count);
          readBuffer.removeRange(0, count);
          return result;
        }

        // SOCKS5 greeting: version 5, 1 method (no auth)
        socket.add([0x05, 0x01, 0x00]);
        await socket.flush();

        final greeting = await readExact(2);
        if (greeting[0] != 0x05 || greeting[1] != 0x00) {
          throw Exception('SOCKS5 handshake failed');
        }

        // SOCKS5 connect request: version 5, connect, reserved, domain
        final hostBytes = utf8.encode(target);
        socket.add([
          0x05, 0x01, 0x00, 0x03,
          hostBytes.length,
          ...hostBytes,
          (port >> 8) & 0xFF,
          port & 0xFF,
        ]);
        await socket.flush();

        final response = await readExact(10);
        if (response[0] != 0x05 || response[1] != 0x00) {
          throw Exception('SOCKS5 connect failed (code: ${response[1]})');
        }

        // ── Handshake succeeded — switch to bridge mode ──
        print('✅ Tunnel SOCKS5 stabilito verso $target (tentativo $attempt)');
        ws.sink.add('CONNECTED\n');
        handshakeComplete = true;

        // Flush any leftover data already buffered
        if (readBuffer.isNotEmpty) {
          ws.sink.add(utf8.decode(readBuffer, allowMalformed: true));
          readBuffer.clear();
        }

        // WebSocket → TCP
        ws.stream.listen(
          (data) {
            try {
              socket!.add(utf8.encode(data.toString()));
            } catch (_) {}
          },
          onDone: () {
            try { socket!.destroy(); } catch (_) {}
            print('📤 Connessione in uscita terminata (WS chiuso)');
          },
          onError: (_) {
            try { socket!.destroy(); } catch (_) {}
          },
        );

        return; // success — bridge is running

      } catch (e) {
        print('❌ Tentativo $attempt/$maxAttempts SOCKS5 fallito: $e');
        try { socket?.destroy(); } catch (_) {}

        if (attempt == maxAttempts) {
          print('❌ Connessione SOCKS5 fallita dopo $maxAttempts tentativi');
          try {
            ws.sink.add('ERROR:Connection failed after $maxAttempts attempts: $e\n');
            ws.sink.close();
          } catch (_) {}
          return;
        }

        final delay = Duration(seconds: 2 * attempt);
        print('⏳ Attesa ${delay.inSeconds}s prima del prossimo tentativo...');
        await Future.delayed(delay);
      }
    }
  }

  Future<void> dispose() async {
    for (final client in _listenClients) {
      try { client.ws.sink.close(); } catch (_) {}
      client.close();
    }
    _listenClients.clear();
    await _incomingServer?.close();
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Tor process management
// ═══════════════════════════════════════════════════════════════════════

class _TorStartResult {
  final Process process;
  final String? onionAddress;
  _TorStartResult(this.process, this.onionAddress);
}

Future<String?> _findTorBinary() async {
  final candidates = [
    'tor',
    '/opt/homebrew/bin/tor',
    '/usr/local/bin/tor',
    '/usr/bin/tor',
  ];
  for (final path in candidates) {
    try {
      final result = await Process.run(path, ['--version']);
      if (result.exitCode == 0) return path;
    } catch (_) {}
  }
  return null;
}

Future<_TorStartResult> _startTor({
  required String torBinary,
  required String dataDir,
  required int socksPort,
  required int controlPort,
  required int hiddenServicePort,
  required int localListenPort,
}) async {
  final dataDirObj = Directory(dataDir);
  if (!dataDirObj.existsSync()) {
    dataDirObj.createSync(recursive: true);
  }

  final hsDir = Directory('$dataDir/hidden_service');
  if (!hsDir.existsSync()) {
    hsDir.createSync(recursive: true);
    // Set permissions (Tor requires 700)
    await Process.run('chmod', ['700', hsDir.path]);
  }

  // Write torrc
  final torrc = '''
SocksPort $socksPort
ControlPort $controlPort
DataDirectory ${dataDirObj.absolute.path}
HiddenServiceDir ${hsDir.absolute.path}
HiddenServicePort $hiddenServicePort 127.0.0.1:$localListenPort
Log notice stdout
''';

  final torrcFile = File('$dataDir/torrc');
  torrcFile.writeAsStringSync(torrc);

  print('📝 Torrc generato: ${torrcFile.absolute.path}');

  final process = await Process.start(
    torBinary,
    ['-f', torrcFile.absolute.path],
  );

  // Wait for bootstrap to reach 100%
  final completer = Completer<void>();
  String? onionAddr;

  process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(
    (line) {
      if (line.contains('Bootstrapped 100%')) {
        // Read onion address
        final hostnameFile = File('${hsDir.path}/hostname');
        if (hostnameFile.existsSync()) {
          onionAddr = hostnameFile.readAsStringSync().trim();
        }
        if (!completer.isCompleted) completer.complete();
      }
      // Print tor log with prefix
      stdout.writeln('  [tor] $line');
    },
  );

  process.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen(
    (line) {
      stderr.writeln('  [tor:err] $line');
    },
  );

  // Wait for bootstrap (up to 2 minutes)
  try {
    await completer.future.timeout(const Duration(minutes: 2));
    print('✅ Tor avviato e connesso!');
  } catch (_) {
    print('⚠️  Timeout bootstrap Tor — potrebbe essere ancora in avvio.');
    // Try reading the address anyway
    final hostnameFile = File('${hsDir.path}/hostname');
    if (hostnameFile.existsSync()) {
      onionAddr = hostnameFile.readAsStringSync().trim();
    }
  }

  return _TorStartResult(process, onionAddr);
}

Future<String?> _readOnionAddress(String dataDir) async {
  final hostnameFile = File('$dataDir/hidden_service/hostname');
  if (hostnameFile.existsSync()) {
    return hostnameFile.readAsStringSync().trim();
  }
  return null;
}

// ═══════════════════════════════════════════════════════════════════════
// Utils
// ═══════════════════════════════════════════════════════════════════════

shelf.Middleware _corsMiddleware() {
  return (shelf.Handler handler) {
    return (shelf.Request request) async {
      if (request.method == 'OPTIONS') {
        return shelf.Response.ok('', headers: _corsHeaders);
      }
      final response = await handler(request);
      return response.change(headers: _corsHeaders);
    };
  };
}

const _corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
};

Future<String?> _getLocalIp() async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        if (!addr.isLoopback) return addr.address;
      }
    }
  } catch (_) {}
  return null;
}
