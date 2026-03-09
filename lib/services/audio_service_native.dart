import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/constants/app_constants.dart';
import 'audio_manager.dart';
import 'audio_service_base.dart';

/// Native implementation of AudioService using flutter_sound.
///
/// Recording: stream-based via `startRecorder(toStream:)` → raw PCM16.
/// Playback (single blob): wraps raw PCM16 in a WAV container and uses
/// `startPlayer(fromDataBuffer:, codec: Codec.pcm16WAV)`.
/// Streaming playback: uses `startPlayerFromStream()` + `feedFromStream()`
/// for real-time walkie-talkie reception.
class AudioServiceNative extends AudioServiceBase {
  FlutterSoundRecorder? _recorder;
  FlutterSoundPlayer? _player;

  final _stateController = StreamController<AudioState>.broadcast();
  AudioState _state = AudioState.idle;

  // Stream-based recording state.
  StreamController<Uint8List>? _recorderStreamController;
  StreamSubscription<Uint8List>? _recorderStreamSub; // tracks internal listener
  final List<Uint8List> _recordedChunks = [];

  // Broadcast stream for real-time chunk emission (walkie-talkie TX).
  final _audioChunkController = StreamController<Uint8List>.broadcast();

  // Defensive locks to prevent race conditions during rapid PTT toggling
  bool _isStartingRecording = false;
  bool _isStoppingRecording = false;

  // Streaming playback state (walkie-talkie RX).
  bool _streamingPlaybackActive = false;
  bool _isStartingPlayback = false;
  bool _isStoppingPlayback = false;
  int _playbackReqId = 0;

  final List<int> _playbackBuffer = [];
  static const int _minChunkSize = 8192; // Feed minimum 8KB at a time

  @override
  Stream<AudioState> get stateStream => _stateController.stream;
  @override
  AudioState get currentState => _state;
  @override
  Stream<Uint8List> get audioChunkStream => _audioChunkController.stream;

  /// Initialize the audio service.
  @override
  Future<void> init() async {
    _recorder = FlutterSoundRecorder();
    _player = FlutterSoundPlayer();

    // Initialize audio session for voice communication (routes to speaker)
    try {
      await initAudioSession();
    } catch (e) {
      debugPrint('AudioServiceNative: Failed to init audio session: $e');
    }

    await _recorder!.openRecorder();
    await _player!.openPlayer();

    // Ensure volume is at max.
    await _player!.setVolume(1.0);

    await _recorder!.setSubscriptionDuration(const Duration(milliseconds: 100));
  }

  /// Request microphone permission.
  @override
  Future<bool> requestPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  /// Check if microphone permission is granted.
  @override
  Future<bool> hasPermission() async {
    return (await Permission.microphone.status).isGranted;
  }

  int _recordingReqId = 0; // Defines current recording attempt

  /// Start recording audio (PTT pressed) — captures raw PCM16 to memory.
  @override
  Future<void> startRecording() async {
    if (_state == AudioState.recording ||
        _isStartingRecording ||
        _isStoppingRecording)
      return;
    _isStartingRecording = true;
    _recordingReqId++;
    final currentReqId = _recordingReqId;

    try {
      final hasPerms = await hasPermission();
      if (!hasPerms) {
        final granted = await requestPermission();
        if (!granted) {
          throw Exception('Microphone permission denied');
        }
      }

      // Check if a stop was requested while we were waiting for permissions
      if (currentReqId != _recordingReqId) {
        debugPrint(
          'AudioServiceNative: startRecording aborted (stop requested)',
        );
        return;
      }

      _recordedChunks.clear();
      _recorderStreamController = StreamController<Uint8List>();

      // Listen to the recorder stream: accumulate chunks AND emit them
      // on the broadcast stream for real-time PTT streaming.
      // Store the subscription so it can be cancelled when recording stops.
      _recorderStreamSub = _recorderStreamController!.stream.listen((data) {
        final chunk = Uint8List.fromList(data);
        _recordedChunks.add(chunk);
        // Emit to broadcast stream for live streaming to remote peer.
        if (!_audioChunkController.isClosed) {
          _audioChunkController.add(chunk);
        }
      });

      await _recorder!.startRecorder(
        toStream: _recorderStreamController!.sink,
        codec: Codec.pcm16,
        sampleRate: AppConstants.defaultSampleRate,
        numChannels: AppConstants.defaultChannels,
      );

      // Final check before committing state
      if (currentReqId != _recordingReqId) {
        debugPrint(
          'AudioServiceNative: startRecording aborted after startRecorder (stop requested)',
        );
        await _recorderStreamSub?.cancel();
        _recorderStreamSub = null;
        await _recorder!.stopRecorder();
        await _recorderStreamController?.close();
        _recorderStreamController = null;
        return;
      }

      _updateState(AudioState.recording);
      debugPrint('AudioServiceNative: Recording started (stream mode)');
    } catch (e) {
      debugPrint('AudioServiceNative: Failed to start recording: $e');
    } finally {
      _isStartingRecording = false;
    }
  }

