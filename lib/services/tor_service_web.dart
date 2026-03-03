import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:web/web.dart' as web;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/tor_status.dart';
import 'tor_service_base.dart';

/// Web implementation of TorService.
///
/// On the web, Tor cannot run locally. This implementation connects to a
/// **relay server** via WebSocket. The relay server runs Tor and bridges
/// WebSocket traffic to the Tor network.
///
/// The user configures the relay URL in settings (e.g. wss://relay.example.com/ws).
class TorServiceWeb extends TorServiceBase {
  TorStatus _status = const TorStatus();
  final _statusController = StreamController<TorStatus>.broadcast();
  WebSocketChannel? _relayChannel;
  StreamSubscription? _relaySubscription;
  String? _relayUrl;
  String? _onionAddress;

  @override
  Stream<TorStatus> get statusStream => _statusController.stream;
  @override
  TorStatus get currentStatus => _status;

  /// On web, "installed" means a relay server URL is configured and reachable.
  @override
  Future<bool> isTorInstalled() async {
    _relayUrl = await _loadRelayUrl();
    return _relayUrl != null && _relayUrl!.isNotEmpty;
  }

  @override
  List<TorInstallOption> getInstallOptions() {
    return const [
      TorInstallOption(
        name: 'Server locale (consigliato)',
        description:
            'Avvia il server locale incluso nel progetto con '
            '"./start.sh". Serve l\'app web e fa da ponte verso Tor.',
        iconType: IconType.terminal,
      ),
      TorInstallOption(
        name: 'Installa Tor',
        description:
            'macOS: brew install tor\n'
            'Linux: sudo apt install tor\n'
            'Windows: torproject.org/download',
        url: 'https://www.torproject.org/download/',
        iconType: IconType.download,
      ),
      TorInstallOption(
        name: 'Versione nativa Android/iOS',
        description:
            'Per la migliore esperienza, usa l\'app nativa che '
            'gestisce Tor direttamente sul dispositivo.',
        url: 'https://github.com/AnonCatalyst/OnionTalkie/releases',
        iconType: IconType.download,
      ),
    ];
  }

  @override
  Future<void> start({bool snowflake = false, String excludeNodes = ''}) async {
    if (_status.state == TorConnectionState.connected ||
        _status.state == TorConnectionState.starting) {
      return;
    }

    _relayUrl = await _loadRelayUrl();
    if (_relayUrl == null || _relayUrl!.isEmpty) {
      _updateStatus(_status.copyWith(
        state: TorConnectionState.notInstalled,
        errorMessage: 'URL del relay server non configurato. '
            'Vai nelle impostazioni per configurarlo.',
      ));
      return;
    }

    _updateStatus(_status.copyWith(
      state: TorConnectionState.starting,
      bootstrapProgress: 0,
      errorMessage: null,
    ));

    try {
      _relayChannel = WebSocketChannel.connect(Uri.parse(_relayUrl!));
      await _relayChannel!.ready;

      _updateStatus(_status.copyWith(
        state: TorConnectionState.bootstrapping,
        bootstrapProgress: 30,
      ));

      // Send start command to relay
      _relayChannel!.sink.add('CMD:START${snowflake ? ':SNOWFLAKE' : ''}');

      _relaySubscription = _relayChannel!.stream.listen(
        (message) => _handleRelayMessage(message.toString()),
        onError: (error) {
          _updateStatus(_status.copyWith(
            state: TorConnectionState.error,
            errorMessage: 'Relay connection error: $error',
          ));
        },
        onDone: () {
          if (_status.state != TorConnectionState.stopped) {
            _updateStatus(_status.copyWith(
              state: TorConnectionState.error,
              errorMessage: 'Relay connection closed',
            ));
          }
        },
      );
    } catch (e) {
      _updateStatus(_status.copyWith(
        state: TorConnectionState.error,
        errorMessage: 'Failed to connect to relay: $e',
      ));
    }
  }

  void _handleRelayMessage(String message) {
    if (message.startsWith('BOOTSTRAP:')) {
      final progress = int.tryParse(message.substring(10)) ?? 0;
      _updateStatus(_status.copyWith(
        state: TorConnectionState.bootstrapping,
        bootstrapProgress: progress,
      ));
      if (progress == 100) {
        _relayChannel!.sink.add('CMD:ONION');
      }
    } else if (message.startsWith('ONION:')) {
      _onionAddress = message.substring(6).trim();
      _updateStatus(_status.copyWith(
        state: TorConnectionState.connected,
        onionAddress: _onionAddress,
        bootstrapProgress: 100,
      ));
    } else if (message.startsWith('ERROR:')) {
      _updateStatus(_status.copyWith(
        state: TorConnectionState.error,
        errorMessage: message.substring(6),
      ));
    } else if (message == 'STOPPED') {
      _updateStatus(const TorStatus(state: TorConnectionState.stopped));
    } else if (message.startsWith('CIRCUIT:')) {
      _updateStatus(_status.copyWith(
        circuitPath: message.substring(8),
        lastCircuitRefresh: DateTime.now(),
      ));
    }
  }

  @override
  Future<void> stop() async {
    try {
      _relayChannel?.sink.add('CMD:STOP');
    } catch (_) {}
    _relaySubscription?.cancel();
    await _relayChannel?.sink.close();
    _relayChannel = null;
    _updateStatus(const TorStatus(state: TorConnectionState.stopped));
  }

  @override
  Future<void> restart({bool snowflake = false, String excludeNodes = ''}) async {
    await stop();
    await Future.delayed(const Duration(seconds: 1));
    await start(snowflake: snowflake, excludeNodes: excludeNodes);
  }

  @override
  Future<void> rotateOnionAddress() async {
    if (_relayChannel != null) {
      _relayChannel!.sink.add('CMD:ROTATE');
    }
  }

  @override
  Future<String?> getOnionAddress() async => _onionAddress;

  /// Get circuit path from the relay server.
  @override
  Future<String?> getCircuitPath() async {
    if (_relayChannel == null || _status.state != TorConnectionState.connected) {
      return null;
    }
    try {
      _relayChannel!.sink.add('CMD:CIRCUIT');
      // The response will come asynchronously through _handleRelayMessage
      // Return the cached circuit path from status
      return _status.circuitPath;
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _relaySubscription?.cancel();
    _relayChannel?.sink.close();
    _statusController.close();
  }

  void _updateStatus(TorStatus newStatus) {
    _status = newStatus;
    _statusController.add(newStatus);
  }

  Future<String?> _loadRelayUrl() async {
    // 1. Check if user manually configured a relay URL
    final prefs = await SharedPreferences.getInstance();
    final manual = prefs.getString('relay_server_url');
    if (manual != null && manual.isNotEmpty) return manual;

    // 2. Auto-detect: derive WebSocket URL from the page origin
    //    e.g. http://192.168.1.10:8080 → ws://192.168.1.10:8080/ws
    try {
      final loc = web.window.location;
      final protocol = loc.protocol == 'https:' ? 'wss' : 'ws';
      return '$protocol://${loc.host}/ws';
    } catch (_) {
      return null;
    }
  }
}

TorServiceBase createTorService() => TorServiceWeb();
