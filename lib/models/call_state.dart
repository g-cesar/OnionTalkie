/// State of an active call.
enum CallPhase { idle, connecting, ringing, active, ended, error }

/// Remote party PTT state.
enum RemotePttState { idle, recording }

/// Discrete step in the connection establishment process.
/// Used by [ConnectionStepsWidget] to show visual progress.
enum ConnectionStep {
  torCircuit,
  peerConnected,
  keyExchange,
  keyVerified,
  encrypted,
}

/// Represents the state of a call.
class CallState {
  final CallPhase phase;
  final String? remoteAddress;
  final String? localCipher;
  final String? remoteCipher;
  final bool isRecording;
  final RemotePttState remotePttState;
  final int sentBytes;
  final int receivedBytes;
  final int messageCount;
  final String? errorMessage;
  final DateTime? callStartTime;
  final bool isIncoming;
  final bool hmacEnabled;
  final bool pakeActive;
  final Set<ConnectionStep> completedSteps;

  /// Human-readable message shown during connection retry (e.g. "Attempt 2/8").
  final String? retryMessage;

  /// Current retry attempt number (0 = no retry in progress).
  final int retryAttempt;

  const CallState({
    this.phase = CallPhase.idle,
    this.remoteAddress,
    this.localCipher,
    this.remoteCipher,
    this.isRecording = false,
    this.remotePttState = RemotePttState.idle,
    this.sentBytes = 0,
    this.receivedBytes = 0,
    this.messageCount = 0,
    this.errorMessage,
    this.callStartTime,
    this.isIncoming = false,
    this.hmacEnabled = false,
    this.pakeActive = false,
    this.completedSteps = const {},
    this.retryMessage,
    this.retryAttempt = 0,
  });

  bool get ciphersMatch =>
      localCipher != null &&
      remoteCipher != null &&
      localCipher == remoteCipher;

  Duration? get callDuration {
    if (callStartTime == null) return null;
    return DateTime.now().difference(callStartTime!);
  }

  /// Return a copy with [step] added to [completedSteps].
  CallState addStep(ConnectionStep step) {
    return copyWith(completedSteps: {...completedSteps, step});
  }

  CallState copyWith({
    CallPhase? phase,
    String? remoteAddress,
    String? localCipher,
    String? remoteCipher,
    bool? isRecording,
    RemotePttState? remotePttState,
    int? sentBytes,
    int? receivedBytes,
    int? messageCount,
    String? errorMessage,
    DateTime? callStartTime,
    bool? isIncoming,
    bool? hmacEnabled,
    bool? pakeActive,
    Set<ConnectionStep>? completedSteps,
    String? retryMessage,
    bool clearRetryMessage = false,
    int? retryAttempt,
  }) {
    return CallState(
      phase: phase ?? this.phase,
      remoteAddress: remoteAddress ?? this.remoteAddress,
      localCipher: localCipher ?? this.localCipher,
      remoteCipher: remoteCipher ?? this.remoteCipher,
      isRecording: isRecording ?? this.isRecording,
      remotePttState: remotePttState ?? this.remotePttState,
      sentBytes: sentBytes ?? this.sentBytes,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      messageCount: messageCount ?? this.messageCount,
      errorMessage: errorMessage ?? this.errorMessage,
      callStartTime: callStartTime ?? this.callStartTime,
      isIncoming: isIncoming ?? this.isIncoming,
      hmacEnabled: hmacEnabled ?? this.hmacEnabled,
      pakeActive: pakeActive ?? this.pakeActive,
      completedSteps: completedSteps ?? this.completedSteps,
      retryMessage:
          clearRetryMessage ? null : (retryMessage ?? this.retryMessage),
      retryAttempt: retryAttempt ?? this.retryAttempt,
    );
  }
}
