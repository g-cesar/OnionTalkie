import 'dart:async';


import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/app_settings.dart';
import '../models/call_state.dart';
import '../models/chat_message.dart';
import '../services/audio_codec.dart';
import '../services/audio_service.dart';
import '../services/chime_service.dart';
import '../services/connection_service.dart';
import '../services/encryption_service.dart';
import '../services/foreground_listen_service.dart';
import '../services/spake2_service.dart';
import '../services/voice_processor.dart';
import 'contacts_provider.dart';
import 'providers.dart';
import 'settings_provider.dart';
import 'tor_provider.dart';

/// Provider for the list of chat messages in the current call.
final chatMessagesProvider = StateProvider<List<ChatMessage>>((ref) => []);

/// StateNotifier for call state management.
class CallNotifier extends StateNotifier<CallState> {
  final ConnectionServiceBase _connectionService;
  final AudioServiceBase _audioService;
  final EncryptionService _encryptionService;
  final Ref _ref;
  StreamSubscription? _messageSubscription;
  Timer? _pingTimer;
  final _uuid = const Uuid();

  /// Active SPAKE2 handshake session (null when not using PAKE).
  Spake2Session? _spake2;

  /// Contact id being called (null for ad-hoc calls).
  String? _activeContactId;

  /// Subscription to audio chunks during live PTT transmission.
  StreamSubscription<Uint8List>? _audioChunkSub;

  /// Completer that resolves when streaming playback is ready to receive
  /// audio chunks.  Set by [_handleRemotePttStart], awaited by
  /// [_handleAudioChunkReceived] so early chunks are not lost.
  Completer<void>? _streamingReady;

  CallNotifier(
    this._connectionService,
    this._audioService,
    this._encryptionService,
    this._ref,
  ) : super(const CallState());

  /// Start listening for incoming calls.
  Future<void> listenForCalls() async {
    state = state.copyWith(
      phase: CallPhase.connecting,
      isIncoming: true,
    );

    // Start foreground service so the OS keeps the app alive in background
    await ForegroundListenService.startListening();

    try {
      await _connectionService.listen();
      state = state.addStep(ConnectionStep.torCircuit);
      _setupMessageHandler();
    } catch (e) {
      await ForegroundListenService.stop();
      state = state.copyWith(
        phase: CallPhase.error,
        errorMessage: 'Failed to listen: $e',
      );
    }
  }

  /// Call a remote .onion address.
  ///
  /// If [contactId] is provided, the contact's shared secret is loaded
  /// automatically (the caller should have already set it on
  /// EncryptionService for the SPAKE2 / manual flow to work).
  Future<void> call(String onionAddress, {String? contactId}) async {
    _activeContactId = contactId;
    state = state.copyWith(
      phase: CallPhase.connecting,
      remoteAddress: onionAddress,
      isIncoming: false,
    );

    try {
      final settings = _ref.read(settingsProvider);
      _setupHmac(settings);

      // Tor circuits are inherently unreliable — retry up to 3 times with
      // increasing back-off to dramatically improve connection success rate.
      const maxAttempts = 3;
      for (int attempt = 1; attempt <= maxAttempts; attempt++) {
        try {
          debugPrint(
            'CallNotifier: connection attempt $attempt/$maxAttempts '
            'to $onionAddress',
          );
          await _connectionService.connect(onionAddress);
          break; // success
        } catch (e) {
          if (attempt == maxAttempts) rethrow;
          debugPrint(
            'CallNotifier: attempt $attempt failed ($e), retrying '
            'in ${2 * attempt}s…',
          );
          await Future.delayed(Duration(seconds: 2 * attempt));
          // Ensure clean state before next attempt
          await _connectionService.disconnect();
        }
      }

      state = state
          .addStep(ConnectionStep.torCircuit)
          .addStep(ConnectionStep.peerConnected);

      _setupMessageHandler();

      await ForegroundListenService.startListening();

      if (settings.keyExchangeMode == KeyExchangeMode.pake &&
          _encryptionService.hasSecret) {
        // ── PAKE mode: start SPAKE2 handshake, stay in connecting ──
        _spake2 = Spake2Session.initiator(_encryptionService.sharedSecret);
        _connectionService.sendSpake2Pub(_spake2!.publicValueBase64);
        debugPrint('CallNotifier: SPAKE2 initiator handshake started');
        // → call setup will complete in _handleSpake2Confirm
      } else {
        // ── Manual mode: send ID/CIPHER immediately and go active ──
        _sendIdAndGoActive(settings);
      }
    } catch (e) {
      await ForegroundListenService.stop();
      state = state.copyWith(
        phase: CallPhase.error,
        errorMessage: 'Failed to connect: $e',
      );
    }
  }

