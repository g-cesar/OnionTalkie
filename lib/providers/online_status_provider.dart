import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'tor_provider.dart';

/// Cached result of a single online-status check.
class _CachedResult {
  final bool isOnline;
  final DateTime fetchedAt;
  _CachedResult(this.isOnline) : fetchedAt = DateTime.now();

  bool get isExpired =>
      DateTime.now().difference(fetchedAt) > const Duration(seconds: 60);
}

final _cache = <String, _CachedResult>{};

/// AsyncNotifier that checks whether a given .onion address is reachable.
///
/// Results are cached for 60 seconds per address to avoid hammering Tor
/// with constant connection probes.
class OnlineStatusNotifier
    extends AutoDisposeFamilyAsyncNotifier<bool, String> {
  Timer? _timer;

  @override
  Future<bool> build(String onionAddress) async {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 45), (_) {
      refresh();
    });
    ref.onDispose(() => _timer?.cancel());

    return _fetchStatus(onionAddress);
  }

  Future<bool> _fetchStatus(String address) async {
    // Return cached result if still fresh
    final cached = _cache[address];
    if (cached != null && !cached.isExpired) {
      return cached.isOnline;
    }

    final torService = ref.read(torServiceProvider);
    final isOnline = await torService.isPeerOnline(address);

    _cache[address] = _CachedResult(isOnline);
    return isOnline;
  }

  /// Force a fresh check, ignoring the cache.
  Future<void> refresh() async {
    final address = arg;
    _cache.remove(address);
    // Perform fetch without setting loading state to avoid UI flicker during periodic refresh
    final result = await _fetchStatus(address);
    state = AsyncValue.data(result);
  }
}

/// Provider family.  Usage: `ref.watch(onlineStatusProvider('xxxxx.onion'))`
final onlineStatusProvider = AsyncNotifierProvider.autoDispose
    .family<OnlineStatusNotifier, bool, String>(OnlineStatusNotifier.new);
