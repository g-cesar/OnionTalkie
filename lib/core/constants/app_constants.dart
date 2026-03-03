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
}

/// Available cipher types ordered by strength (strongest first).
class CipherInfo {
  final String name;
  final String displayName;
  final int keyBits;
  final String family;
  final String description;

  const CipherInfo({
    required this.name,
    required this.displayName,
    required this.keyBits,
    required this.family,
    required this.description,
  });
}

const List<CipherInfo> availableCiphers = [
  CipherInfo(name: 'aes-256-cbc', displayName: 'AES-256-CBC', keyBits: 256, family: 'AES',
    description: 'Standard industriale, veloce con AES-NI hardware. Consigliato per la maggior parte dei dispositivi.'),
  CipherInfo(name: 'aes-256-ctr', displayName: 'AES-256-CTR', keyBits: 256, family: 'AES',
    description: 'Modalità contatore, non richiede padding. Ideale per flussi audio continui.'),
  CipherInfo(name: 'aes-256-cfb', displayName: 'AES-256-CFB', keyBits: 256, family: 'AES',
    description: 'Cifrario a flusso basato su AES. Tollerante alla perdita di pacchetti.'),
  CipherInfo(name: 'aes-256-ofb', displayName: 'AES-256-OFB', keyBits: 256, family: 'AES',
    description: 'Pre-computa il keystream indipendentemente dal testo cifrato.'),
  CipherInfo(name: 'chacha20-poly1305', displayName: 'ChaCha20-Poly1305', keyBits: 256, family: 'ChaCha20',
    description: 'Ottimo per dispositivi mobili senza AES hardware. Autenticazione integrata (AEAD).'),
  CipherInfo(name: 'chacha20', displayName: 'ChaCha20', keyBits: 256, family: 'ChaCha20',
    description: 'Veloce su CPU ARM senza AES-NI. Senza autenticazione integrata.'),
  CipherInfo(name: 'camellia-256-cbc', displayName: 'Camellia-256-CBC', keyBits: 256, family: 'Camellia',
    description: 'Alternativa ad AES, standard giapponese approvato ISO/NESSIE.'),
  CipherInfo(name: 'camellia-256-ctr', displayName: 'Camellia-256-CTR', keyBits: 256, family: 'Camellia',
    description: 'Variante CTR di Camellia per flussi continui.'),
  CipherInfo(name: 'aria-256-cbc', displayName: 'ARIA-256-CBC', keyBits: 256, family: 'ARIA',
    description: 'Standard coreano, equivalente ad AES in sicurezza.'),
  CipherInfo(name: 'aria-256-ctr', displayName: 'ARIA-256-CTR', keyBits: 256, family: 'ARIA',
    description: 'Variante CTR di ARIA. Meno diffuso, buona diversificazione algoritmica.'),
  CipherInfo(name: 'aes-192-cbc', displayName: 'AES-192-CBC', keyBits: 192, family: 'AES',
    description: 'Chiave ridotta a 192 bit. Adeguato ma preferire 256 bit se possibile.'),
  CipherInfo(name: 'aes-192-ctr', displayName: 'AES-192-CTR', keyBits: 192, family: 'AES',
    description: 'AES-192 in modalità contatore. Buon compromesso velocità/sicurezza.'),
  CipherInfo(name: 'camellia-192-cbc', displayName: 'Camellia-192-CBC', keyBits: 192, family: 'Camellia',
    description: 'Camellia con chiave 192 bit. Meno supportato hardware.'),
  CipherInfo(name: 'aria-192-cbc', displayName: 'ARIA-192-CBC', keyBits: 192, family: 'ARIA',
    description: 'ARIA con chiave 192 bit. Utilizzato in ambito governativo coreano.'),
  CipherInfo(name: 'aes-128-cbc', displayName: 'AES-128-CBC', keyBits: 128, family: 'AES',
    description: 'Chiave 128 bit. Sicuro oggi ma margine ridotto contro attacchi futuri.'),
  CipherInfo(name: 'aes-128-ctr', displayName: 'AES-128-CTR', keyBits: 128, family: 'AES',
    description: 'AES-128 contatore. Il più veloce in assoluto ma chiave corta.'),
  CipherInfo(name: 'aes-128-cfb', displayName: 'AES-128-CFB', keyBits: 128, family: 'AES',
    description: 'Cifrario a flusso su AES-128. Solo per compatibilità.'),
  CipherInfo(name: 'aes-128-ofb', displayName: 'AES-128-OFB', keyBits: 128, family: 'AES',
    description: 'OFB su AES-128. Pre-computa keystream, chiave corta.'),
  CipherInfo(name: 'camellia-128-cbc', displayName: 'Camellia-128-CBC', keyBits: 128, family: 'Camellia',
    description: 'Camellia 128 bit. Diversificazione algoritmica a chiave ridotta.'),
  CipherInfo(name: 'aria-128-cbc', displayName: 'ARIA-128-CBC', keyBits: 128, family: 'ARIA',
    description: 'ARIA 128 bit. Solo per ambienti con vincoli specifici.'),
  CipherInfo(name: 'aria-128-ctr', displayName: 'ARIA-128-CTR', keyBits: 128, family: 'ARIA',
    description: 'ARIA-128 contatore. Chiave minima consigliata.'),
];