  /// Send our ID + CIPHER and transition to active call state.
  void _sendIdAndGoActive(AppSettings settings, {bool pakeActive = false}) {
    final torStatus = _ref.read(torProvider);
    if (torStatus.onionAddress != null) {
      _connectionService.sendId(torStatus.onionAddress!);
    }

    _connectionService.sendCipher(settings.cipher);
    _encryptionService.setCipher(settings.cipher);

    if (!pakeActive) {
      state = state
          .addStep(ConnectionStep.keyExchange)
          .addStep(ConnectionStep.keyVerified);
    }
    state = state.addStep(ConnectionStep.encrypted);

    ForegroundListenService.notifyActiveCall();

    state = state.copyWith(
      phase: CallPhase.active,
      localCipher: settings.cipher,
      callStartTime: DateTime.now(),
      hmacEnabled: settings.hmacEnabled,
      pakeActive: pakeActive,
    );

    _startPingTimer();

    // Mark contact as contacted
    if (_activeContactId != null) {
      try {
        _ref.read(contactsProvider.notifier).markContacted(_activeContactId!);
      } catch (_) {}
    }
  }

  /// Configure HMAC on the connection service.
  void _setupHmac(AppSettings settings) {
    _connectionService.setHmac(
      enabled: settings.hmacEnabled,
      key: _encryptionService.hasSecret ? _encryptionService.cipher : '',
    );
  }

  /// Set up the message handler for incoming protocol messages.
  void _setupMessageHandler() {
    _messageSubscription?.cancel();
    _messageSubscription = _connectionService.messageStream.listen((entry) {
      _handleMessage(entry.key, entry.value);
    });
  }

  /// Handle incoming protocol messages.
  void _handleMessage(String type, String data) {
    switch (type) {
      case 'SPAKE2_PUB':
        _handleSpake2Pub(data);
        break;

      case 'SPAKE2_CONFIRM':
        _handleSpake2Confirm(data);
        break;

      case 'ID':
        state = state.copyWith(remoteAddress: data);
        if (!state.completedSteps.contains(ConnectionStep.peerConnected)) {
          state = state.addStep(ConnectionStep.peerConnected);
        }
        // If incoming call, resolve the peer and transition to ringing.
        if (state.isIncoming && state.phase == CallPhase.connecting) {
          _resolveIncomingPeer(data);

          // Notify user about the incoming connection
          ForegroundListenService.notifyIncomingCall();

          // Transition to ringing — the UI will show the incoming call
          // screen and auto-accept after a short delay.
          state = state.copyWith(phase: CallPhase.ringing);
          debugPrint('CallNotifier: incoming call from $data — ringing');
        }
        break;

      case 'CIPHER':
        state = state.copyWith(remoteCipher: data);
        break;

      case 'PTT_START':
        _handleRemotePttStart();
        break;

      case 'PTT_STOP':
        _handleRemotePttStop();
        break;

      case 'AUDIO':
        _handleAudioChunkReceived(data);
        break;

      case 'MSG':
        _handleTextReceived(data);
        break;

      case 'HANGUP':
        state = state.copyWith(phase: CallPhase.ended);
        _cleanup();
        ForegroundListenService.stop();
        break;

      case 'PING':
        // Keepalive received, no action needed
        break;

      case 'ERROR':
      case 'DISCONNECTED':
        if (state.phase == CallPhase.active) {
          state = state.copyWith(
            phase: CallPhase.ended,
            errorMessage: type == 'ERROR' ? data : 'Connection lost',
          );
          _cleanup();
          ForegroundListenService.stop();
        }
        break;
    }
  }

  // ─── SPAKE2 handshake handlers ──────────────────────────────────

  /// Resolve an incoming peer's onion address to a saved contact.
  /// If found, loads their shared secret into EncryptionService.
  void _resolveIncomingPeer(String peerOnion) {
    try {
      final contactsNotifier = _ref.read(contactsProvider.notifier);
      final contact = contactsNotifier.findByOnion(peerOnion);
      if (contact != null) {
        _activeContactId = contact.id;
        if (contact.hasSecret) {
          _encryptionService.setSharedSecret(contact.sharedSecret);
          debugPrint('CallNotifier: loaded secret for contact "${contact.alias}"');
        }
        return;
      }
      // Check if the address used to belong to a different contact
      // (peer rotated their hidden service).
      final prev = contactsNotifier.findByPreviousOnion(peerOnion);
      if (prev != null) {
        debugPrint(
            'CallNotifier: incoming from PREVIOUS onion of "${prev.alias}" — address change detected');
      }
    } catch (_) {
      // contacts provider may not be initialised in tests — ignore
    }
  }

