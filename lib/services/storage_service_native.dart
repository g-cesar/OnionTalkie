
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_constants.dart';
import '../models/app_settings.dart';
import 'storage_service_base.dart';

/// Native storage service using filesystem + SharedPreferences.
class StorageServiceNative extends StorageServiceBase {
  SharedPreferences? _prefs;

  /// Initialize shared preferences.
  @override
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// Get the app data directory.
  Future<String> getAppDataDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/terminalphone');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }

  // -- Settings --

  /// Save application settings.
  @override
  Future<void> saveSettings(AppSettings settings) async {
    await _prefs?.setString(AppConstants.settingsFile, settings.toJsonString());
  }

  /// Load application settings.
  @override
  AppSettings loadSettings() {
    final json = _prefs?.getString(AppConstants.settingsFile);
    if (json != null) {
      return AppSettings.fromJsonString(json);
    }
    return const AppSettings();
  }

  // -- Shared Secret --

  /// Save the shared secret (optionally encrypted with passphrase).
  @override
  Future<void> saveSharedSecret(String secret) async {
    final dataDir = await getAppDataDir();
    final file = File('$dataDir/${AppConstants.sharedSecretFile}');
    await file.writeAsString(secret);
  }

  /// Load the shared secret.
  @override
  Future<String?> loadSharedSecret() async {
    final dataDir = await getAppDataDir();
    final file = File('$dataDir/${AppConstants.sharedSecretFile}');
    if (await file.exists()) {
      return (await file.readAsString()).trim();
    }
    return null;
  }

  /// Check if a shared secret exists.
  @override
  Future<bool> hasSharedSecret() async {
    final dataDir = await getAppDataDir();
    final file = File('$dataDir/${AppConstants.sharedSecretFile}');
    return file.exists();
  }

  /// Delete the shared secret.
  @override
  Future<void> deleteSharedSecret() async {
    final dataDir = await getAppDataDir();
    final file = File('$dataDir/${AppConstants.sharedSecretFile}');
    if (await file.exists()) {
      await file.delete();
    }
  }

  // -- Generic key-value --

  @override
  Future<void> setString(String key, String value) async {
    await _prefs?.setString(key, value);
  }

  @override
  String? getString(String key) {
    return _prefs?.getString(key);
  }

  @override
  Future<void> setBool(String key, bool value) async {
    await _prefs?.setBool(key, value);
  }

  @override
  bool? getBool(String key) {
    return _prefs?.getBool(key);
  }

  // -- Cleanup --

  /// Clean up temporary audio files.
  @override
  Future<void> cleanupTempFiles() async {
    final dir = await getTemporaryDirectory();
    final files = dir.listSync();
    for (final file in files) {
      if (file is File && file.path.contains('tp_')) {
        await file.delete();
      }
    }
  }
}

StorageServiceBase createStorageService() => StorageServiceNative();
