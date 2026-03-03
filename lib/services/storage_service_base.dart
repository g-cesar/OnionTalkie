import '../models/app_settings.dart';

/// Abstract storage service interface (platform-agnostic).
abstract class StorageServiceBase {
  /// Initialize storage.
  Future<void> init();

  // -- Settings --

  /// Save application settings.
  Future<void> saveSettings(AppSettings settings);

  /// Load application settings.
  AppSettings loadSettings();

  // -- Shared Secret --

  /// Save the shared secret.
  Future<void> saveSharedSecret(String secret);

  /// Load the shared secret.
  Future<String?> loadSharedSecret();

  /// Check if a shared secret exists.
  Future<bool> hasSharedSecret();

  /// Delete the shared secret.
  Future<void> deleteSharedSecret();

  // -- Generic key-value --

  Future<void> setString(String key, String value);
  String? getString(String key);
  Future<void> setBool(String key, bool value);
  bool? getBool(String key);

  // -- Cleanup --

  /// Clean up temporary files.
  Future<void> cleanupTempFiles();
}
