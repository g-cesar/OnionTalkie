import 'dart:convert';

/// A contact in the address book.
///
/// Each contact holds its own [sharedSecret] so that different peers
/// can use different keys. The [onionAddress] is the last-known hidden
/// service address of this contact.
class Contact {
  /// Unique identifier (UUID v4).
  final String id;

  /// Local alias chosen by the user.
  final String alias;

  /// The peer's .onion address.
  final String onionAddress;

  /// Per-contact shared secret (may be empty if not yet exchanged).
  final String sharedSecret;

  /// When this contact was first created.
  final DateTime createdAt;

  /// When we last communicated successfully.
  final DateTime? lastContactedAt;

  /// Previous onion address (if the peer changed it).
  /// Used to detect address changes.
  final String? previousOnionAddress;

  /// Whether the peer's onion address has changed since our last contact
  /// and the user hasn't acknowledged it yet.
  final bool addressChanged;

  /// Availability information (e.g. "Online every 10 minutes").
  final String availability;

  const Contact({
    required this.id,
    required this.alias,
    required this.onionAddress,
    this.sharedSecret = '',
    required this.createdAt,
    this.lastContactedAt,
    this.previousOnionAddress,
    this.addressChanged = false,
    this.availability = '',
  });

  Contact copyWith({
    String? alias,
    String? onionAddress,
    String? sharedSecret,
    DateTime? lastContactedAt,
    String? previousOnionAddress,
    bool? addressChanged,
    String? availability,
  }) {
    return Contact(
      id: id,
      alias: alias ?? this.alias,
      onionAddress: onionAddress ?? this.onionAddress,
      sharedSecret: sharedSecret ?? this.sharedSecret,
      createdAt: createdAt,
      lastContactedAt: lastContactedAt ?? this.lastContactedAt,
      previousOnionAddress: previousOnionAddress ?? this.previousOnionAddress,
      addressChanged: addressChanged ?? this.addressChanged,
      availability: availability ?? this.availability,
    );
  }

  /// Whether a usable shared secret is configured for this contact.
  bool get hasSecret => sharedSecret.isNotEmpty;

  /// Short representation of the onion address for display.
  String get shortOnion {
    final addr = onionAddress.replaceAll('.onion', '');
    if (addr.length > 12) {
      return '${addr.substring(0, 6)}…${addr.substring(addr.length - 6)}.onion';
    }
    return onionAddress;
  }

  // ── Serialisation ──────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    'id': id,
    'alias': alias,
    'onionAddress': onionAddress,
    'sharedSecret': sharedSecret,
    'createdAt': createdAt.toIso8601String(),
    'lastContactedAt': lastContactedAt?.toIso8601String(),
    'previousOnionAddress': previousOnionAddress,
    'addressChanged': addressChanged,
    'availability': availability,
  };

  factory Contact.fromJson(Map<String, dynamic> json) => Contact(
    id: json['id'] as String,
    alias: json['alias'] as String,
    onionAddress: json['onionAddress'] as String,
    sharedSecret: (json['sharedSecret'] as String?) ?? '',
    createdAt: DateTime.parse(json['createdAt'] as String),
    lastContactedAt:
        json['lastContactedAt'] != null
            ? DateTime.parse(json['lastContactedAt'] as String)
            : null,
    previousOnionAddress: json['previousOnionAddress'] as String?,
    addressChanged: (json['addressChanged'] as bool?) ?? false,
    availability: (json['availability'] as String?) ?? '',
  );

  String toJsonString() => jsonEncode(toJson());
  factory Contact.fromJsonString(String s) =>
      Contact.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
