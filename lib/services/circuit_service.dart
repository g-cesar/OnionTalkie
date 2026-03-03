import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/constants/app_constants.dart';

/// A single hop in a Tor circuit.
class CircuitHop {
  /// Role in the circuit: Guard, Relay, Exit/Rendezvous.
  final String role;

  /// Relay nickname (from circuit-status response).
  final String name;

  /// Hex fingerprint of the relay.
  final String fingerprint;

  /// ISO 3166-1 alpha-2 country code (lowercase), e.g. "de", "us".
  /// Null if not resolved.
  final String? countryCode;

  /// IP address of the relay (if resolved via ns/id).
  final String? ip;

  const CircuitHop({
    required this.role,
    required this.name,
    required this.fingerprint,
    this.countryCode,
    this.ip,
  });

  /// Country flag as emoji. Falls back to globe emoji.
  String get flag {
    final cc = countryCode;
    if (cc == null || cc.length != 2) return '🌐';
    // Convert country code to regional indicator symbols.
    final a = cc.codeUnitAt(0) - 0x61 + 0x1F1E6;
    final b = cc.codeUnitAt(1) - 0x61 + 0x1F1E6;
    return String.fromCharCodes([a, b]);
  }

  /// Human-readable country name.
  String get countryName => CircuitService.getCountryName(countryCode ?? '??');
}

/// Service for querying Tor's ControlPort to get circuit information.
///
/// Connects to Tor's control port (default 9051) and retrieves the
/// current circuit path with relay names, IPs and countries.
class CircuitService {
  CircuitService._();

