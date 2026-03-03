import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_settings.dart';
import '../services/storage_service.dart';
import 'providers.dart';

/// StateNotifier for application settings.
class SettingsNotifier extends StateNotifier<AppSettings> {
  final StorageServiceBase _storageService;

  SettingsNotifier(this._storageService) : super(const AppSettings()) {
    _load();
  }

  void _load() {
    state = _storageService.loadSettings();
  }

  Future<void> updateSettings(AppSettings newSettings) async {
    state = newSettings;
    await _storageService.saveSettings(newSettings);
  }

  Future<void> setCipher(String cipher) async {
    await updateSettings(state.copyWith(cipher: cipher));
  }

  Future<void> setOpusBitrate(int bitrate) async {
    await updateSettings(state.copyWith(opusBitrate: bitrate));
  }

  Future<void> setSampleRate(int sampleRate) async {
    await updateSettings(state.copyWith(sampleRate: sampleRate));
  }

  Future<void> setHmacEnabled(bool enabled) async {
    await updateSettings(state.copyWith(hmacEnabled: enabled));
  }

  Future<void> setSnowflakeEnabled(bool enabled) async {
    await updateSettings(state.copyWith(snowflakeEnabled: enabled));
  }

  Future<void> setShowCircuitPath(bool enabled) async {
    await updateSettings(state.copyWith(showCircuitPath: enabled));
  }

  Future<void> setCircuitRefreshSeconds(int seconds) async {
    await updateSettings(state.copyWith(circuitRefreshSeconds: seconds));
  }

  Future<void> setExcludeNodes(String nodes) async {
    await updateSettings(state.copyWith(excludeNodes: nodes));
  }

  Future<void> setPttChime(PttChimePreset chime) async {
    await updateSettings(state.copyWith(pttChime: chime));
  }

  Future<void> setVoiceChangerPreset(VoiceChangerPreset preset) async {
    await updateSettings(state.copyWith(voiceChangerPreset: preset));
  }

  Future<void> setSecretPassphraseEnabled(bool enabled) async {
    await updateSettings(state.copyWith(secretPassphraseEnabled: enabled));
  }

  Future<void> setKeyExchangeMode(KeyExchangeMode mode) async {
    await updateSettings(state.copyWith(keyExchangeMode: mode));
  }

  Future<void> setRelayServerUrl(String url) async {
    await updateSettings(state.copyWith(relayServerUrl: url));
  }

  Future<void> setLocale(String locale) async {
    await updateSettings(state.copyWith(locale: locale));
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return SettingsNotifier(storage);
});
