import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_constants.dart';
import '../models/app_settings.dart';
import 'storage_service_base.dart';

/// Web storage service — uses SharedPreferences (localStorage) only.
///
/// No file system access on the web; all data is stored in localStorage
/// via the SharedPreferences plugin.
class StorageServiceWeb extends StorageServiceBase {
  SharedPreferences? _prefs;

  static const _secretKey = 'tp_shared_secret';

  @override
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // -- Settings --

  @override
  Future<void> saveSettings(AppSettings settings) async {
    await _prefs?.setString(AppConstants.settingsFile, settings.toJsonString());
  }

  @override
  AppSettings loadSettings() {
    final json = _prefs?.getString(AppConstants.settingsFile);
    if (json != null) {
      return AppSettings.fromJsonString(json);
    }
    return const AppSettings();
  }

  // -- Shared Secret --

  @override
  Future<void> saveSharedSecret(String secret) async {
    await _prefs?.setString(_secretKey, secret);
  }

  @override
  Future<String?> loadSharedSecret() async {
    return _prefs?.getString(_secretKey);
  }

  @override
  Future<bool> hasSharedSecret() async {
    return _prefs?.containsKey(_secretKey) ?? false;
  }

  @override
  Future<void> deleteSharedSecret() async {
    await _prefs?.remove(_secretKey);
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

  @override
  Future<void> cleanupTempFiles() async {
    // No temp files on web — all data is in memory / localStorage
  }
}

StorageServiceBase createStorageService() => StorageServiceWeb();
