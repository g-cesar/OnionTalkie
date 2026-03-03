import 'dart:convert';

/// Voice changer preset.
enum VoiceChangerPreset {
  off,
  deep,
  high,
  robot,
  echo,
  whisper,
  custom,
}

/// Key exchange mode.
enum KeyExchangeMode {
  /// Manual shared secret (PBKDF2 key derivation, same key every call).
  manual,

  /// SPAKE2 PAKE (zero-knowledge, fresh session key per call).
  pake,
}

/// PTT chime preset.
enum PttChimePreset {
  off,
  tone,
  doubleTone,
  chirp,
  ding,
  click,
  custom,
}

/// Application settings model.
class AppSettings {
  // Audio
  final int opusBitrate;
  final int sampleRate;

  // Security
  final String cipher;
  final bool hmacEnabled;
  final bool secretPassphraseEnabled;
  final KeyExchangeMode keyExchangeMode;

  // Tor
  final bool snowflakeEnabled;
  final String excludeNodes;
  final bool showCircuitPath;

  // PTT
  final bool autoListen;
  final PttChimePreset pttChime;

  // Voice Changer
  final VoiceChangerPreset voiceChangerPreset;
  final double customPitchShift;
  final double customOverdrive;
  final double customFlanger;
  final double customEcho;
  final double customHighpass;
  final double customTremolo;

  // Web relay
  final String relayServerUrl;

  const AppSettings({
    this.opusBitrate = 16,
    this.sampleRate = 8000,
    this.cipher = 'aes-256-cbc',
    this.hmacEnabled = false,
    this.secretPassphraseEnabled = false,
    this.keyExchangeMode = KeyExchangeMode.manual,
    this.snowflakeEnabled = false,
    this.excludeNodes = '',
    this.showCircuitPath = false,
    this.autoListen = false,
    this.pttChime = PttChimePreset.off,
    this.voiceChangerPreset = VoiceChangerPreset.off,
    this.customPitchShift = 0,
    this.customOverdrive = 0,
    this.customFlanger = 0,
    this.customEcho = 0,
    this.customHighpass = 0,
    this.customTremolo = 0,
    this.relayServerUrl = '',
  });

  AppSettings copyWith({
    int? opusBitrate,
    int? sampleRate,
    String? cipher,
    bool? hmacEnabled,
    bool? secretPassphraseEnabled,
    KeyExchangeMode? keyExchangeMode,
    bool? snowflakeEnabled,
    String? excludeNodes,
    bool? showCircuitPath,
    bool? autoListen,
    PttChimePreset? pttChime,
    VoiceChangerPreset? voiceChangerPreset,
    double? customPitchShift,
    double? customOverdrive,
    double? customFlanger,
    double? customEcho,
    double? customHighpass,
    double? customTremolo,
    String? relayServerUrl,
  }) {
    return AppSettings(
      opusBitrate: opusBitrate ?? this.opusBitrate,
      sampleRate: sampleRate ?? this.sampleRate,
      cipher: cipher ?? this.cipher,
      hmacEnabled: hmacEnabled ?? this.hmacEnabled,
      secretPassphraseEnabled: secretPassphraseEnabled ?? this.secretPassphraseEnabled,
      keyExchangeMode: keyExchangeMode ?? this.keyExchangeMode,
      snowflakeEnabled: snowflakeEnabled ?? this.snowflakeEnabled,
      excludeNodes: excludeNodes ?? this.excludeNodes,
      showCircuitPath: showCircuitPath ?? this.showCircuitPath,
      autoListen: autoListen ?? this.autoListen,
      pttChime: pttChime ?? this.pttChime,
      voiceChangerPreset: voiceChangerPreset ?? this.voiceChangerPreset,
      customPitchShift: customPitchShift ?? this.customPitchShift,
      customOverdrive: customOverdrive ?? this.customOverdrive,
      customFlanger: customFlanger ?? this.customFlanger,
      customEcho: customEcho ?? this.customEcho,
      customHighpass: customHighpass ?? this.customHighpass,
      customTremolo: customTremolo ?? this.customTremolo,
      relayServerUrl: relayServerUrl ?? this.relayServerUrl,
    );
  }

  Map<String, dynamic> toJson() => {
    'opusBitrate': opusBitrate,
    'sampleRate': sampleRate,
    'cipher': cipher,
    'hmacEnabled': hmacEnabled,
    'secretPassphraseEnabled': secretPassphraseEnabled,
    'keyExchangeMode': keyExchangeMode.name,
    'snowflakeEnabled': snowflakeEnabled,
    'excludeNodes': excludeNodes,
    'showCircuitPath': showCircuitPath,
    'autoListen': autoListen,
    'pttChime': pttChime.name,
    'voiceChangerPreset': voiceChangerPreset.name,
    'customPitchShift': customPitchShift,
    'customOverdrive': customOverdrive,
    'customFlanger': customFlanger,
    'customEcho': customEcho,
    'customHighpass': customHighpass,
    'customTremolo': customTremolo,
    'relayServerUrl': relayServerUrl,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      opusBitrate: json['opusBitrate'] as int? ?? 16,
      sampleRate: json['sampleRate'] as int? ?? 8000,
      cipher: json['cipher'] as String? ?? 'aes-256-cbc',
      hmacEnabled: json['hmacEnabled'] as bool? ?? false,
      secretPassphraseEnabled: json['secretPassphraseEnabled'] as bool? ?? false,
      keyExchangeMode: KeyExchangeMode.values.firstWhere(
        (e) => e.name == json['keyExchangeMode'],
        orElse: () => KeyExchangeMode.manual,
      ),
      snowflakeEnabled: json['snowflakeEnabled'] as bool? ?? false,
      excludeNodes: json['excludeNodes'] as String? ?? '',
      showCircuitPath: json['showCircuitPath'] as bool? ?? false,
      autoListen: json['autoListen'] as bool? ?? false,
      pttChime: PttChimePreset.values.firstWhere(
        (e) => e.name == json['pttChime'],
        orElse: () => PttChimePreset.off,
      ),
      voiceChangerPreset: VoiceChangerPreset.values.firstWhere(
        (e) => e.name == json['voiceChangerPreset'],
        orElse: () => VoiceChangerPreset.off,
      ),
      customPitchShift: (json['customPitchShift'] as num?)?.toDouble() ?? 0,
      customOverdrive: (json['customOverdrive'] as num?)?.toDouble() ?? 0,
      customFlanger: (json['customFlanger'] as num?)?.toDouble() ?? 0,
      customEcho: (json['customEcho'] as num?)?.toDouble() ?? 0,
      customHighpass: (json['customHighpass'] as num?)?.toDouble() ?? 0,
      customTremolo: (json['customTremolo'] as num?)?.toDouble() ?? 0,
      relayServerUrl: json['relayServerUrl'] as String? ?? '',
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory AppSettings.fromJsonString(String jsonString) {
    return AppSettings.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);
  }
}
