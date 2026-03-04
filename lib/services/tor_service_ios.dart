import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../core/constants/app_constants.dart';
import '../models/tor_status.dart';
import 'hidden_service_probe.dart';
import 'tor_service_base.dart';
import 'circuit_service.dart';

/// iOS implementation of TorService using Tor.framework via MethodChannel.
class TorServiceIos extends TorServiceBase {
  TorStatus _status = const TorStatus();
  final _statusController = StreamController<TorStatus>.broadcast();
  Timer? _bootstrapTimer;
  Timer? _bootstrapPollTimer;
  Timer? _propagationTimer;
  int _propagationAttempt = 0;
  String? _dataDir;

  @override
  Stream<TorStatus> get statusStream => _statusController.stream;
  @override
  TorStatus get currentStatus => _status;

  // ─── Tor installation helpers ──────────────────────────────────────

  /// Tor.framework is bundled statically on iOS, so it is always installed.
  @override
  Future<bool> isTorInstalled() async => true;

  /// Return platform-specific installation options for the user.
  @override
  List<TorInstallOption> getInstallOptions() {
    if (Platform.isAndroid) {
      return const [
        TorInstallOption(
          name: 'Orbot (recommended)',
          description:
              'Official Tor Project app for Android. '
              'Provides a complete Tor proxy with VPN mode.',
          url:
              'https://play.google.com/store/apps/details?id=org.torproject.android',
          iconType: IconType.store,
        ),
        TorInstallOption(
          name: 'Orbot — Guardian Project Repo',
          description:
              'Guardian Project F-Droid repo (contains updated Orbot).',
          url: 'https://guardianproject.info/fdroid/',
          iconType: IconType.download,
        ),
        TorInstallOption(
          name: 'Orbot — Direct download',
          description:
              'Download the APK directly from the Tor Project website.',
          url: 'https://guardianproject.info/apps/org.torproject.android/',
          iconType: IconType.web,
        ),
      ];
    } else if (Platform.isIOS) {
      return const [
        TorInstallOption(
          name: 'Orbot (recommended)',
          description:
              'Official Tor Project app for iOS. '
              'Provides a system-integrated Tor proxy.',
          url: 'https://apps.apple.com/app/orbot/id1609461599',
          iconType: IconType.store,
        ),
        TorInstallOption(
          name: 'Onion Browser',
          description: 'Tor browser for iOS with built-in SOCKS5 proxy.',
          url: 'https://apps.apple.com/app/onion-browser/id519296448',
          iconType: IconType.store,
        ),
      ];
    } else {
      // macOS / Linux / desktop fallback
      return const [
        TorInstallOption(
          name: 'Homebrew (macOS)',
          description: 'Install via terminal: brew install tor',
          command: 'brew install tor',
          iconType: IconType.terminal,
        ),
        TorInstallOption(
          name: 'Official site',
          description: 'Download Tor from the project website.',
          url: 'https://www.torproject.org/download/',
          iconType: IconType.web,
        ),
      ];
    }
  }

  /// Initialize the Tor data directory.
  Future<String> _getDataDir() async {
    if (_dataDir != null) return _dataDir!;
    final appDir = await getApplicationDocumentsDirectory();
    _dataDir = '${appDir.path}/terminalphone/${AppConstants.torDataDir}';
    final dir = Directory(_dataDir!);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return _dataDir!;
  }

  /// Extract a Flutter asset to [destPath] if the file does not already exist.
  Future<void> _extractAssetIfMissing(String assetKey, String destPath) async {
    final dest = File(destPath);
    if (await dest.exists()) return;
    try {
      final data = await rootBundle.load(assetKey);
      await dest.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      debugPrint('TorServiceNative: extracted $assetKey → $destPath');
    } catch (e) {
      debugPrint('TorServiceNative: failed to extract $assetKey: $e');
    }
  }

