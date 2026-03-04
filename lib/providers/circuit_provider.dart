import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tor_status.dart';
import '../services/circuit_service.dart';
import '../services/tor_service_base.dart';
import 'settings_provider.dart';
import 'tor_provider.dart';

/// Shared provider that auto-polls Tor circuit hops.
///
/// Reacts to [settingsProvider] (showCircuitPath, circuitRefreshSeconds)
/// and [torProvider] (connection state).  Both the home screen and the
/// call screen can `ref.watch(circuitHopsProvider)`.
class CircuitHopsNotifier extends StateNotifier<List<CircuitHop>?> {
  final TorServiceBase _torService;
  Timer? _timer;
  bool _enabled = false;
  int _intervalSeconds = 60;
  bool _torConnected = false;

  CircuitHopsNotifier(this._torService) : super(null);

  /// Reconfigure polling based on current settings / Tor state.
  void configure({
    required bool enabled,
    required int intervalSeconds,
    required bool torConnected,
  }) {
    final needsRestart =
        enabled != _enabled ||
        intervalSeconds != _intervalSeconds ||
        torConnected != _torConnected;

    _enabled = enabled;
    _intervalSeconds = intervalSeconds;
    _torConnected = torConnected;

    if (!needsRestart) return;

    _timer?.cancel();
    _timer = null;

    if (!_enabled || !_torConnected) {
      if (!_enabled) state = null;
      return;
    }

    // Immediate fetch + periodic
    _fetchCircuit();
    _timer = Timer.periodic(
      Duration(seconds: _intervalSeconds),
      (_) => _fetchCircuit(),
    );
  }

  /// Force a single refresh (e.g. pull-to-refresh).
  Future<void> refresh() => _fetchCircuit();

  Future<void> _fetchCircuit() async {
    try {
      final hops = await _torService.getCircuitHops();
      if (mounted && hops != null && hops.isNotEmpty) {
        state = hops;
      }
    } catch (e) {
      debugPrint('CircuitHopsNotifier: $e');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// Provides the current Tor circuit hops, auto-refreshing based on settings.
final circuitHopsProvider =
    StateNotifierProvider<CircuitHopsNotifier, List<CircuitHop>?>((ref) {
      final torService = ref.watch(torServiceProvider);
      final notifier = CircuitHopsNotifier(torService);

      void reconfigure() {
        final settings = ref.read(settingsProvider);
        final torStatus = ref.read(torProvider);
        notifier.configure(
          enabled: settings.showCircuitPath,
          intervalSeconds: settings.circuitRefreshSeconds,
          torConnected: torStatus.state == TorConnectionState.connected,
        );
      }

      ref.listen(settingsProvider, (_, __) => reconfigure());
      ref.listen(torProvider, (_, __) => reconfigure());

      // Initial configuration
      reconfigure();

      ref.onDispose(() => notifier.dispose());
      return notifier;
    });