  /// Country codes → localised names.
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
    'es': 'Spagna',
    'it': 'Italia',
    'pt': 'Portogallo',
    'pl': 'Polonia',
    'hu': 'Ungheria',
    'dk': 'Danimarca',
    'ie': 'Irlanda',
    'nz': 'Nuova Zelanda',
    'in': 'India',
    'kr': 'Corea del Sud',
    'za': 'Sudafrica',
    'mx': 'Messico',
    'ar': 'Argentina',
    'cl': 'Cile',
    'co': 'Colombia',
    'hk': 'Hong Kong',
    'tw': 'Taiwan',
    'il': 'Israele',
    'ae': 'EAU',
    'tr': 'Turchia',
    'ee': 'Estonia',
    'lv': 'Lettonia',
    'sk': 'Slovacchia',
    'si': 'Slovenia',
    'hr': 'Croazia',
    'rs': 'Serbia',
    'be': 'Belgio',
  };

  // ─── Control port helper ──────────────────────────────────────

  /// Send a command and collect the response using the given [completer]
  /// pattern.  Caller must call [_resetCompleter] first.
  static late StringBuffer _buf;
  static late Completer<String> _comp;

  static void _resetCompleter() {
    _buf = StringBuffer();
    _comp = Completer<String>();
  }

  /// Send [command] through [socket], wait for a complete ControlPort
  /// response and return it.
  static Future<String> _sendCommand(Socket socket, String command) async {
    _resetCompleter();
    socket.write('$command\r\n');
    await socket.flush();
    return _comp.future.timeout(const Duration(seconds: 5));
  }

  /// Query Tor ControlPort for the current circuit hops.
  ///
  /// Returns a list of [CircuitHop] with name, fingerprint, IP and
  /// country code — or null if unavailable.
  static Future<List<CircuitHop>?> getCircuitHops() async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        '127.0.0.1',
        AppConstants.torControlPort,
      ).timeout(const Duration(seconds: 5));

      _resetCompleter();

      socket.listen(
        (data) {
          _buf.write(utf8.decode(data));
          final content = _buf.toString();
          // Tor ControlPort: a complete response always ends with
          // "250 OK\r\n" on success, or "4xx/5xx ...\r\n" on error.
          // Previous heuristic was triggering on intermediate 250- lines
          // of multi-line responses, causing premature completion.
          if (content.endsWith('250 OK\r\n') ||
              RegExp(r'[45]\d{2} .+\r\n$').hasMatch(content)) {
            if (!_comp.isCompleted) _comp.complete(content);
          }
        },
        onError: (e) {
          if (!_comp.isCompleted) _comp.completeError(e);
        },
        onDone: () {
          if (!_comp.isCompleted) _comp.complete(_buf.toString());
        },
      );

      // 1) Authenticate
      final auth = await _sendCommand(socket, 'AUTHENTICATE');
      if (!auth.contains('250 OK')) {
        debugPrint('CircuitService: Auth failed: $auth');
        return null;
      }

      // 2) Get circuit-status
      final circuitResp = await _sendCommand(socket, 'GETINFO circuit-status');
      final relays = _parseRelays(circuitResp);
      if (relays == null || relays.isEmpty) return null;

      // 3) Resolve IP + country per relay
      final hops = <CircuitHop>[];
      final roles = ['Guard', 'Relay', 'Exit/Rendezvous'];

      for (int i = 0; i < relays.length; i++) {
        final (fingerprint, name) = relays[i];
        final role = i < roles.length ? roles[i] : 'Hop ${i + 1}';

        // Try to get IP via ns/id
        String? ip;
        try {
          final nsResp =
              await _sendCommand(socket, 'GETINFO ns/id/$fingerprint');
          ip = _parseIpFromNs(nsResp);
        } catch (_) {}

        // Try to get country code from IP
        String? cc;
        if (ip != null) {
          try {
            final ccResp =
                await _sendCommand(socket, 'GETINFO ip-to-country/$ip');
            cc = _parseCountryCode(ccResp);
          } catch (_) {}
        }

        hops.add(CircuitHop(
          role: role,
          name: name,
          fingerprint: fingerprint,
          ip: ip,
          countryCode: cc,
        ));
      }

      return hops;
    } catch (e) {
      debugPrint('CircuitService: Failed to query circuit: $e');
      return null;
    } finally {
      try {
        socket?.write('QUIT\r\n');
        await socket?.flush();
      } catch (_) {}
      await socket?.close();
    }
  }

  /// Legacy string-based getter (kept for backward compat).
  static Future<String?> getCircuitPath() async {
    final hops = await getCircuitHops();
    if (hops == null || hops.isEmpty) return null;
    return hops.map((h) => '${h.flag} ${h.role}: ${h.name}').join(' → ');
  }

  // ─── Parsers ──────────────────────────────────────────────────

  /// Extract (fingerprint, name) pairs from the first BUILT circuit.
  static List<(String, String)>? _parseRelays(String response) {
    final lines = response.split('\n');
    String? bestCircuit;

    for (final line in lines) {
      if (line.contains('BUILT') && line.contains('\$')) {
        bestCircuit = line;
        break;
      }
    }

    if (bestCircuit == null) return null;

    final relayPattern = RegExp(r'\$([A-F0-9]+)(?:[~=](\w+))?');
    final matches = relayPattern.allMatches(bestCircuit).toList();

    if (matches.isEmpty) return null;

    return [
      for (final m in matches) (m.group(1)!, m.group(2) ?? 'Unknown'),
    ];
  }

  /// Extract the IP address from a `GETINFO ns/id/` response line.
  /// Typical line: `r RelayName <base64> <date> <time> 1.2.3.4 9001 0`
  static String? _parseIpFromNs(String response) {
    // The 'r' line contains: name identity date time ip orport dirport
    final rLine = response.split('\n').firstWhere(
          (l) => l.startsWith('r '),
          orElse: () => '',
        );
    if (rLine.isEmpty) return null;
    final parts = rLine.split(RegExp(r'\s+'));
    // r <name> <identity> <digest> <date> <time> <ip> <orport> <dirport>
    if (parts.length >= 7) {
      final candidate = parts[6];
      if (RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$')
          .hasMatch(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  /// Parse the country code from `GETINFO ip-to-country/<ip>`.
  /// Response: `250-ip-to-country/1.2.3.4=de\r\n250 OK\r\n`
  static String? _parseCountryCode(String response) {
    final match = RegExp(r'ip-to-country/[\d.]+=([\w]{2})').firstMatch(response);
    return match?.group(1)?.toLowerCase();
  }

  /// Get country name from code.
  static String getCountryName(String code) {
    return _countryNames[code.toLowerCase()] ?? code.toUpperCase();
  }
}