  /// Generate the torrc configuration file.
  Future<String> _generateTorrc({
    bool snowflake = false,
    String excludeNodes = '',
  }) async {
    final dataDir = await _getDataDir();
    final hiddenServiceDir = '$dataDir/hidden_service';

    // Extract GeoIP database files from Flutter assets (if not already present)
    final geoipPath = '$dataDir/geoip';
    final geoip6Path = '$dataDir/geoip6';
    await _extractAssetIfMissing('assets/tor/geoip', geoipPath);
    await _extractAssetIfMissing('assets/tor/geoip6', geoip6Path);

    final buffer =
        StringBuffer()
          ..writeln('SocksPort ${AppConstants.torSocksPort}')
          ..writeln('DataDirectory $dataDir')
          ..writeln('HiddenServiceDir $hiddenServiceDir')
          ..writeln(
            'HiddenServicePort ${AppConstants.listenPort} 127.0.0.1:${AppConstants.listenPort}',
          )
          ..writeln('Log notice file $dataDir/tor.log')
          ..writeln('Log notice stdout')
          ..writeln('GeoIPFile $geoipPath')
          ..writeln('GeoIPv6File $geoip6Path');

    if (excludeNodes.isNotEmpty) {
      buffer
        ..writeln('ExcludeNodes $excludeNodes')
        ..writeln('StrictNodes 1');
    }

    if (snowflake) {
      buffer
        ..writeln('UseBridges 1')
        ..writeln(
          'ClientTransportPlugin snowflake exec /usr/bin/snowflake-client',
        )
        ..writeln(
          'Bridge snowflake 192.0.2.3:80 '
          '2B280B23E1107BB62ABFC40DDCC8824814F80A72 '
          'fingerprint=2B280B23E1107BB62ABFC40DDCC8824814F80A72 '
          'url=https://snowflake-broker.torproject.net.global.prod.fastly.net/ '
          'fronts=cdn.sstatic.net,www.phpmyadmin.net '
          'ice=stun:stun.l.google.com:19302,stun:stun.antisip.com:3478,'
          'stun:stun.bluesip.net:3478,stun:stun.dus.net:3478,'
          'stun:stun.epygi.com:3478,stun:stun.sonetel.com:3478,'
          'stun:stun.uls.co.za:3478,stun:stun.voipgate.com:3478 '
          'utls-imitate=hellorandomizedalpn',
        );
    }

    // Enable ControlPort for circuit info queries
    buffer.writeln('ControlPort ${AppConstants.torControlPort}');
    buffer.writeln('CookieAuthentication 0');

    final torrcPath = '$dataDir/torrc';
    final file = File(torrcPath);
    await file.writeAsString(buffer.toString());
    return torrcPath;
  }

  /// Start the Tor process.
  @override
  Future<void> start({bool snowflake = false, String excludeNodes = ''}) async {
    if (_status.state == TorConnectionState.connected ||
        _status.state == TorConnectionState.starting ||
        _status.state == TorConnectionState.bootstrapping) {
      return;
    }

    _updateStatus(
      _status.copyWith(
        state: TorConnectionState.starting,
        bootstrapProgress: 0,
        errorMessage: null,
      ),
    );

    try {
      final torrcPath = await _generateTorrc(
        snowflake: snowflake,
        excludeNodes: excludeNodes,
      );

      // Invoke native iOS MethodChannel to start Tor.framework thread
      const channel = MethodChannel('onion_talkie/tor_ios');
      await channel.invokeMethod('start', {'torrcPath': torrcPath});

      _updateStatus(_status.copyWith(state: TorConnectionState.bootstrapping));

      // On iOS, Tor does not output to stdout in a way Dart can read.
      // We rely completely on polling the ControlPort to track bootstrap progress.
      _startBootstrapPolling();

      // No native process exit code to listen to on iOS, TorThread is managed by the OS.

      // Set a bootstrap timeout
      final isFirstBoot = !await _hasConsensusCache();
      final timeout =
          isFirstBoot
              ? AppConstants.firstBootTimeout
              : AppConstants.connectingTimeout;

      _bootstrapTimer?.cancel();
      _bootstrapTimer = Timer(timeout, () {
        if (_status.state == TorConnectionState.bootstrapping) {
          _updateStatus(
            _status.copyWith(
              state: TorConnectionState.error,
              errorMessage:
                  'Tor bootstrap timed out after ${timeout.inSeconds}s',
            ),
          );
          stop();
        }
      });
    } catch (e) {
      _updateStatus(
        _status.copyWith(
          state: TorConnectionState.error,
          errorMessage: 'Failed to start Tor: $e',
        ),
      );
    }
  }

