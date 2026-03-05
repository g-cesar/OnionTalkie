import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/router/app_router.dart';
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

/// Provider that determines if contact polling should be active based on current path.
final contactPollingEnabledProvider = Provider<bool>((ref) {
  final path = ref.watch(currentPathProvider);
  // Only enable polling on Contacts and Dial screens.
  // We check if the path starts with these to account for nested routes (like /contacts/edit).
  return path.startsWith('/contacts') || path == '/dial';
});

/// AsyncNotifier that checks whether a given .onion address is reachable.
///
/// Results are cached for 60 seconds per address to avoid hammering Tor
/// with constant connection probes.
class OnlineStatusNotifier
    extends AutoDisposeFamilyAsyncNotifier<bool, String> {
  Timer? _timer;

  @override
  Future<bool> build(String onionAddress) async {
    final pollingEnabled = ref.watch(contactPollingEnabledProvider);

    if (!pollingEnabled) {
      _stopPolling();
      return false;
    }

    // If we just entered a polling-enabled screen, clear the cache for this address
    // to ensure a fresh "restart" as requested.
    _cache.remove(onionAddress);

    _startPolling();
    ref.onDispose(_stopPolling);

    return _fetchStatus(onionAddress);
  }

  void _startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 45), (_) {
      refresh();
    });
  }

  void _stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  Future<bool> _fetchStatus(String address) async {
    // Return cached result if still fresh
    final cached = _cache[address];
    if (cached != null && !cached.isExpired) {
      return cached.isOnline;
    }

    // Immediate check: if polling was disabled while we were waiting or before starting, bail.
    if (!ref.read(contactPollingEnabledProvider)) return false;

    final torService = ref.read(torServiceProvider);
    final isOnline = await torService.isPeerOnline(address);

    // Double check polling state after async operation to avoid interfering
    // if the user navigated away during the SOCKS probe.
    if (!ref.read(contactPollingEnabledProvider)) return false;

    _cache[address] = _CachedResult(isOnline);
    return isOnline;
  }

  /// Force a fresh check, ignoring the cache.
  Future<void> refresh() async {
    final address = arg;
    _cache.remove(address);
    // Perform fetch without setting loading state to avoid UI flicker during periodic refresh
    final result = await _fetchStatus(address);
    if (ref.read(contactPollingEnabledProvider)) {
      state = AsyncValue.data(result);
    }
  }
}

/// Provider family.  Usage: `ref.watch(onlineStatusProvider('xxxxx.onion'))`
final onlineStatusProvider = AsyncNotifierProvider.autoDispose
    .family<OnlineStatusNotifier, bool, String>(OnlineStatusNotifier.new);
