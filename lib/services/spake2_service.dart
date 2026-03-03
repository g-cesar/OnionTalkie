import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto_lib;
import 'package:pointycastle/export.dart';

// ─── SPAKE2 Password-Authenticated Key Exchange ───────────────────────
//
// Implements SPAKE2 over P-256 (secp256r1) per RFC 9382.
//
// Both parties share a low-entropy passphrase.  The protocol derives a
// strong 256-bit session key on each call WITHOUT ever transmitting the
// passphrase.
//
// Advantages over raw PBKDF2 key derivation:
//   • Fresh session key per call (forward secrecy)
//   • Immune to offline dictionary attacks on captured traffic
//   • Zero-knowledge: an eavesdropper learns nothing about the passphrase
//
// ──────────────────────────────────────────────────────────────────────

class Spake2Session {
  // ── P-256 curve parameters ─────────────────────────────────────

  static final ECDomainParameters _curve = ECCurve_secp256r1();

  /// RFC 9382 "nothing up my sleeve" blind points for P-256.
  // ignore: non_constant_identifier_names
  static final ECPoint _M = _curve.curve.decodePoint(Uint8List.fromList(
    _hexToBytes(
        '02886e2f97ace46e55ba9dd7242579f2993b64e16ef3dcab95afd497333d8fa12f'),
  ))!;

  // ignore: non_constant_identifier_names
  static final ECPoint _N = _curve.curve.decodePoint(Uint8List.fromList(
    _hexToBytes(
        '03d8bbd6c639c62937b04d997f38c3770719c629d7014d49a24b4f98baa1292b49'),
  ))!;

  // ── Instance state ─────────────────────────────────────────────

  final bool _isInitiator;
  final BigInt _w; // password scalar (mod n)
  final BigInt _scalar; // random ephemeral private scalar
  final ECPoint _publicValue; // our blinded public value
  ECPoint? _remotePublicValue; // peer's blinded public value
  Uint8List? _sessionKey; // derived 256-bit session key
  Uint8List? _confirmKey; // key for confirmation MACs

  // ── Constructors ───────────────────────────────────────────────

  /// Internal constructor that avoids double computation.
  Spake2Session._internal({
    required bool isInitiator,
    required BigInt w,
    required BigInt scalar,
    required ECPoint publicValue,
  })  : _isInitiator = isInitiator,
        _w = w,
        _scalar = scalar,
        _publicValue = publicValue;

  /// Create a SPAKE2 session as the **initiator** (caller).
  factory Spake2Session.initiator(String passphrase) {
    final w = _deriveW(passphrase);
    final scalar = _generateRandomScalar();
    final pub = _computePublicValue(true, w, scalar);
    return Spake2Session._internal(
      isInitiator: true,
      w: w,
      scalar: scalar,
      publicValue: pub,
    );
  }

  /// Create a SPAKE2 session as the **responder** (listener).
  factory Spake2Session.responder(String passphrase) {
    final w = _deriveW(passphrase);
    final scalar = _generateRandomScalar();
    final pub = _computePublicValue(false, w, scalar);
    return Spake2Session._internal(
      isInitiator: false,
      w: w,
      scalar: scalar,
      publicValue: pub,
    );
  }

  // ── Public API ─────────────────────────────────────────────────

  /// Our blinded public value, base64-encoded (to send to the peer).
  String get publicValueBase64 =>
      base64Encode(_publicValue.getEncoded(true)); // compressed

  /// Whether the handshake has completed (session key derived).
  bool get isComplete => _sessionKey != null;

  /// The derived 256-bit session key. Throws if handshake is not complete.
  Uint8List get sessionKey {
    if (_sessionKey == null) {
      throw StateError('SPAKE2 handshake not complete');
    }
    return _sessionKey!;
  }

  /// Process the peer's blinded public value and derive the session key.
  ///
  /// After this call, [isComplete] becomes `true` and [sessionKey] is
  /// available.
  void processRemotePublicValue(String base64Value) {
    final bytes = base64Decode(base64Value);
    _remotePublicValue = _curve.curve.decodePoint(bytes);

    if (_remotePublicValue == null) {
      throw ArgumentError('Invalid SPAKE2 public value');
    }

    // Unblind the remote value and compute the shared secret point.
    //
    // Initiator: K = scalar · (Y* − w·N)
    // Responder: K = scalar · (X* − w·M)
    final unblindPoint = _isInitiator ? _N : _M; // opposite blind
    final wBlindPoint = unblindPoint * _w;
    if (wBlindPoint == null) {
      throw StateError('SPAKE2: blind point multiplication failed');
    }

    final negWBlind = -wBlindPoint; // negate the blind
    final unblinded = _remotePublicValue! + negWBlind;
    if (unblinded == null) {
      throw StateError('SPAKE2: unblinding failed');
    }

    final sharedSecret = unblinded * _scalar;
    if (sharedSecret == null || sharedSecret.isInfinity) {
      throw StateError('SPAKE2: derived point is at infinity');
    }

    _deriveKeys(sharedSecret);
  }

