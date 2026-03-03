/// Application-wide constants for OnionTalkie.
class AppConstants {
  AppConstants._();

  // -- Network --
  static const int listenPort = 7777;
  static const int torSocksPort = 9050;
  static const int torControlPort = 9051;
  static const String torSocksHost = '127.0.0.1';

  // -- Audio --
  static const int defaultOpusBitrate = 16; // kbps
  static const int defaultSampleRate = 8000; // Hz
  static const int defaultChannels = 1; // Mono
  static const int chunkDuration = 1; // seconds

  // -- Encryption --
  static const String defaultCipher = 'aes-256-cbc';
  static const int pbkdf2Iterations = 10000;
  static const int pbkdf2KeyLength = 32; // bytes
  static const int ivLength = 16; // bytes
  static const int hmacIterations = 100000;

  // -- Protocol messages --
  static const String protoId = 'ID:';
  static const String protoCipher = 'CIPHER:';
  static const String protoPttStart = 'PTT_START';
  static const String protoPttStop = 'PTT_STOP';
  static const String protoAudio = 'AUDIO:';
  static const String protoMsg = 'MSG:';
  static const String protoHangup = 'HANGUP';
  static const String protoPing = 'PING';
  static const String protoHmacPrefix = 'HMAC:';
  static const String protoSpake2Pub = 'SPAKE2_PUB:';
  static const String protoSpake2Confirm = 'SPAKE2_CONFIRM:';

  // -- File paths --
  static const String torDataDir = 'tor_data';
  static const String audioDir = 'audio';
  static const String pidsDir = 'pids';
  static const String sharedSecretFile = 'shared_secret';
  static const String torrcFile = 'torrc';
  static const String settingsFile = 'settings.json';

  // -- UI --
  static const double maxContentWidth = 600;
  static const Duration connectingTimeout = Duration(seconds: 120);
  static const Duration firstBootTimeout = Duration(seconds: 300);
  static const Duration pingInterval = Duration(seconds: 30);
  static const Duration circuitRefreshInterval = Duration(seconds: 60);
}

/// Available cipher types ordered by strength (strongest first).
class CipherInfo {
  final String name;
  final String displayName;
  final int keyBits;
  final String family;

  const CipherInfo({
    required this.name,
    required this.displayName,
    required this.keyBits,
    required this.family,
  });
}

const List<CipherInfo> availableCiphers = [
  CipherInfo(name: 'aes-256-cbc', displayName: 'AES-256-CBC', keyBits: 256, family: 'AES'),
  CipherInfo(name: 'aes-256-ctr', displayName: 'AES-256-CTR', keyBits: 256, family: 'AES'),
  CipherInfo(name: 'aes-256-cfb', displayName: 'AES-256-CFB', keyBits: 256, family: 'AES'),
  CipherInfo(name: 'aes-256-ofb', displayName: 'AES-256-OFB', keyBits: 256, family: 'AES'),
  CipherInfo(name: 'chacha20-poly1305', displayName: 'ChaCha20-Poly1305', keyBits: 256, family: 'ChaCha20'),
  CipherInfo(name: 'chacha20', displayName: 'ChaCha20', keyBits: 256, family: 'ChaCha20'),
  CipherInfo(name: 'camellia-256-cbc', displayName: 'Camellia-256-CBC', keyBits: 256, family: 'Camellia'),
  CipherInfo(name: 'camellia-256-ctr', displayName: 'Camellia-256-CTR', keyBits: 256, family: 'Camellia'),
  CipherInfo(name: 'aria-256-cbc', displayName: 'ARIA-256-CBC', keyBits: 256, family: 'ARIA'),
  CipherInfo(name: 'aria-256-ctr', displayName: 'ARIA-256-CTR', keyBits: 256, family: 'ARIA'),
  CipherInfo(name: 'aes-192-cbc', displayName: 'AES-192-CBC', keyBits: 192, family: 'AES'),
  CipherInfo(name: 'aes-192-ctr', displayName: 'AES-192-CTR', keyBits: 192, family: 'AES'),
  CipherInfo(name: 'camellia-192-cbc', displayName: 'Camellia-192-CBC', keyBits: 192, family: 'Camellia'),
  CipherInfo(name: 'aria-192-cbc', displayName: 'ARIA-192-CBC', keyBits: 192, family: 'ARIA'),
  CipherInfo(name: 'aes-128-cbc', displayName: 'AES-128-CBC', keyBits: 128, family: 'AES'),
  CipherInfo(name: 'aes-128-ctr', displayName: 'AES-128-CTR', keyBits: 128, family: 'AES'),
  CipherInfo(name: 'aes-128-cfb', displayName: 'AES-128-CFB', keyBits: 128, family: 'AES'),
  CipherInfo(name: 'aes-128-ofb', displayName: 'AES-128-OFB', keyBits: 128, family: 'AES'),
  CipherInfo(name: 'camellia-128-cbc', displayName: 'Camellia-128-CBC', keyBits: 128, family: 'Camellia'),
  CipherInfo(name: 'aria-128-cbc', displayName: 'ARIA-128-CBC', keyBits: 128, family: 'ARIA'),
  CipherInfo(name: 'aria-128-ctr', displayName: 'ARIA-128-CTR', keyBits: 128, family: 'ARIA'),
];