  @override
  Future<void> stop() async {
    _bootstrapTimer?.cancel();
    _bootstrapPollTimer?.cancel();
    _propagationTimer?.cancel();

    try {
      const channel = MethodChannel('onion_talkie/tor_ios');
      await channel.invokeMethod('stop');
    } catch (_) {}

    _updateStatus(const TorStatus(state: TorConnectionState.stopped));
  }

  /// Restart Tor.
  @override
  Future<void> restart({
    bool snowflake = false,
    String excludeNodes = '',
  }) async {
    await stop();
    await Future.delayed(const Duration(seconds: 1));
    await start(snowflake: snowflake, excludeNodes: excludeNodes);
  }

  /// Rotate the onion address by deleting the hidden service keys.
  @override
  Future<void> rotateOnionAddress() async {
    final wasRunning = _status.state == TorConnectionState.connected;
    if (wasRunning) await stop();

    final dataDir = await _getDataDir();
    final hsDir = Directory('$dataDir/hidden_service');
    if (await hsDir.exists()) {
      await hsDir.delete(recursive: true);
    }

    if (wasRunning) await start();
  }

  /// Get the current onion address.
  @override
  Future<String?> getOnionAddress() async {
    final dataDir = await _getDataDir();
    final hostnameFile = File('$dataDir/hidden_service/hostname');
    if (await hostnameFile.exists()) {
      final address = await hostnameFile.readAsString();
      return address.trim();
    }
    return null;
  }

  @override
  Future<String?> getCircuitPath() => CircuitService.getCircuitPath();

  @override
  Future<List<CircuitHop>?> getCircuitHops() => CircuitService.getCircuitHops();

  /// Handle a bootstrap progress update from any source (poll).
  void _handleBootstrapProgress(int progress) {
    if (progress <= _status.bootstrapProgress) return; // avoid regressions
    _updateStatus(_status.copyWith(bootstrapProgress: progress));

    if (progress == 100) {
      _bootstrapTimer?.cancel();
      _bootstrapPollTimer?.cancel();
      _readOnionAddress();
    }
  }

