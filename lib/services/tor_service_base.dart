import 'dart:async';

import 'package:url_launcher/url_launcher.dart';

import '../models/tor_status.dart';

/// Information about a Tor installation option.
class TorInstallOption {
  final String name;
  final String description;
  final String? url;
  final String? command;
  final IconType iconType;

  const TorInstallOption({
    required this.name,
    required this.description,
    this.url,
    this.command,
    this.iconType = IconType.download,
  });
}

enum IconType { download, store, terminal, web }

/// Abstract Tor service interface (platform-agnostic).
abstract class TorServiceBase {
  Stream<TorStatus> get statusStream;
  TorStatus get currentStatus;

  /// Check if a Tor binary / relay is available.
  Future<bool> isTorInstalled();

  /// Return platform-specific installation options for the user.
  List<TorInstallOption> getInstallOptions();

  /// Open an install option URL in the browser / store.
  Future<bool> openInstallOption(TorInstallOption option) async {
    if (option.url == null) return false;
    final uri = Uri.parse(option.url!);
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Start the Tor process / connect to relay.
  Future<void> start({bool snowflake = false, String excludeNodes = ''});

  /// Stop the Tor process / disconnect from relay.
  Future<void> stop();

  /// Restart Tor.
  Future<void> restart({bool snowflake = false, String excludeNodes = ''});

  /// Rotate the onion address by deleting the hidden service keys.
  Future<void> rotateOnionAddress();

  /// Get the current onion address.
  Future<String?> getOnionAddress();

  /// Get the current Tor circuit path.
  ///
  /// Returns a human-readable string like "Guard: Name → Relay: Name → Exit: Name"
  /// or null if unavailable.
  Future<String?> getCircuitPath();

  void dispose();
}
