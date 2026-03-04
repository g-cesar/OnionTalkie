/// Tor connection state.
enum TorConnectionState {
  stopped,
  notInstalled,
  starting,
  bootstrapping,
  connected,
  error,
}

/// Hidden-service propagation state (only meaningful once Tor is connected).
enum HsPropagationState {
  /// Not yet checked (Tor not connected, or check hasn't started).
  unknown,

  /// Actively probing whether the HS is reachable.
  checking,

  /// HS is confirmed reachable from the Tor network.
  ready,

  /// Probing timed out — HS may still propagate, but we gave up polling.
  timeout,
}

/// Represents the current Tor status.
class TorStatus {
  final TorConnectionState state;
  final int bootstrapProgress; // 0-100
  final String? onionAddress;
  final String? errorMessage;
  final String? circuitPath;
  final DateTime? lastCircuitRefresh;
  final bool snowflakeEnabled;
  final String? snowflakeBridgeInfo;

  /// Hidden-service propagation status (checked after Tor fully bootstraps).
  final HsPropagationState propagationState;

  const TorStatus({
    this.state = TorConnectionState.stopped,
    this.bootstrapProgress = 0,
    this.onionAddress,
    this.errorMessage,
    this.circuitPath,
    this.lastCircuitRefresh,
    this.snowflakeEnabled = false,
    this.snowflakeBridgeInfo,
    this.propagationState = HsPropagationState.unknown,
  });

  /// Tor is connected and an onion address is available (minimum requirement
  /// for calling/listening — propagation is a bonus indicator).
  bool get isReady =>
      state == TorConnectionState.connected && onionAddress != null;

  /// Tor is connected *and* the HS is confirmed reachable by external peers.
  bool get isFullyPropagated =>
      isReady && propagationState == HsPropagationState.ready;

  TorStatus copyWith({
    TorConnectionState? state,
    int? bootstrapProgress,
    String? onionAddress,
    String? errorMessage,
    String? circuitPath,
    DateTime? lastCircuitRefresh,
    bool? snowflakeEnabled,
    String? snowflakeBridgeInfo,
    HsPropagationState? propagationState,
  }) {
    return TorStatus(
      state: state ?? this.state,
      bootstrapProgress: bootstrapProgress ?? this.bootstrapProgress,
      onionAddress: onionAddress ?? this.onionAddress,
      errorMessage: errorMessage ?? this.errorMessage,
      circuitPath: circuitPath ?? this.circuitPath,
      lastCircuitRefresh: lastCircuitRefresh ?? this.lastCircuitRefresh,
      snowflakeEnabled: snowflakeEnabled ?? this.snowflakeEnabled,
      snowflakeBridgeInfo: snowflakeBridgeInfo ?? this.snowflakeBridgeInfo,
      propagationState: propagationState ?? this.propagationState,
    );
  }
}
