import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/constants/app_constants.dart';

/// Probes whether a hidden-service address is reachable by attempting a
/// loopback SOCKS5 connection through the local Tor daemon.
///
/// A successful TCP connection (even if immediately closed) proves that the
/// hidden-service introduction points have been published to the Tor directory,
/// making the `.onion` address dialable from external peers.
class HiddenServiceProbe {
  HiddenServiceProbe._();

  // ── Single-shot check ───────────────────────────────────────────────────

  /// Try to reach [onionAddress] through SOCKS5. Returns `true` when the
  /// SOCKS5 tunnel is established (i.e. the HS is propagated and reachable).
  ///
  /// [timeout] controls how long to wait for the Tor circuit to the address.
  static Future<bool> checkPropagated(
    String onionAddress, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final host = onionAddress
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'^https?://'), '')
        .replaceAll(RegExp(r'/$'), '');

    Socket? socket;
    ServerSocket? tempServer;

    try {
      // 0. Bind a temporary server socket on the listen port.
      // If the app isn't actively listening yet (e.g. user is on home screen),
      // Tor will drop the incoming circuit because nothing is listening on 7777.
      // If this throws, the app's actual ConnectionService is already listening, which is fine.
      try {
        tempServer = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          AppConstants.listenPort,
        );
        tempServer.listen((s) => s.destroy());
      } catch (_) {}

      // 1. Connect to local SOCKS5 proxy
      socket = await Socket.connect(
        AppConstants.torSocksHost,
        AppConstants.torSocksPort,
        timeout: const Duration(seconds: 5),
      );

      socket.setOption(SocketOption.tcpNoDelay, true);

      // 2. Setup stream iterator (rather than raw .listen which can't be awaited safely inline)
      final iterator = StreamIterator(socket);

      Future<List<int>?> readBytes(int count) async {
        final buffer = <int>[];
        final stopwatch = Stopwatch()..start();
        while (buffer.length < count) {
          final remaining = timeout - stopwatch.elapsed;
          if (remaining.isNegative) return null;

          // Await next chunk with a timeout
          bool hasNext;
          try {
            hasNext = await iterator.moveNext().timeout(remaining);
          } on TimeoutException {
            return null;
          } catch (_) {
            return null;
          }

          if (!hasNext) return null;
          buffer.addAll(iterator.current);
        }

        // Note: this implementation reads exactly `count` items from the stream.
        // If the chunk contained more bytes than `count`, the extra bytes might be
        // dropped or cause desync in subsequent reads.
        // For SOCKS5, the greeting response is exactly 2 bytes in one chunk.
        // The connect response is typically exactly 10 bytes in one chunk.
        return buffer;
      }

      // 2. SOCKS5 greeting
      socket.add([0x05, 0x01, 0x00]);
      await socket.flush();

      final greeting = await readBytes(2);
      if (greeting == null || greeting[0] != 0x05 || greeting[1] != 0x00) {
        return false;
      }

      // 3. SOCKS5 CONNECT request to our own .onion
      final hostBytes = host.codeUnits;
      socket.add([
        0x05,
        0x01,
        0x00,
        0x03,
        hostBytes.length,
        ...hostBytes,
        (AppConstants.listenPort >> 8) & 0xFF,
        AppConstants.listenPort & 0xFF,
      ]);
      await socket.flush();

      // 4. Read response — only first 4 bytes matter
      final resp = await readBytes(4);
      if (resp == null) return false;

      // REP == 0x00 means success; anything else means failure
      final success = resp[0] == 0x05 && resp[1] == 0x00;
      debugPrint(
        'HiddenServiceProbe: $host → ${success ? "REACHABLE" : "UNREACHABLE (code ${resp[1]})"}',
      );
      return success;
    } catch (e) {
      debugPrint('HiddenServiceProbe: probe error for $host: $e');
      return false;
    } finally {
      try {
        socket?.destroy();
      } catch (_) {}
      try {
        await tempServer?.close();
      } catch (_) {}
    }
  }

  // ── Polling helper ──────────────────────────────────────────────────────

  /// Poll until [onionAddress] is reachable or [timeout] elapses.
  ///
  /// Calls [onProgress] with the attempt number each time a probe is made.
  /// Returns `true` if the HS became reachable before the timeout.
  static Future<bool> waitForPropagation(
    String onionAddress, {
    Duration timeout = const Duration(minutes: 5),
    Duration interval = const Duration(seconds: 15),
    void Function(int attempt)? onProgress,
  }) async {
    final deadline = DateTime.now().add(timeout);
    int attempt = 0;

    while (DateTime.now().isBefore(deadline)) {
      attempt++;
      onProgress?.call(attempt);

      final reachable = await checkPropagated(onionAddress);
      if (reachable) return true;

      // Wait before retrying (but bail early if deadline passed)
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) break;
      await Future.delayed(
        Duration(seconds: interval.inSeconds.clamp(0, remaining.inSeconds)),
      );
    }

    return false;
  }
}
