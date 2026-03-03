import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/audio_service.dart';
import '../services/connection_service.dart';
import '../services/encryption_service.dart';
import '../services/storage_service.dart';

/// Core service providers (singletons).

final storageServiceProvider = Provider<StorageServiceBase>((ref) {
  // Overridden in main() with a pre-initialized instance.
  // This fallback should never be reached in practice.
  throw UnimplementedError(
    'storageServiceProvider must be overridden with an already-initialized instance',
  );
});

final audioServiceProvider = Provider<AudioServiceBase>((ref) {
  // Overridden in main() with a pre-initialized instance.
  throw UnimplementedError(
    'audioServiceProvider must be overridden with an already-initialized instance',
  );
});

final encryptionServiceProvider = Provider<EncryptionService>((ref) {
  return EncryptionService();
});

final connectionServiceProvider = Provider<ConnectionServiceBase>((ref) {
  final service = createConnectionService();
  ref.onDispose(() => service.dispose());
  return service;
});