  /// Stop recording and return the raw PCM audio data.
  @override
  Future<Uint8List?> stopRecording() async {
    _recordingReqId++; // Invalidate any pending start requests

    // If a start is in progress but hasn't updated the state yet, we still need to
    // let the start finish its initialization and naturally abort due to _recordingReqId changing.
    // But we don't return early just because _state is idle, we must wait and ensure cleanup.

    if (_isStoppingRecording) return null;
    _isStoppingRecording = true;

    // Optional short wait to allow a pending start to abort cleanly
    if (_isStartingRecording) {
      await Future.delayed(
        const Duration(milliseconds: 50),
      ); // Allow microtasks to settle
    }

    if (_state != AudioState.recording && _recorderStreamController == null) {
      // Nothing to stop
      _isStoppingRecording = false;
      return null;
    }

    try {
      // Cancel internal listener FIRST — critical to prevent leak
      await _recorderStreamSub?.cancel();
      _recorderStreamSub = null;

      await _recorder!.stopRecorder();
      await _recorderStreamController?.close();
      _recorderStreamController = null;
      _updateState(AudioState.idle);

      if (_recordedChunks.isEmpty) {
        debugPrint('AudioServiceNative: No audio data recorded');
        return null;
      }

      // Merge all chunks into a single Uint8List.
      int totalLength = 0;
      for (final chunk in _recordedChunks) {
        totalLength += chunk.length;
      }
      final result = Uint8List(totalLength);
      int offset = 0;
      for (final chunk in _recordedChunks) {
        result.setRange(offset, offset + chunk.length, chunk);
        offset += chunk.length;
      }
      _recordedChunks.clear();

      debugPrint('AudioServiceNative: Recorded $totalLength bytes');
      return result;
    } finally {
      _isStoppingRecording = false;
    }
  }

  /// Play raw PCM audio data.
  ///
  /// Wraps the raw PCM16 bytes in a proper 44-byte WAV header and plays
  /// via `startPlayer(fromDataBuffer:)`.  This avoids the unreliable
  /// `startPlayerFromStream` + `feedUint8FromStream` low-level API which
  /// fails silently on many Android devices.
  @override
  Future<void> playAudio(Uint8List audioData) async {
    if (audioData.isEmpty) {
      debugPrint('AudioServiceNative: playAudio called with empty data');
      return;
    }

    if (_state == AudioState.playing) {
      try {
        await _player!.stopPlayer();
      } catch (_) {}
    }

    _updateState(AudioState.playing);

    try {
      // Wrap raw PCM16 in a WAV container.
      final wavData = _buildWav(
        audioData,
        AppConstants.defaultSampleRate,
        AppConstants.defaultChannels,
      );

      // --- Diagnostic: check if data is all zeros or has some content ---
      int nonZero = 0;
      int maxVal = 0;
      for (int i = 0; i < audioData.length - 1; i += 2) {
        final sample = audioData[i] | (audioData[i + 1] << 8);
        if (sample != 0) nonZero++;
        if (sample > maxVal) maxVal = sample;
      }
      final totalSamples = audioData.length ~/ 2;
      debugPrint(
        'AudioServiceNative: Playing ${audioData.length} PCM bytes '
        '(${wavData.length} WAV bytes) — '
        'non-zero samples: $nonZero/$totalSamples, peak: $maxVal',
      );

      final completer = Completer<void>();

      await _player!.startPlayer(
        fromDataBuffer: wavData,
        codec: Codec.pcm16WAV,
        sampleRate: AppConstants.defaultSampleRate,
        numChannels: AppConstants.defaultChannels,
        whenFinished: () {
          if (!completer.isCompleted) completer.complete();
        },
      );

      // Ensure volume is up (some devices reset it).
      await _player!.setVolume(1.0);

      // Estimate playback duration for a safety timeout.
      final durationMs =
          (audioData.length * 1000) ~/
          (AppConstants.defaultSampleRate * 2 * AppConstants.defaultChannels);
      final timeout = Duration(milliseconds: durationMs + 3000);

      // Wait for the whenFinished callback (or timeout).
      await completer.future.timeout(
        timeout,
        onTimeout: () {
          debugPrint('AudioServiceNative: playback timeout — stopping');
        },
      );

      try {
        await _player!.stopPlayer();
      } catch (_) {}
      _updateState(AudioState.idle);

      debugPrint('AudioServiceNative: Playback complete (${durationMs}ms)');
    } catch (e) {
      debugPrint('AudioServiceNative: Playback error: $e');
      try {
        await _player!.stopPlayer();
      } catch (_) {}
      _updateState(AudioState.idle);
    }
  }

