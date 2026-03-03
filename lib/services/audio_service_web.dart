import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import '../core/constants/app_constants.dart';
import 'audio_service_base.dart';

/// Web implementation of AudioService using browser MediaRecorder + AudioContext.
class AudioServiceWeb extends AudioServiceBase {
  final _stateController = StreamController<AudioState>.broadcast();
  AudioState _state = AudioState.idle;

  web.MediaStream? _mediaStream;
  web.AudioContext? _audioContext;
  web.MediaStreamAudioSourceNode? _sourceNode;
  web.ScriptProcessorNode? _processorNode;

  final List<Float32List> _recordedChunks = [];
  final int _sampleRate = AppConstants.defaultSampleRate;

  // Broadcast stream for real-time chunk emission (walkie-talkie TX).
  final _audioChunkController = StreamController<Uint8List>.broadcast();

  // Streaming playback state (walkie-talkie RX).
  web.AudioContext? _streamPlaybackCtx;
  double _nextPlayTime = 0;
  bool _streamingPlaybackActive = false;

  @override
  Stream<AudioState> get stateStream => _stateController.stream;
  @override
  AudioState get currentState => _state;
  @override
  Stream<Uint8List> get audioChunkStream => _audioChunkController.stream;

  @override
  Future<void> init() async {
    // AudioContext is created lazily on first use (browser policy).
    debugPrint('AudioServiceWeb: initialized');
  }

  @override
  Future<bool> requestPermission() async {
    try {
      final constraints = web.MediaStreamConstraints(
        audio: true.toJS,
        video: false.toJS,
      );
      _mediaStream = await web.window.navigator.mediaDevices
          .getUserMedia(constraints)
          .toDart;
      // Stop tracks immediately — we just wanted permission.
      _stopMediaStream();
      return true;
    } catch (e) {
      debugPrint('AudioServiceWeb: Permission denied: $e');
      return false;
    }
  }

