import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web/web.dart' as web;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/tor_status.dart';
import 'circuit_service.dart';
import 'tor_service_base.dart';

/// Web implementation of TorService.
///
/// On the web, Tor cannot run locally. This implementation connects to a
/// **relay server** via WebSocket. The relay server runs Tor and bridges
/// WebSocket traffic to the Tor network.
class TorServiceWeb extends TorServiceBase {
  TorStatus _status = const TorStatus();
  final _statusController = StreamController<TorStatus>.broadcast();
  WebSocketChannel? _relayChannel;
  StreamSubscription? _relaySubscription;
  String? _onionAddress;
  Completer<bool>? _probeCompleter;
  Completer<bool>? _pingCompleter;
  Completer<List<CircuitHop>?>? _circuitCompleter;

  /// Default public community relays for zero-config fallback.
  static const _publicRelays = [
    'wss://relay1.oniontalkie.org/ws',
    'wss://relay2.oniontalkie.org/ws',
    'wss://onion-relay.secure.pub/ws',
  ];

  @override
  Stream<TorStatus> get statusStream => _statusController.stream;
  @override
  TorStatus get currentStatus => _status;

  @override
  Future<bool> isTorInstalled() async {
    final relayUrls = await _getAvailableRelayUrls();
    return relayUrls.isNotEmpty;
  }

