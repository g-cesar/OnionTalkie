import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/constants/app_constants.dart';

/// Service for querying Tor's ControlPort to get circuit information.
///
/// Connects to Tor's control port (default 9051) and retrieves the
/// current circuit path with relay names and countries.
class CircuitService {
  CircuitService._();

  /// Country codes for common relay locations.
  static const Map<String, String> _countryNames = {
    'us': 'USA',
    'de': 'Germania',
    'fr': 'Francia',
    'nl': 'Paesi Bassi',
    'gb': 'Regno Unito',
    'ca': 'Canada',
    'ch': 'Svizzera',
    'se': 'Svezia',
    'no': 'Norvegia',
    'fi': 'Finlandia',
    'at': 'Austria',
    'ro': 'Romania',
    'is': 'Islanda',
    'lu': 'Lussemburgo',
    'cz': 'Rep. Ceca',
    'lt': 'Lituania',
    'md': 'Moldavia',
    'bg': 'Bulgaria',
    'ua': 'Ucraina',
    'ru': 'Russia',
    'jp': 'Giappone',
    'sg': 'Singapore',
    'au': 'Australia',
    'br': 'Brasile',
  };

  /// Query Tor ControlPort for the current circuit path.
  ///
  /// Returns a human-readable circuit path string like:
  /// "Guard (DE) → Relay (NL) → Rendezvous (CH)"
  ///
  /// Returns null if circuit info is unavailable.
  static Future<String?> getCircuitPath() async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        '127.0.0.1',
        AppConstants.torControlPort,
      ).timeout(const Duration(seconds: 5));

      final completer = Completer<String>();
      final buffer = StringBuffer();

      socket.listen(
        (data) {
          buffer.write(utf8.decode(data));
          final content = buffer.toString();
          if (content.contains('\r\n.\r\n') || content.contains('250 OK')) {
            if (!completer.isCompleted) completer.complete(content);
          }
        },
        onError: (e) {
          if (!completer.isCompleted) completer.completeError(e);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete(buffer.toString());
        },
      );

      // Authenticate (no password by default with CookieAuthentication disabled)
      socket.write('AUTHENTICATE\r\n');
      await socket.flush();

      // Wait for auth response
      final authResponse = await completer.future.timeout(
        const Duration(seconds: 5),
      );

      if (!authResponse.contains('250 OK')) {
        debugPrint('CircuitService: Auth failed: $authResponse');
        return null;
      }

      // Request circuit status
      final circuitCompleter = Completer<String>();
      final circuitBuffer = StringBuffer();

      socket.listen(
        (data) {
          circuitBuffer.write(utf8.decode(data));
          final content = circuitBuffer.toString();
          if (content.contains('\r\n.\r\n') || content.contains('250 OK')) {
            if (!circuitCompleter.isCompleted) {
              circuitCompleter.complete(content);
            }
          }
        },
        onError: (e) {
          if (!circuitCompleter.isCompleted) circuitCompleter.completeError(e);
        },
      );

      socket.write('GETINFO circuit-status\r\n');
      await socket.flush();

      final circuitResponse = await circuitCompleter.future.timeout(
        const Duration(seconds: 5),
      );

      return _parseCircuitStatus(circuitResponse);
    } catch (e) {
      debugPrint('CircuitService: Failed to query circuit: $e');
      return null;
    } finally {
      await socket?.close();
    }
  }

  /// Parse Tor's circuit-status response into a readable format.
  static String? _parseCircuitStatus(String response) {
    // Find BUILT circuits (established)
    final lines = response.split('\n');
    String? bestCircuit;

    for (final line in lines) {
      if (line.contains('BUILT') && line.contains('\$')) {
        bestCircuit = line;
        break; // Use the first BUILT circuit
      }
    }

    if (bestCircuit == null) return null;

    // Extract relay fingerprints and names
    // Format: <circuitId> BUILT $FINGERPRINT~Name,$FINGERPRINT~Name,...
    final relayPattern = RegExp(r'\$([A-F0-9]+)(?:~(\w+))?');
    final matches = relayPattern.allMatches(bestCircuit).toList();

    if (matches.isEmpty) return null;

    final hops = <String>[];
    final roles = ['Guard', 'Relay', 'Exit/Rendezvous'];

    for (int i = 0; i < matches.length; i++) {
      final name = matches[i].group(2) ?? 'Unknown';
      final role = i < roles.length ? roles[i] : 'Hop ${i + 1}';
      hops.add('$role: $name');
    }

    return hops.join(' → ');
  }

  /// Get country name from code.
  static String getCountryName(String code) {
    return _countryNames[code.toLowerCase()] ?? code.toUpperCase();
  }
}
