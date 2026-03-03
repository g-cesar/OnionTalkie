import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../core/constants/app_constants.dart';
import '../models/tor_status.dart';
import 'tor_service_base.dart';

/// Native implementation of TorService using local Tor process.
class TorServiceNative extends TorServiceBase {
  Process? _torProcess;
  TorStatus _status = const TorStatus();
  final _statusController = StreamController<TorStatus>.broadcast();
  Timer? _bootstrapTimer;
  Timer? _bootstrapPollTimer;
  String? _dataDir;

  @override
  Stream<TorStatus> get statusStream => _statusController.stream;
  @override
  TorStatus get currentStatus => _status;

  // ─── Tor installation helpers ──────────────────────────────────────

  /// Check if a Tor binary is available on the device.
  @override
  Future<bool> isTorInstalled() async {
    return (await _findTorBinary()) != null;
  }

  /// Return platform-specific installation options for the user.
  @override
  List<TorInstallOption> getInstallOptions() {
    if (Platform.isAndroid) {
      return const [
        TorInstallOption(
          name: 'Orbot (consigliato)',
          description:
              'App ufficiale del Tor Project per Android. '
              'Fornisce un proxy Tor completo con VPN mode.',
          url: 'https://play.google.com/store/apps/details?id=org.torproject.android',
          iconType: IconType.store,
        ),
        TorInstallOption(
          name: 'Orbot — Guardian Project Repo',
          description:
              'Repo F-Droid del Guardian Project (contiene Orbot aggiornato).',
          url: 'https://guardianproject.info/fdroid/',
          iconType: IconType.download,
        ),
        TorInstallOption(
          name: 'Orbot — Download diretto',
          description:
              'Scarica l\'APK direttamente dal sito del Tor Project.',
          url: 'https://guardianproject.info/apps/org.torproject.android/',
          iconType: IconType.web,
        ),
      ];
    } else if (Platform.isIOS) {
      return const [
        TorInstallOption(
          name: 'Orbot (consigliato)',
          description:
              'App ufficiale del Tor Project per iOS. '
              'Fornisce un proxy Tor integrato nel sistema.',
          url: 'https://apps.apple.com/app/orbot/id1609461599',
          iconType: IconType.store,
        ),
        TorInstallOption(
          name: 'Onion Browser',
          description:
              'Browser Tor per iOS con proxy SOCKS5 integrato.',
          url: 'https://apps.apple.com/app/onion-browser/id519296448',
          iconType: IconType.store,
        ),
      ];
    } else {
      // macOS / Linux / desktop fallback
      return const [
        TorInstallOption(
          name: 'Homebrew (macOS)',
          description: 'Installa tramite terminale: brew install tor',
          command: 'brew install tor',
          iconType: IconType.terminal,
        ),
        TorInstallOption(
          name: 'Sito ufficiale',
          description: 'Scarica Tor dal sito del progetto.',
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

  /// Generate the torrc configuration file.
  Future<String> _generateTorrc({
    bool snowflake = false,
    String excludeNodes = '',
  }) async {
    final dataDir = await _getDataDir();
    final hiddenServiceDir = '$dataDir/hidden_service';

    final buffer = StringBuffer()
      ..writeln('SocksPort ${AppConstants.torSocksPort}')
      ..writeln('DataDirectory $dataDir')
      ..writeln('HiddenServiceDir $hiddenServiceDir')
      ..writeln('HiddenServicePort ${AppConstants.listenPort} 127.0.0.1:${AppConstants.listenPort}')
      ..writeln('Log notice file $dataDir/tor.log')
      ..writeln('Log notice stdout');

    if (excludeNodes.isNotEmpty) {
      buffer
        ..writeln('ExcludeNodes $excludeNodes')
        ..writeln('StrictNodes 1');
    }

    if (snowflake) {
      buffer
        ..writeln('UseBridges 1')
        ..writeln('ClientTransportPlugin snowflake exec /usr/bin/snowflake-client')
        ..writeln('Bridge snowflake 192.0.2.3:80 '
            '2B280B23E1107BB62ABFC40DDCC8824814F80A72 '
            'fingerprint=2B280B23E1107BB62ABFC40DDCC8824814F80A72 '
            'url=https://snowflake-broker.torproject.net.global.prod.fastly.net/ '
            'fronts=cdn.sstatic.net,www.phpmyadmin.net '
            'ice=stun:stun.l.google.com:19302,stun:stun.antisip.com:3478,'
            'stun:stun.bluesip.net:3478,stun:stun.dus.net:3478,'
            'stun:stun.epygi.com:3478,stun:stun.sonetel.com:3478,'
            'stun:stun.uls.co.za:3478,stun:stun.voipgate.com:3478 '
            'utls-imitate=hellorandomizedalpn');
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
  Future<void> start({
    bool snowflake = false,
    String excludeNodes = '',
  }) async {
    if (_status.state == TorConnectionState.connected ||
        _status.state == TorConnectionState.starting ||
        _status.state == TorConnectionState.bootstrapping) {
      return;
    }

    _updateStatus(_status.copyWith(
      state: TorConnectionState.starting,
      bootstrapProgress: 0,
      errorMessage: null,
    ));

    try {
      final torrcPath = await _generateTorrc(
        snowflake: snowflake,
        excludeNodes: excludeNodes,
      );

      // Find tor binary — on mobile it will be bundled in the app's native libs
      final torBinary = await _findTorBinary();
      if (torBinary == null) {
        _updateStatus(_status.copyWith(
          state: TorConnectionState.notInstalled,
          errorMessage: 'Client Tor non trovato. Installa Tor per continuare.',
        ));
        return;
      }

      _torProcess = await Process.start(torBinary, ['-f', torrcPath]);

      _updateStatus(_status.copyWith(state: TorConnectionState.bootstrapping));

      // Monitor Tor output for bootstrap progress (works on desktop where
      // stdout is available).
      _torProcess!.stdout.transform(utf8.decoder).listen(_parseTorOutput);
      _torProcess!.stderr.transform(utf8.decoder).listen(_parseTorOutput);

      // On Android, Tor may not send bootstrap messages to stdout even with
      // "Log notice stdout" in torrc. Poll the ControlPort as a fallback to
      // reliably track bootstrap progress on all platforms.
      _startBootstrapPolling();

      _torProcess!.exitCode.then((code) {
        if (_status.state != TorConnectionState.stopped) {
          _updateStatus(_status.copyWith(
            state: TorConnectionState.error,
            errorMessage: 'Tor process exited with code $code',
          ));
        }
      });

      // Set a bootstrap timeout
      final isFirstBoot = !await _hasConsensusCache();
      final timeout = isFirstBoot
          ? AppConstants.firstBootTimeout
          : AppConstants.connectingTimeout;

      _bootstrapTimer?.cancel();
      _bootstrapTimer = Timer(timeout, () {
        if (_status.state == TorConnectionState.bootstrapping) {
          _updateStatus(_status.copyWith(
            state: TorConnectionState.error,
            errorMessage: 'Tor bootstrap timed out after ${timeout.inSeconds}s',
          ));
          stop();
        }
      });
    } catch (e) {
      _updateStatus(_status.copyWith(
        state: TorConnectionState.error,
        errorMessage: 'Failed to start Tor: $e',
      ));
    }
  }

  /// Stop the Tor process.
  @override
  Future<void> stop() async {
    _bootstrapTimer?.cancel();
    _bootstrapPollTimer?.cancel();
    _torProcess?.kill();
    _torProcess = null;
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

  /// Get the current circuit path by querying the Tor ControlPort.
  @override
  Future<String?> getCircuitPath() async {
    try {
      final socket = await Socket.connect(
        '127.0.0.1',
        AppConstants.torControlPort,
      ).timeout(const Duration(seconds: 3));

      final responseBuffer = StringBuffer();
      final completer = Completer<String>();

      socket.listen(
        (data) {
          responseBuffer.write(utf8.decode(data));
          final content = responseBuffer.toString();
          if (content.contains('250 OK\r\n') &&
              content.contains('circuit-status=')) {
            if (!completer.isCompleted) completer.complete(content);
          }
        },
        onError: (e) {
          if (!completer.isCompleted) completer.completeError(e);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete(responseBuffer.toString());
        },
      );

      // Authenticate and request circuit status
      socket.write('AUTHENTICATE\r\nGETINFO circuit-status\r\n');
      await socket.flush();

      final response = await completer.future.timeout(
        const Duration(seconds: 5),
      );

      await socket.close();

      return _parseCircuitPath(response);
    } catch (e) {
      debugPrint('TorServiceNative: Failed to query circuit: $e');
      return null;
    }
  }

  /// Parse circuit-status response into readable format.
  String? _parseCircuitPath(String response) {
    final lines = response.split('\n');
    for (final line in lines) {
      if (line.contains('BUILT') && line.contains('\$')) {
        final relayPattern = RegExp(r'\$([A-F0-9]+)(?:~(\w+))?');
        final matches = relayPattern.allMatches(line).toList();
        if (matches.isEmpty) continue;

        final hops = <String>[];
        final roles = ['Guard', 'Relay', 'Rendezvous'];

        for (int i = 0; i < matches.length; i++) {
          final name = matches[i].group(2) ?? 'Unknown';
          final role = i < roles.length ? roles[i] : 'Hop ${i + 1}';
          hops.add('$role: $name');
        }
        return hops.join(' → ');
      }
    }
    return null;
  }

  /// Parse Tor output to track bootstrap progress.
  void _parseTorOutput(String output) {
    for (final line in output.split('\n')) {
      // Parse bootstrap progress: "Bootstrapped XX%"
      final bootstrapMatch = RegExp(r'Bootstrapped (\d+)%').firstMatch(line);
      if (bootstrapMatch != null) {
        final progress = int.parse(bootstrapMatch.group(1)!);
        _handleBootstrapProgress(progress);
      }

      // Check for errors
      if (line.contains('[err]') || line.contains('[warn]')) {
        debugPrint('Tor: $line');
      }
    }
  }

  /// Handle a bootstrap progress update from any source (stdout or poll).
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

  /// Read the onion address once Tor has bootstrapped.
  Future<void> _readOnionAddress() async {
    final address = await getOnionAddress();
    _updateStatus(_status.copyWith(
      state: TorConnectionState.connected,
      onionAddress: address,
    ));
  }

  /// Check if Tor has cached consensus data (not first boot).
  Future<bool> _hasConsensusCache() async {
    final dataDir = await _getDataDir();
    final cacheFile = File('$dataDir/cached-microdesc-consensus');
    return cacheFile.exists();
  }

  /// Platform channel per ottenere il percorso nativeLibraryDir su Android.
  static const _nativeChannel = MethodChannel('com.oniontalkie/native_info');

  /// Find the Tor binary on the system.
  Future<String?> _findTorBinary() async {
    // On Android, the Tor binary is bundled as libtor.so in jniLibs
    // and extracted to nativeLibraryDir at install time.
    if (Platform.isAndroid) {
      try {
        final nativeLibDir =
            await _nativeChannel.invokeMethod<String>('getNativeLibraryDir');
        if (nativeLibDir != null) {
          final bundledTor = File('$nativeLibDir/libtor.so');
          if (await bundledTor.exists()) {
            debugPrint('TorServiceNative: found bundled tor at ${bundledTor.path}');
            return bundledTor.path;
          }
        }
      } catch (e) {
        debugPrint('TorServiceNative: platform channel error: $e');
      }

      // Fallback: check legacy paths
      final appDir = await getApplicationDocumentsDirectory();
      final legacyPaths = [
        '${appDir.parent.path}/lib/libtor.so',
        '${appDir.path}/tor',
      ];
      for (final path in legacyPaths) {
        if (await File(path).exists()) return path;
      }

      return null;
    }

    // Desktop: check common system paths
    final paths = [
      '/usr/bin/tor',
      '/usr/local/bin/tor',
      '/opt/homebrew/bin/tor',
    ];

    for (final path in paths) {
      if (await File(path).exists()) return path;
    }

    // Try `which tor`
    try {
      final result = await Process.run('which', ['tor']);
      if (result.exitCode == 0) {
        return (result.stdout as String).trim();
      }
    } catch (_) {}

    return null;
  }

  void _updateStatus(TorStatus newStatus) {
    _status = newStatus;
    _statusController.add(newStatus);
  }

  @override
  void dispose() {
    _bootstrapTimer?.cancel();
    _bootstrapPollTimer?.cancel();
    _torProcess?.kill();
    _statusController.close();
  }
}

TorServiceBase createTorService() => TorServiceNative();
