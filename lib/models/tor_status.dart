/// Tor connection state.
enum TorConnectionState {
  stopped,
  notInstalled,
  starting,
  bootstrapping,
  connected,
  error,
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

  const TorStatus({
    this.state = TorConnectionState.stopped,
    this.bootstrapProgress = 0,
    this.onionAddress,
    this.errorMessage,
    this.circuitPath,
    this.lastCircuitRefresh,
    this.snowflakeEnabled = false,
    this.snowflakeBridgeInfo,
  });

  bool get isReady => state == TorConnectionState.connected && onionAddress != null;

  TorStatus copyWith({
    TorConnectionState? state,
    int? bootstrapProgress,
    String? onionAddress,
    String? errorMessage,
    String? circuitPath,
    DateTime? lastCircuitRefresh,
    bool? snowflakeEnabled,
    String? snowflakeBridgeInfo,
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
    );
  }
}