  /// Generate our key-confirmation MAC.
  ///
  /// Must be called after [processRemotePublicValue].
  String generateConfirmation() {
    if (_confirmKey == null || _remotePublicValue == null) {
      throw StateError(
          'Must process remote value before generating confirmation');
    }

    final role = _isInitiator ? 'initiator' : 'responder';
    final myPub = _publicValue.getEncoded(true);
    final remotePub = _remotePublicValue!.getEncoded(true);

    final data = <int>[...utf8.encode(role), ...myPub, ...remotePub];
    final hmac = crypto_lib.Hmac(crypto_lib.sha256, _confirmKey!);
    return hmac.convert(data).toString();
  }

  /// Verify the peer's key-confirmation MAC.
  ///
  /// Returns `true` if both parties derived the same session key
  /// (i.e. both know the same passphrase). Must be called after
  /// [processRemotePublicValue].
  bool verifyConfirmation(String remoteConfirmHex) {
    if (_confirmKey == null || _remotePublicValue == null) return false;

    // Reconstruct what the OTHER party should have generated.
    final role = _isInitiator ? 'responder' : 'initiator';
    final remotePub = _remotePublicValue!.getEncoded(true);
    final myPub = _publicValue.getEncoded(true);

    final data = <int>[...utf8.encode(role), ...remotePub, ...myPub];
    final hmac = crypto_lib.Hmac(crypto_lib.sha256, _confirmKey!);
    final expected = hmac.convert(data).toString();

    // Constant-time comparison to prevent timing attacks.
    if (expected.length != remoteConfirmHex.length) return false;
    int result = 0;
    for (int i = 0; i < expected.length; i++) {
      result |= expected.codeUnitAt(i) ^ remoteConfirmHex.codeUnitAt(i);
    }
    return result == 0;
  }

  // ── Key derivation ─────────────────────────────────────────────

  /// Derive session key (32 B) + confirmation key (32 B) from [sharedPoint].
  void _deriveKeys(ECPoint sharedPoint) {
    final xBytes = _bigIntToBytes(sharedPoint.x!.toBigInteger()!, 32);

    // Salt = initiatorPub ‖ responderPub (same order on both sides).
    final initiatorPub = _isInitiator
        ? _publicValue.getEncoded(true)
        : _remotePublicValue!.getEncoded(true);
    final responderPub = _isInitiator
        ? _remotePublicValue!.getEncoded(true)
        : _publicValue.getEncoded(true);

    final salt = Uint8List.fromList([...initiatorPub, ...responderPub]);

    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, 10000, 64));

    final derived = pbkdf2.process(Uint8List.fromList(xBytes));
    _sessionKey = Uint8List.fromList(derived.sublist(0, 32));
    _confirmKey = Uint8List.fromList(derived.sublist(32, 64));
  }

  // ── Static helpers ─────────────────────────────────────────────

  /// Compute the blinded public value: scalar·G + w·blind.
  static ECPoint _computePublicValue(
      bool isInitiator, BigInt w, BigInt scalar) {
    final blindPoint = isInitiator ? _M : _N;
    final xG = _curve.G * scalar;
    final wBlind = blindPoint * w;
    if (xG == null || wBlind == null) {
      throw StateError('SPAKE2: EC multiplication returned null');
    }
    final result = xG + wBlind;
    if (result == null) {
      throw StateError('SPAKE2: EC addition returned null');
    }
    return result;
  }

  /// Derive password scalar w from passphrase via PBKDF2, reduced mod n.
  static BigInt _deriveW(String passphrase) {
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(
        Uint8List.fromList(utf8.encode('SPAKE2-w-derivation-v1')),
        100000,
        32,
      ));

    final wBytes =
        pbkdf2.process(Uint8List.fromList(utf8.encode(passphrase)));
    return _bytesToBigInt(wBytes) % _curve.n;
  }

  /// Generate a cryptographically random scalar in [1, n−1].
  static BigInt _generateRandomScalar() {
    final rng = FortunaRandom();
    rng.seed(KeyParameter(_secureRandomBytes(32)));

    final n = _curve.n;
    final byteLen = (n.bitLength + 7) >> 3;
    while (true) {
      final s = _bytesToBigInt(rng.nextBytes(byteLen)) % n;
      if (s > BigInt.zero) return s;
    }
  }

  // ── Byte / BigInt utilities ────────────────────────────────────

  static List<int> _hexToBytes(String hex) {
    final result = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      result.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return result;
  }

  static BigInt _bytesToBigInt(Uint8List bytes) {
    var result = BigInt.zero;
    for (final b in bytes) {
      result = (result << 8) | BigInt.from(b);
    }
    return result;
  }

  static List<int> _bigIntToBytes(BigInt value, int length) {
    final result = List<int>.filled(length, 0);
    var v = value;
    for (var i = length - 1; i >= 0; i--) {
      result[i] = (v & BigInt.from(0xFF)).toInt();
      v >>= 8;
    }
    return result;
  }

  static Uint8List _secureRandomBytes(int length) {
    final rng = Random.secure();
    return Uint8List.fromList(
        List.generate(length, (_) => rng.nextInt(256)));
  }
}
