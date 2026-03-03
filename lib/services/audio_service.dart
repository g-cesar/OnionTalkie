// Audio service — platform-adaptive barrel.
//
// On native (Android/iOS/desktop) uses flutter_sound.
// On web uses Web Audio API (MediaRecorder + AudioContext).
export 'audio_service_base.dart';

import 'audio_service_stub.dart'
    if (dart.library.io) 'audio_service_native.dart'
    if (dart.library.html) 'audio_service_web.dart' as impl;

import 'audio_service_base.dart';

/// Create a platform-appropriate AudioService.
AudioServiceBase createAudioService() => impl.createAudioService();