  @override
  List<TorInstallOption> getInstallOptions() {
    return const [
      TorInstallOption(
        name: 'Local server (recommended)',
        description:
            'Start the local server included in the project with '
            '"./start.sh". Serves the web app and bridges to Tor.',
        iconType: IconType.terminal,
      ),
      TorInstallOption(
        name: 'Install Tor',
        description:
            'macOS: brew install tor\n'
            'Linux: sudo apt install tor\n'
            'Windows: torproject.org/download',
        url: 'https://www.torproject.org/download/',
        iconType: IconType.download,
      ),
      TorInstallOption(
        name: 'Native Android/iOS version',
        description:
            'For the best experience, use the native app which '
            'manages Tor directly on the device.',
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

    final relayUrls = await _getAvailableRelayUrls();
    if (relayUrls.isEmpty) {
      _updateStatus(
        _status.copyWith(
          state: TorConnectionState.notInstalled,
          errorMessage:
              'Nessun relay server disponibile. '
              'Configura un URL nelle impostazioni o verifica la connessione.',
        ),
      );
      return;
    }

    _updateStatus(
      _status.copyWith(
        state: TorConnectionState.starting,
        bootstrapProgress: 0,
        errorMessage: null,
      ),
    );

    // Attempt to connect to available relays in order
    for (final url in relayUrls) {
      try {
        _relayChannel = WebSocketChannel.connect(Uri.parse(url));
        await _relayChannel!.ready;
        _startRelaySubscription(snowflake);
        return; // Success
      } catch (e) {
        debugPrint('WebTor: Failed to connect to relay $url: $e');
        continue;
      }
    }

    _updateStatus(
      _status.copyWith(
        state: TorConnectionState.error,
        errorMessage: 'Impossibile connettersi ai relay server disponibili.',
      ),
    );
  }

  void _startRelaySubscription(bool snowflake) {
    _updateStatus(
      _status.copyWith(
        state: TorConnectionState.bootstrapping,
        bootstrapProgress: 30,
      ),
    );

    // Send start command to relay
    _relayChannel!.sink.add('CMD:START${snowflake ? ':SNOWFLAKE' : ''}');

    _relaySubscription = _relayChannel!.stream.listen(
      (message) => _handleRelayMessage(message.toString()),
      onError: (error) {
        _updateStatus(
          _status.copyWith(
            state: TorConnectionState.error,
            errorMessage: 'Relay connection error: $error',
          ),
        );
      },
      onDone: () {
        if (_status.state != TorConnectionState.stopped) {
          _updateStatus(
            _status.copyWith(
              state: TorConnectionState.error,
              errorMessage: 'Relay connection closed',
            ),
          );
        }
      },
    );
  }

  void _handleRelayMessage(String message) {
    if (message.startsWith('BOOTSTRAP:')) {
      final progress = int.tryParse(message.substring(10)) ?? 0;
      _updateStatus(
        _status.copyWith(
          state: TorConnectionState.bootstrapping,
          bootstrapProgress: progress,
        ),
      );
      if (progress == 100) {
        _relayChannel!.sink.add('CMD:ONION');
      }
    } else if (message.startsWith('ONION:')) {
      _onionAddress = message.substring(6).trim();
      _updateStatus(
        _status.copyWith(
          state: TorConnectionState.connected,
          onionAddress: _onionAddress,
          bootstrapProgress: 100,
        ),
      );
    } else if (message.startsWith('ERROR:')) {
      _updateStatus(
        _status.copyWith(
          state: TorConnectionState.error,
          errorMessage: message.substring(6),
        ),
      );
    } else if (message == 'STOPPED') {
      _updateStatus(const TorStatus(state: TorConnectionState.stopped));
    } else if (message.startsWith('CIRCUIT:')) {
      _updateStatus(
        _status.copyWith(
          circuitPath: message.substring(8),
          lastCircuitRefresh: DateTime.now(),
        ),
      );
    } else if (message.startsWith('PROBE:')) {
      final ready = message.substring(6) == 'READY';
      _updateStatus(
        _status.copyWith(
          propagationState:
              ready ? HsPropagationState.ready : HsPropagationState.checking,
        ),
      );
      if (_probeCompleter != null && !_probeCompleter!.isCompleted) {
        _probeCompleter!.complete(ready);
      }
    } else if (message.startsWith('PONG:')) {
      final online = message.substring(5) == 'ONLINE';
      if (_pingCompleter != null && !_pingCompleter!.isCompleted) {
        _pingCompleter!.complete(online);
      }
    } else if (message.startsWith('CIRCUIT_JSON:')) {
      try {
        final List<dynamic> json = jsonDecode(message.substring(13));
        final hops =
            json.map((h) {
              final map = h as Map<String, dynamic>;
              return CircuitHop(
                role: map['role'] ?? 'Unknown',
                name: map['name'] ?? 'Unknown',
                fingerprint: map['fingerprint'] ?? '',
                ip: map['ip'],
                countryCode: map['countryCode'],
              );
            }).toList();

        _updateStatus(_status.copyWith(lastCircuitRefresh: DateTime.now()));

        if (_circuitCompleter != null && !_circuitCompleter!.isCompleted) {
          _circuitCompleter!.complete(hops);
        }
      } catch (e) {
        debugPrint('WebTor: Error parsing circuit JSON: $e');
        if (_circuitCompleter != null && !_circuitCompleter!.isCompleted) {
          _circuitCompleter!.complete(null);
        }
      }
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
  Future<void> restart({
    bool snowflake = false,
    String excludeNodes = '',
  }) async {
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

  @override
  Future<String?> getCircuitPath() async {
    final hops = await getCircuitHops();
    if (hops == null || hops.isEmpty) return null;
    return hops.map((h) => '${h.flag} ${h.role}: ${h.name}').join(' → ');
  }

  @override
  Future<List<CircuitHop>?> getCircuitHops() async {
    if (_relayChannel == null ||
        _status.state != TorConnectionState.connected) {
      return null;
    }

    _circuitCompleter = Completer<List<CircuitHop>?>();
    _relayChannel!.sink.add('CMD:CIRCUIT');

    try {
      return await _circuitCompleter!.future.timeout(
        const Duration(seconds: 15),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> checkHsPropagation() async {
    if (_relayChannel == null || _onionAddress == null) return false;

    _probeCompleter = Completer<bool>();
    _relayChannel!.sink.add('CMD:PROBE $_onionAddress');

    try {
      return await _probeCompleter!.future.timeout(const Duration(seconds: 45));
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> waitForHsPropagation({
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final endTime = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(endTime)) {
      final ready = await checkHsPropagation();
      if (ready) return true;
      await Future.delayed(const Duration(seconds: 15));
    }
    _updateStatus(
      _status.copyWith(propagationState: HsPropagationState.timeout),
    );
    return false;
  }

  /// Check if a peer is online via the relay.
  Future<bool> isPeerOnline(String onionAddress) async {
    if (_relayChannel == null) return false;

    _pingCompleter = Completer<bool>();
    _relayChannel!.sink.add('CMD:PING $onionAddress');

    try {
      return await _pingCompleter!.future.timeout(const Duration(seconds: 40));
    } catch (_) {
      return false;
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

  Future<List<String>> _getAvailableRelayUrls() async {
    final urls = <String>[];

    // 1. User manual config
    final prefs = await SharedPreferences.getInstance();
    final manual = prefs.getString('relay_server_url');
    if (manual != null && manual.isNotEmpty) {
      urls.add(manual);
    }

    // 2. Auto-detect origin
    try {
      final loc = web.window.location;
      final protocol = loc.protocol == 'https:' ? 'wss' : 'ws';
      final auto = '$protocol://${loc.host}/ws';
      if (!urls.contains(auto)) urls.add(auto);
    } catch (_) {}

    // 3. Fallback to public
    for (final relay in _publicRelays) {
      if (!urls.contains(relay)) urls.add(relay);
    }

    return urls;
  }
}

TorServiceBase createTorService() => TorServiceWeb();
