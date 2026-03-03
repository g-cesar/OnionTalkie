import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'providers/providers.dart';
import 'services/audio_service.dart';
import 'services/foreground_listen_service.dart';
import 'services/storage_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise storage FIRST so SharedPreferences is ready
  // before any provider tries to load settings.
  final storage = createStorageService();
  await storage.init();

  // Initialise audio service so recorder/player are open
  // before the UI tries to use them.
  final audio = createAudioService();
  await audio.init();

  // Initialise foreground service (Android / iOS only)
  await ForegroundListenService.init();

  if (!kIsWeb) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );
  }

  runApp(
    ProviderScope(
      overrides: [
        storageServiceProvider.overrideWithValue(storage),
        audioServiceProvider.overrideWithValue(audio),
      ],
      child: const OnionTalkieApp(),
    ),
  );
}