  /// Build a complete WAV file (RIFF header + PCM data) from raw PCM16 bytes.
  static Uint8List _buildWav(
    Uint8List pcmData,
    int sampleRate,
    int numChannels,
  ) {
    final byteRate = sampleRate * numChannels * 2; // 16-bit = 2 bytes/sample
    final blockAlign = numChannels * 2;
    final dataSize = pcmData.length;

    final header = ByteData(44);
    // "RIFF"
    header.setUint8(0, 0x52);
    header.setUint8(1, 0x49);
    header.setUint8(2, 0x46);
    header.setUint8(3, 0x46);
    header.setUint32(4, 36 + dataSize, Endian.little); // file size - 8
    // "WAVE"
    header.setUint8(8, 0x57);
    header.setUint8(9, 0x41);
    header.setUint8(10, 0x56);
    header.setUint8(11, 0x45);
    // "fmt " chunk
    header.setUint8(12, 0x66);
    header.setUint8(13, 0x6D);
    header.setUint8(14, 0x74);
    header.setUint8(15, 0x20);
    header.setUint32(16, 16, Endian.little); // chunk size
    header.setUint16(20, 1, Endian.little); // PCM format
    header.setUint16(22, numChannels, Endian.little); // channels
    header.setUint32(24, sampleRate, Endian.little); // sample rate
    header.setUint32(28, byteRate, Endian.little); // byte rate
    header.setUint16(32, blockAlign, Endian.little); // block align
    header.setUint16(34, 16, Endian.little); // bits per sample
    // "data" chunk
    header.setUint8(36, 0x64);
    header.setUint8(37, 0x61);
    header.setUint8(38, 0x74);
    header.setUint8(39, 0x61);
    header.setUint32(40, dataSize, Endian.little); // data size

    // Combine header + PCM data.
    final wav = Uint8List(44 + dataSize);
    wav.setRange(0, 44, header.buffer.asUint8List());
    wav.setRange(44, 44 + dataSize, pcmData);
    return wav;
  }

  /// Start streaming playback (walkie-talkie RX mode).
  ///
  /// Opens the player in streaming mode so that incoming PCM16 chunks
  /// can be fed via [feedAudioChunk].
  @override
  Future<void> startStreamingPlayback() async {
    if (_streamingPlaybackActive || _isStartingPlayback || _isStoppingPlayback)
      return;
    _isStartingPlayback = true;
    _playbackReqId++;
    final currentReqId = _playbackReqId;

    // Stop any single-blob playback if running.
    if (_state == AudioState.playing) {
      try {
        await _player!.stopPlayer();
      } catch (_) {}
    }

    try {
      await _player!.startPlayerFromStream(
        codec: Codec.pcm16,
        sampleRate: AppConstants.defaultSampleRate,
        numChannels: AppConstants.defaultChannels,
        interleaved: true,
        bufferSize: 16384,
      );

      // Check if another request or stop happened during init
      if (currentReqId != _playbackReqId) {
        debugPrint(
          'AudioServiceNative: startStreamingPlayback aborted (stop requested)',
        );
        await _player!.stopPlayer();
        return;
      }

      await _player!.setVolume(1.0);
      _streamingPlaybackActive = true;
      _playbackBuffer.clear();
      _updateState(AudioState.streamingPlayback);

      debugPrint(
        'AudioServiceNative: Streaming playback started '
        '(sampleRate=${AppConstants.defaultSampleRate}, '
        'channels=${AppConstants.defaultChannels})',
      );
    } catch (e) {
      debugPrint('AudioServiceNative: Failed to start streaming playback: $e');
      _streamingPlaybackActive = false;
      if (_state == AudioState.streamingPlayback) {
        _updateState(AudioState.idle);
      }
    } finally {
      _isStartingPlayback = false;
    }
  }