  /// Handle received SPAKE2 blinded public value.
  void _handleSpake2Pub(String base64Value) {
    try {
      if (_spake2 == null) {
        // We're the responder — auto-engage in SPAKE2 handshake
        if (!_encryptionService.hasSecret) {
          debugPrint('CallNotifier: SPAKE2_PUB received but no secret set');
          return;
        }
        _spake2 = Spake2Session.responder(_encryptionService.sharedSecret);
      }

      _spake2!.processRemotePublicValue(base64Value);

      if (!state.completedSteps.contains(ConnectionStep.peerConnected)) {
        state = state.addStep(ConnectionStep.peerConnected);
      }
      state = state.addStep(ConnectionStep.keyExchange);

      if (state.isIncoming) {
        // Responder: send our public value + confirmation
        _connectionService.sendSpake2Pub(_spake2!.publicValueBase64);
        _connectionService.sendSpake2Confirm(_spake2!.generateConfirmation());
        debugPrint('CallNotifier: SPAKE2 responder sent PUB + CONFIRM');
      } else {
        // Initiator: got responder's pub → send our confirmation
        _connectionService.sendSpake2Confirm(_spake2!.generateConfirmation());
        debugPrint('CallNotifier: SPAKE2 initiator sent CONFIRM');
      }
    } catch (e) {
      debugPrint('CallNotifier: SPAKE2 public value error: $e');
      state = state.copyWith(
        phase: CallPhase.error,
        errorMessage: 'Errore SPAKE2: $e',
      );
    }
  }

  /// Handle received SPAKE2 key-confirmation MAC.
  void _handleSpake2Confirm(String confirmHex) {
    if (_spake2 == null || !_spake2!.isComplete) {
      debugPrint('CallNotifier: SPAKE2_CONFIRM received but no session');
      return;
    }

    if (!_spake2!.verifyConfirmation(confirmHex)) {
      state = state.copyWith(
        phase: CallPhase.error,
        errorMessage: 'Verifica SPAKE2 fallita — passphrase errata?',
      );
      _cleanup();
      ForegroundListenService.stop();
      return;
    }

    debugPrint('CallNotifier: SPAKE2 key confirmation verified ✓');

    state = state.addStep(ConnectionStep.keyVerified);

    // Set the SPAKE2-derived session key on the encryption service
    _encryptionService.setSessionKey(_spake2!.sessionKey);

    if (!state.isIncoming) {
      // Initiator: SPAKE2 complete → now send ID/CIPHER and go active
      final settings = _ref.read(settingsProvider);
      _sendIdAndGoActive(settings, pakeActive: true);
    }
    // Responder: will receive ID next → normal active transition
  }

  // ─── Audio / Text handlers ──────────────────────────────────────

  /// Accept the incoming call: send our ID + CIPHER and go active.
  void acceptIncomingCall() {
    if (state.phase != CallPhase.ringing) return;

    final torStatus = _ref.read(torProvider);
    if (torStatus.onionAddress != null) {
      _connectionService.sendId(torStatus.onionAddress!);
    }
    final settings = _ref.read(settingsProvider);
    _setupHmac(settings);
    _connectionService.sendCipher(settings.cipher);
    _encryptionService.setCipher(settings.cipher);

    final isPake = _spake2 != null && _spake2!.isComplete;

    if (!isPake) {
      state = state
          .addStep(ConnectionStep.keyExchange)
          .addStep(ConnectionStep.keyVerified);
    }
    state = state.addStep(ConnectionStep.encrypted);

    state = state.copyWith(
      phase: CallPhase.active,
      localCipher: settings.cipher,
      callStartTime: DateTime.now(),
      hmacEnabled: settings.hmacEnabled,
      pakeActive: isPake,
    );

    ForegroundListenService.notifyActiveCall();
    _startPingTimer();

    // Mark contact as contacted
    if (_activeContactId != null) {
      try {
        _ref.read(contactsProvider.notifier).markContacted(_activeContactId!);
      } catch (_) {}
    }

    debugPrint('CallNotifier: incoming call accepted — active');
  }