  @override
  Future<bool> hasPermission() async {
    try {
      // Try to get a stream to check permission (permissions.query not
      // available for 'microphone' in all browsers).
      final constraints = web.MediaStreamConstraints(
        audio: true.toJS,
        video: false.toJS,
      );
      final stream = await web.window.navigator.mediaDevices
          .getUserMedia(constraints)
          .toDart;
      // Stop immediately
      final tracks = stream.getAudioTracks().toDart;
      for (final track in tracks) {
        track.stop();
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> startRecording() async {
    if (_state == AudioState.recording) return;

    final constraints = web.MediaStreamConstraints(
      audio: true.toJS,
      video: false.toJS,
    );
    _mediaStream = await web.window.navigator.mediaDevices
        .getUserMedia(constraints)
        .toDart;

    _audioContext = web.AudioContext(
      web.AudioContextOptions(sampleRate: _sampleRate.toDouble()),
    );

    _sourceNode = _audioContext!.createMediaStreamSource(_mediaStream!);

    // ScriptProcessorNode gathers raw PCM float32 samples.
    // bufferSize 4096 at 8000 Hz ≈ 512ms per buffer.
    _processorNode = _audioContext!.createScriptProcessor(
      4096, // bufferSize
      1, // inputChannels
      1, // outputChannels
    );

    _recordedChunks.clear();

    _processorNode!.onaudioprocess = ((web.AudioProcessingEvent event) {
      final inputBuffer = event.inputBuffer;
      final channelData = inputBuffer.getChannelData(0);
      // Convert JSFloat32Array to Dart Float32List
      final samples = channelData.toDart;
      _recordedChunks.add(Float32List.fromList(samples));

      // Also emit as PCM16 on the broadcast stream for real-time PTT.
      final pcm16 = Int16List(samples.length);
      for (int i = 0; i < samples.length; i++) {
        pcm16[i] = (samples[i] * 32767).round().clamp(-32768, 32767);
      }
      if (!_audioChunkController.isClosed) {
        _audioChunkController.add(pcm16.buffer.asUint8List());
      }
    }).toJS;

    _sourceNode!.connect(_processorNode!);
    _processorNode!.connect(_audioContext!.destination);

    _updateState(AudioState.recording);
    debugPrint('AudioServiceWeb: Recording started at ${_sampleRate}Hz');
  }

  @override
  Future<Uint8List?> stopRecording() async {
    if (_state != AudioState.recording) return null;

    _processorNode?.disconnect();
    _sourceNode?.disconnect();
    _stopMediaStream();

    _updateState(AudioState.idle);

    if (_recordedChunks.isEmpty) return null;

    // Convert float32 chunks to int16 PCM
    int totalSamples = 0;
    for (final chunk in _recordedChunks) {
      totalSamples += chunk.length;
    }

    final pcm16 = Int16List(totalSamples);
    int offset = 0;
    for (final chunk in _recordedChunks) {
      for (int i = 0; i < chunk.length; i++) {
        // Clamp float32 [-1.0, 1.0] → int16 [-32768, 32767]
        final sample = (chunk[i] * 32767).round().clamp(-32768, 32767);
        pcm16[offset++] = sample;
      }
    }

    _recordedChunks.clear();
    debugPrint('AudioServiceWeb: Recorded $totalSamples samples (${pcm16.buffer.lengthInBytes} bytes)');
    return pcm16.buffer.asUint8List();
  }

  @override
  Future<void> playAudio(Uint8List audioData) async {
    if (_state == AudioState.playing) {
      await stopPlayback();
    }

    _updateState(AudioState.playing);

    try {
      final ctx = web.AudioContext(
        web.AudioContextOptions(sampleRate: _sampleRate.toDouble()),
      );

      // Decode int16 PCM to float32
      final int16Data = audioData.buffer.asInt16List();
      final float32Data = Float32List(int16Data.length);
      for (int i = 0; i < int16Data.length; i++) {
        float32Data[i] = int16Data[i] / 32768.0;
      }

      final audioBuffer = ctx.createBuffer(
        1, // channels
        float32Data.length,
        _sampleRate.toDouble(),
      );

      // Copy float32 data into the AudioBuffer's channel
      audioBuffer.copyToChannel(float32Data.toJS, 0);

      final source = ctx.createBufferSource();
      source.buffer = audioBuffer;
      source.connect(ctx.destination);

      source.onended = ((web.Event _) {
        _updateState(AudioState.idle);
        ctx.close();
      }).toJS;

      source.start();
      debugPrint('AudioServiceWeb: Playing ${float32Data.length} samples');
    } catch (e) {
      debugPrint('AudioServiceWeb: Playback error: $e');
      _updateState(AudioState.idle);
    }
  }

  /// Start streaming playback (walkie-talkie RX mode).
  @override
  Future<void> startStreamingPlayback() async {
    if (_streamingPlaybackActive) return;

    _streamPlaybackCtx = web.AudioContext(
      web.AudioContextOptions(sampleRate: _sampleRate.toDouble()),
    );
    _nextPlayTime = 0;
    _streamingPlaybackActive = true;
    _updateState(AudioState.streamingPlayback);
    debugPrint('AudioServiceWeb: Streaming playback started');
  }

  /// Feed a chunk of PCM16 data to the streaming player.
  @override
  Future<void> feedAudioChunk(Uint8List chunk) async {
    if (!_streamingPlaybackActive || _streamPlaybackCtx == null) return;

    try {
      final int16Data = chunk.buffer.asInt16List();
      final float32Data = Float32List(int16Data.length);
      for (int i = 0; i < int16Data.length; i++) {
        float32Data[i] = int16Data[i] / 32768.0;
      }

      final audioBuffer = _streamPlaybackCtx!.createBuffer(
        1,
        float32Data.length,
        _sampleRate.toDouble(),
      );
      audioBuffer.copyToChannel(float32Data.toJS, 0);

      final source = _streamPlaybackCtx!.createBufferSource();
      source.buffer = audioBuffer;
      source.connect(_streamPlaybackCtx!.destination);

      final now = _streamPlaybackCtx!.currentTime;
      if (_nextPlayTime < now) _nextPlayTime = now;
      source.start(_nextPlayTime);
      _nextPlayTime += float32Data.length / _sampleRate;
    } catch (e) {
      debugPrint('AudioServiceWeb: feedAudioChunk error: $e');
    }
  }

  /// Stop the streaming playback session.
  @override
  Future<void> stopStreamingPlayback() async {
    if (!_streamingPlaybackActive) return;

    _streamingPlaybackActive = false;
    if (_streamPlaybackCtx != null) {
      await _streamPlaybackCtx!.close().toDart;
      _streamPlaybackCtx = null;
    }
    _updateState(AudioState.idle);
    debugPrint('AudioServiceWeb: Streaming playback stopped');
  }

  @override
  Future<void> loopbackTest({int durationSeconds = 3}) async {
    debugPrint('AudioServiceWeb: Starting loopback test...');
    await startRecording();
    await Future.delayed(Duration(seconds: durationSeconds));
    final data = await stopRecording();

    if (data != null && data.isNotEmpty) {
      debugPrint('AudioServiceWeb: Playing back ${data.length} bytes');
      await playAudio(data);
    } else {
      debugPrint('AudioServiceWeb: No audio data recorded');
    }
  }

  @override
  Future<void> stopPlayback() async {
    // AudioBufferSourceNode auto-stops; we just reset state.
    if (_state == AudioState.playing) {
      _updateState(AudioState.idle);
    }
  }

  @override
  Future<void> dispose() async {
    _stopMediaStream();
    _processorNode?.disconnect();
    _sourceNode?.disconnect();
    await _audioContext?.close().toDart;
    _stateController.close();
    _audioChunkController.close();
  }

  void _stopMediaStream() {
    if (_mediaStream != null) {
      final tracks = _mediaStream!.getAudioTracks().toDart;
      for (final track in tracks) {
        track.stop();
      }
      _mediaStream = null;
    }
  }

  void _updateState(AudioState newState) {
    _state = newState;
    _stateController.add(newState);
  }
}

AudioServiceBase createAudioService() => AudioServiceWeb();
