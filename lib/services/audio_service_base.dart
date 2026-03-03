import 'dart:async';
import 'dart:typed_data';

/// Audio recording and playback state.
enum AudioState {
  idle,
  recording,
  playing,
  streamingPlayback,
}

/// Abstract audio service interface (platform-agnostic).
abstract class AudioServiceBase {
  Stream<AudioState> get stateStream;
  AudioState get currentState;

  /// Stream of raw PCM16 chunks emitted during recording.
  /// Subscribe to this to get each chunk in real-time for streaming PTT.
  Stream<Uint8List> get audioChunkStream;

  /// Initialize the audio service.
  Future<void> init();

  /// Request microphone permission.
  Future<bool> requestPermission();

  /// Check if microphone permission is granted.
  Future<bool> hasPermission();

  /// Start recording audio (PTT pressed).
  Future<void> startRecording();

  /// Stop recording and return the raw PCM audio data.
  Future<Uint8List?> stopRecording();

  /// Play raw PCM audio data (single blob — used for tap-to-replay).
  Future<void> playAudio(Uint8List audioData);

  /// Start streaming playback session (for receiving real-time PTT audio).
  Future<void> startStreamingPlayback();

  /// Feed a chunk of PCM audio data into the streaming player.
  Future<void> feedAudioChunk(Uint8List chunk);

  /// Stop the streaming playback session.
  Future<void> stopStreamingPlayback();

  /// Run audio loopback test: record for a few seconds, then play back.
  Future<void> loopbackTest({int durationSeconds = 3});

  /// Stop any current playback.
  Future<void> stopPlayback();

  /// Clean up resources.
  Future<void> dispose();
}