  /// Handle remote party starting PTT transmission.
  ///
  /// Opens streaming playback so incoming audio chunks play in real-time.
  /// Blocks local PTT while the remote is transmitting (walkie-talkie
  /// mutual exclusion).
  void _handleRemotePttStart() {
    state = state.copyWith(remotePttState: RemotePttState.recording);

    // Create a completer that _handleAudioChunkReceived will await before
    // feeding data — avoids the race where chunks arrive before the player
    // has finished opening.
    _streamingReady = Completer<void>();

    // Start streaming playback asynchronously; complete the gate once ready.
    _audioService.startStreamingPlayback().then((_) {
      if (_streamingReady != null && !_streamingReady!.isCompleted) {
        _streamingReady!.complete();
      }
    }).catchError((e) {
      debugPrint('CallNotifier: startStreamingPlayback error: $e');
      if (_streamingReady != null && !_streamingReady!.isCompleted) {
        _streamingReady!.completeError(e);
      }
    });

    debugPrint('CallNotifier: Remote PTT started — streaming playback opening');
  }

  /// Handle remote party stopping PTT transmission.
  ///
  /// Stops streaming playback.
  void _handleRemotePttStop() {
    state = state.copyWith(remotePttState: RemotePttState.idle);
    _streamingReady = null;

    _audioService.stopStreamingPlayback();
    debugPrint('CallNotifier: Remote PTT stopped — playback closed');
  }

  /// Handle an incoming audio chunk during real-time PTT.
  ///
  /// Decrypts, decompresses and feeds the chunk to the streaming player.
  /// Waits for the streaming player to be ready (in case PTT_START was
  /// received just before this chunk).
  Future<void> _handleAudioChunkReceived(String base64Audio) async {
    try {
      var audioData = _encryptionService.decrypt(base64Audio);

      // Decompress ADPCM if compressed
      if (AudioCodec.isCompressed(audioData)) {
        audioData = AudioCodec.decode(audioData);
      }

      state = state.copyWith(
        receivedBytes: state.receivedBytes + base64Audio.length,
      );

      // Feed to streaming player (or single-blob fallback).
      if (state.remotePttState == RemotePttState.recording) {
        // Wait for the streaming player to finish opening before feeding.
        if (_streamingReady != null && !_streamingReady!.isCompleted) {
          await _streamingReady!.future.timeout(
            const Duration(seconds: 3),
            onTimeout: () {
              debugPrint('CallNotifier: Streaming ready timeout — feeding anyway');
            },
          );
        }
        await _audioService.feedAudioChunk(audioData);
      } else {
        await _audioService.playAudio(audioData);
      }
    } catch (e) {
      debugPrint('CallNotifier: Failed to handle audio chunk: $e');
    }
  }

  /// Handle received encrypted text message.
  void _handleTextReceived(String base64Msg) {
    try {
      final text = _encryptionService.decryptText(base64Msg);
      state = state.copyWith(
        receivedBytes: state.receivedBytes + base64Msg.length,
        messageCount: state.messageCount + 1,
      );

      final messages = _ref.read(chatMessagesProvider);
      _ref.read(chatMessagesProvider.notifier).state = [
        ...messages,
        ChatMessage(
          id: _uuid.v4(),
          type: MessageType.text,
          direction: MessageDirection.received,
          content: text,
          timestamp: DateTime.now(),
          payloadBytes: base64Msg.length,
        ),
      ];
    } catch (e) {
      debugPrint('CallNotifier: Failed to decrypt message: $e');
    }
  }

  /// Start PTT recording — streams audio chunks to the remote peer in
  /// real-time (walkie-talkie mode).
  ///
  /// Blocked when the remote party is already transmitting (mutual exclusion).
  Future<void> startRecording() async {
    if (state.phase != CallPhase.active) return;

    // ── Walkie-talkie mutual exclusion: cannot talk while remote sends ──
    if (state.remotePttState == RemotePttState.recording) {
      debugPrint('CallNotifier: cannot record — remote is transmitting');
      return;
    }

    // Block recording while audio is still playing.
    if (_audioService.currentState == AudioState.playing ||
        _audioService.currentState == AudioState.streamingPlayback) {
      debugPrint('CallNotifier: cannot record while audio is playing');
      return;
    }

    try {
      // Play PTT chime before recording
      final settings = _ref.read(settingsProvider);
      await _playPttChime(settings);

      await _audioService.startRecording();
      state = state.copyWith(isRecording: true);
      _connectionService.sendPttStart();

      // Subscribe to audio chunks — encrypt and send each one live.
      _audioChunkSub = _audioService.audioChunkStream.listen((chunk) {
        _sendAudioChunkLive(chunk);
      });
    } catch (e) {
      debugPrint('CallNotifier: Failed to start recording: $e');
    }
  }