  /// Feed a chunk of PCM16 data to the streaming player.
  @override
  Future<void> feedAudioChunk(Uint8List chunk) async {
    if (!_streamingPlaybackActive) return;
    if (chunk.isEmpty) return;

    _playbackBuffer.addAll(chunk);

    // Only feed the player when we have enough data
    if (_playbackBuffer.length < _minChunkSize) {
      return;
    }

    try {
      // Must be a multiple of 2
      int feedSize = _playbackBuffer.length;
      if (feedSize % 2 != 0) feedSize -= 1;

      final feedChunk = Uint8List.fromList(
        _playbackBuffer.sublist(0, feedSize),
      );
      _playbackBuffer.removeRange(0, feedSize);

      // On some platforms, isPlaying may be false intermittently for streams.
      // We rely on startPlayerFromStream having been called.
      await _player!.feedUint8FromStream(feedChunk);
    } catch (e) {
      debugPrint('AudioServiceNative: feedAudioChunk error: $e');
    }
  }

  /// Stop the streaming playback session.
  @override
  Future<void> stopStreamingPlayback() async {
    _playbackReqId++; // Invalidate any pending startups

    if (!_streamingPlaybackActive &&
        !_isStartingPlayback &&
        _playbackBuffer.isEmpty)
      return;
    if (_isStoppingPlayback) return;
    _isStoppingPlayback = true;

    if (_isStartingPlayback) {
      await Future.delayed(const Duration(milliseconds: 50));
    }

    // Flush any remaining buffered data
    if (_playbackBuffer.isNotEmpty && _streamingPlaybackActive) {
      try {
        int feedSize = _playbackBuffer.length;
        if (feedSize % 2 != 0) feedSize -= 1;
        if (feedSize > 0) {
          final feedChunk = Uint8List.fromList(
            _playbackBuffer.sublist(0, feedSize),
          );
          await _player!.feedUint8FromStream(feedChunk);
        }
      } catch (_) {}
    }

    _streamingPlaybackActive = false;
    _playbackBuffer.clear();

    try {
      await _player!.stopPlayer();
    } catch (_) {}

    _updateState(AudioState.idle);
    debugPrint('AudioServiceNative: Streaming playback stopped');
    _isStoppingPlayback = false;
  }

  /// Run audio loopback test: record for a few seconds, then play back.
  @override
  Future<void> loopbackTest({int durationSeconds = 3}) async {
    debugPrint('AudioServiceNative: Starting loopback test...');

    await startRecording();
    await Future.delayed(Duration(seconds: durationSeconds));
    final data = await stopRecording();

    if (data != null && data.isNotEmpty) {
      debugPrint('AudioServiceNative: Playing back ${data.length} bytes');
      await playAudio(data);
    } else {
      debugPrint('AudioServiceNative: No audio data recorded');
    }
  }

  /// Stop any current playback.
  @override
  Future<void> stopPlayback() async {
    if (_state == AudioState.playing) {
      await _player!.stopPlayer();
      _updateState(AudioState.idle);
    }
  }

  void _updateState(AudioState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  /// Clean up resources.
  @override
  Future<void> dispose() async {
    await _recorderStreamController?.close();
    await _recorder?.closeRecorder();
    await _player?.closePlayer();
    _recorder = null;
    _player = null;
    _stateController.close();
    _audioChunkController.close();
  }
}

AudioServiceBase createAudioService() => AudioServiceNative();
