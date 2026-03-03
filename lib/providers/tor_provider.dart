import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tor_status.dart';
import '../services/tor_service.dart';


/// Provider for the TorService instance.
final torServiceProvider = Provider<TorServiceBase>((ref) {
  final service = createTorService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// StateNotifier for Tor status.
class TorNotifier extends StateNotifier<TorStatus> {
  final TorServiceBase _torService;
  StreamSubscription? _subscription;
  Timer? _circuitTimer;

  TorNotifier(this._torService) : super(const TorStatus()) {
    _subscription = _torService.statusStream.listen((status) {
      final previousState = state.state;
      state = status;

      // Start circuit path refresh timer when connected
      if (status.state == TorConnectionState.connected &&
          previousState != TorConnectionState.connected) {
        _startCircuitRefreshTimer();
      } else if (status.state != TorConnectionState.connected) {
        _circuitTimer?.cancel();
      }
    });
  }

  TorServiceBase get service => _torService;

  /// Check if Tor is installed and update state accordingly.
  Future<bool> checkTorInstalled() async {
    final installed = await _torService.isTorInstalled();
    if (!installed) {
      state = state.copyWith(
        state: TorConnectionState.notInstalled,
        errorMessage: 'Tor client not found.',
      );
    }
    return installed;
  }

  Future<void> start({bool snowflake = false, String excludeNodes = ''}) async {
    await _torService.start(snowflake: snowflake, excludeNodes: excludeNodes);
  }

  Future<void> stop() async {
    _circuitTimer?.cancel();
    await _torService.stop();
  }

  Future<void> restart({bool snowflake = false, String excludeNodes = ''}) async {
    await _torService.restart(snowflake: snowflake, excludeNodes: excludeNodes);
  }

  Future<void> rotateOnionAddress() async {
    await _torService.rotateOnionAddress();
  }

  Future<String?> getOnionAddress() async {
    return _torService.getOnionAddress();
  }

  /// Query the current Tor circuit path.
  Future<String?> getCircuitPath() async {
    try {
      final path = await _torService.getCircuitPath();
      if (path != null) {
        state = state.copyWith(
          circuitPath: path,
          lastCircuitRefresh: DateTime.now(),
        );
      }
      return path;
    } catch (e) {
      debugPrint('TorNotifier: Failed to query circuit: $e');
      return null;
    }
  }

  /// Start periodic circuit path refresh (every 60 seconds).
  void _startCircuitRefreshTimer() {
    _circuitTimer?.cancel();
    // Initial query
    getCircuitPath();
    _circuitTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => getCircuitPath(),
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _circuitTimer?.cancel();
    super.dispose();
  }
}

final torProvider = StateNotifierProvider<TorNotifier, TorStatus>((ref) {
  final service = ref.watch(torServiceProvider);
  return TorNotifier(service);
});