  /// Poll the Tor ControlPort to track bootstrap progress.
  /// This is the reliable method on Android where stdout may not
  /// deliver log lines from the Tor binary.
  void _startBootstrapPolling() {
    _bootstrapPollTimer?.cancel();
    _bootstrapPollTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _pollBootstrapStatus(),
    );
  }

  /// Query the ControlPort for current bootstrap status.
  Future<void> _pollBootstrapStatus() async {
    if (_status.state == TorConnectionState.connected ||
        _status.state == TorConnectionState.stopped ||
        _status.state == TorConnectionState.error) {
      _bootstrapPollTimer?.cancel();
      return;
    }

    try {
      final socket = await Socket.connect(
        '127.0.0.1',
        AppConstants.torControlPort,
      ).timeout(const Duration(seconds: 2));

      final responseBuffer = StringBuffer();
      final completer = Completer<String>();

      socket.listen(
        (data) {
          responseBuffer.write(utf8.decode(data));
          final content = responseBuffer.toString();
          // Wait until we get the response to GETINFO
          if (content.contains('250 OK') &&
              content.contains('status/bootstrap-phase')) {
            if (!completer.isCompleted) completer.complete(content);
          }
          // Also handle if Tor rejects our command (unlikely but safe)
          if (content.contains('5') && content.contains('Unrecognized')) {
            if (!completer.isCompleted) completer.complete(content);
          }
        },
        onError: (e) {
          if (!completer.isCompleted) completer.completeError(e);
        },
        onDone: () {
          if (!completer.isCompleted) {
            completer.complete(responseBuffer.toString());
          }
        },
      );

      socket.write('AUTHENTICATE\r\nGETINFO status/bootstrap-phase\r\n');
      await socket.flush();

      final response = await completer.future.timeout(
        const Duration(seconds: 3),
      );

      await socket.close();

      // Parse: 250-status/bootstrap-phase=NOTICE BOOTSTRAP PROGRESS=XX ...
      final match = RegExp(r'PROGRESS=(\d+)').firstMatch(response);
      if (match != null) {
        final progress = int.parse(match.group(1)!);
        _handleBootstrapProgress(progress);
      }
    } catch (_) {
      // ControlPort not yet ready — ignore and retry next tick
    }
  }

  /// Read the onion address once Tor has bootstrapped and kick off
  /// hidden-service propagation polling.
  Future<void> _readOnionAddress() async {
    final address = await getOnionAddress();
    _updateStatus(
      _status.copyWith(
        state: TorConnectionState.connected,
        onionAddress: address,
        propagationState: HsPropagationState.unknown,
      ),
    );

    if (address != null) {
      _startPropagationPolling(address);
    }
  }

  /// Start polling the Tor network to confirm the HS is reachable.
  void _startPropagationPolling(String onionAddress) {
    _propagationTimer?.cancel();
    _propagationAttempt = 0;

    // Mark as "checking" immediately
    _updateStatus(
      _status.copyWith(propagationState: HsPropagationState.checking),
    );

    // First check after 10 s (HS rarely propagates faster)
    _propagationTimer = Timer(const Duration(seconds: 10), () {
      _doPropagationCheck(onionAddress);
    });
  }

  /// Single propagation probe + schedule next attempt.
  Future<void> _doPropagationCheck(String onionAddress) async {
    // Stop if Tor disconnected in the meantime
    if (_status.state != TorConnectionState.connected) return;

    _propagationAttempt++;
    debugPrint(
      'TorServiceNative: propagation probe #$_propagationAttempt for $onionAddress',
    );

    final reachable = await HiddenServiceProbe.checkPropagated(onionAddress);

    if (reachable) {
      _propagationTimer?.cancel();
      _updateStatus(
        _status.copyWith(propagationState: HsPropagationState.ready),
      );
      debugPrint('TorServiceNative: hidden service propagated ✓');
      return;
    }

    // Give up after ~5 minutes (20 attempts × 15 s)
    if (_propagationAttempt >= 20) {
      _propagationTimer?.cancel();
      _updateStatus(
        _status.copyWith(propagationState: HsPropagationState.timeout),
      );
      debugPrint('TorServiceNative: propagation polling timed out');
      return;
    }

    // Retry in 15 s
    _propagationTimer = Timer(const Duration(seconds: 15), () {
      _doPropagationCheck(onionAddress);
    });
  }

  /// Public one-shot propagation check (used by TorProvider / UI).
  @override
  Future<bool> checkHsPropagation() async {
    final addr = _status.onionAddress;
    if (addr == null || _status.state != TorConnectionState.connected) {
      return false;
    }
    final reachable = await HiddenServiceProbe.checkPropagated(addr);
    if (reachable && _status.propagationState != HsPropagationState.ready) {
      _propagationTimer?.cancel();
      _updateStatus(
        _status.copyWith(propagationState: HsPropagationState.ready),
      );
    }
    return reachable;
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

  @override
  Future<bool> isPeerOnline(String onionAddress) async {
    return HiddenServiceProbe.checkPropagated(
      onionAddress,
      timeout: const Duration(seconds: 25),
    );
  }

  /// Check if Tor has cached consensus data (not first boot).
  Future<bool> _hasConsensusCache() async {
    final dataDir = await _getDataDir();
    final cacheFile = File('$dataDir/cached-microdesc-consensus');
    return cacheFile.exists();
  }

  void _updateStatus(TorStatus newStatus) {
    _status = newStatus;
    _statusController.add(newStatus);
  }

  @override
  void dispose() {
    _bootstrapTimer?.cancel();
    _bootstrapPollTimer?.cancel();
    _propagationTimer?.cancel();
    try {
      const channel = MethodChannel('onion_talkie/tor_ios');
      channel.invokeMethod('stop');
    } catch (_) {}
    _statusController.close();
  }
}

TorServiceBase createTorService() => TorServiceIos();