  /// Encrypt and send a single audio chunk in real-time.
  void _sendAudioChunkLive(Uint8List chunk) {
    try {
      final settings = _ref.read(settingsProvider);
      var audioData = chunk;

      // Apply voice effects if configured.
      if (settings.voiceChangerPreset != VoiceChangerPreset.off) {
        audioData = VoiceProcessor.applyPreset(
          audioData,
          settings.voiceChangerPreset,
          settings.sampleRate,
          customPitch: settings.customPitchShift,
          customOverdrive: settings.customOverdrive,
          customFlanger: settings.customFlanger,
          customEcho: settings.customEcho,
          customHighpass: settings.customHighpass,
          customTremolo: settings.customTremolo,
        );
      }

      // Compress with ADPCM if enabled.
      if (settings.opusBitrate > 0) {
        audioData = AudioCodec.encode(audioData);
      }

      final encrypted = _encryptionService.encrypt(audioData);
      _connectionService.sendAudio(encrypted);

      state = state.copyWith(
        sentBytes: state.sentBytes + encrypted.length,
      );
    } catch (e) {
      debugPrint('CallNotifier: Failed to send audio chunk: $e');
    }
  }

  /// Stop PTT recording and finalise the transmission.
  Future<void> stopRecording() async {
    if (!state.isRecording) return;

    try {
      // Stop subscribing to audio chunks.
      await _audioChunkSub?.cancel();
      _audioChunkSub = null;

      await _audioService.stopRecording();
      state = state.copyWith(isRecording: false);
      _connectionService.sendPttStop();
    } catch (e) {
      debugPrint('CallNotifier: Failed to stop recording: $e');
    }
  }

  /// Play PTT chime sound.
  Future<void> _playPttChime(AppSettings settings) async {
    if (settings.pttChime == PttChimePreset.off) return;

    try {
      final chimeData = ChimeService.generateChime(
        settings.pttChime,
        settings.sampleRate,
      );
      if (chimeData != null) {
        await _audioService.playAudio(chimeData);
        // Brief pause to let chime play
        await Future.delayed(const Duration(milliseconds: 250));
      }
    } catch (e) {
      debugPrint('CallNotifier: Failed to play chime: $e');
    }
  }

  /// Send an encrypted text message.
  Future<void> sendTextMessage(String text) async {
    if (state.phase != CallPhase.active || text.trim().isEmpty) return;

    try {
      final encrypted = _encryptionService.encryptText(text);
      _connectionService.sendMessage(encrypted);

      state = state.copyWith(
        sentBytes: state.sentBytes + encrypted.length,
        messageCount: state.messageCount + 1,
      );

      final messages = _ref.read(chatMessagesProvider);
      _ref.read(chatMessagesProvider.notifier).state = [
        ...messages,
        ChatMessage(
          id: _uuid.v4(),
          type: MessageType.text,
          direction: MessageDirection.sent,
          content: text,
          timestamp: DateTime.now(),
          payloadBytes: encrypted.length,
        ),
      ];
    } catch (e) {
      debugPrint('CallNotifier: Failed to send message: $e');
    }
  }

  /// Change cipher mid-call.
  void changeCipher(String cipher) {
    _encryptionService.setCipher(cipher);
    _connectionService.sendCipher(cipher);
    state = state.copyWith(localCipher: cipher);
  }

  /// Hang up the call.
  Future<void> hangUp() async {
    state = state.copyWith(phase: CallPhase.ended);
    _cleanup();
    await ForegroundListenService.stop();
    await _connectionService.disconnect();
  }

  /// Start the ping keepalive timer.
  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) {
        if (_connectionService.isConnected) {
          _connectionService.sendPing();
        }
      },
    );
  }

  /// Clean up resources after call ends.
  void _cleanup() {
    _messageSubscription?.cancel();
    _pingTimer?.cancel();
    _audioChunkSub?.cancel();
    _audioChunkSub = null;
    _streamingReady = null;
    _spake2 = null;
    _activeContactId = null;
    _encryptionService.resetSessionKey();
  }

  /// Reset state for a new call.
  void reset() {
    _cleanup();
    // Disconnect the connection service so stale sockets (especially the
    // ServerSocket used for listening) are properly closed before starting
    // a new call.  Without this, listen() would find the old ServerSocket
    // still bound and return early, leaving the receiver stuck.
    _connectionService.disconnect();
    ForegroundListenService.stop();
    state = const CallState();
    _ref.read(chatMessagesProvider.notifier).state = [];
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }
}

final callProvider = StateNotifierProvider<CallNotifier, CallState>((ref) {
  final connection = ref.watch(connectionServiceProvider);
  final audio = ref.watch(audioServiceProvider);
  final encryption = ref.watch(encryptionServiceProvider);
  return CallNotifier(connection, audio, encryption, ref);
});
