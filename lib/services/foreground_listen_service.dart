import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

// ─── Foreground Listen Service ────────────────────────────────────────
//
// Manages Android foreground service and iOS background task to keep the
// app alive while listening for incoming PTT calls over Tor.
//
// On Android: persistent notification + wake‑lock prevent the OS from
//             killing the process in background.
// On iOS:     background audio + VoIP entitlements keep execution alive.
// On Web:     no‑op (Service Workers handle background in the PWA).
// ──────────────────────────────────────────────────────────────────────

class ForegroundListenService {
  static bool _initialized = false;

  /// Initialise the foreground‑task system.  Call once from `main()`.
  static Future<void> init() async {
    if (kIsWeb || _initialized) return;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'tp_listen_channel',
        channelName: 'OnionTalkie – Ascolto',
        channelDescription:
            'Notifica persistente mentre OnionTalkie ascolta chiamate in arrivo.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        enableVibration: false,
        playSound: false,
        showWhen: false,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    _initialized = true;
    debugPrint('ForegroundListenService: initialised');
  }

  // ─── Start / Update / Stop ──────────────────────────────────────

  /// Start the foreground service with a "listening" notification.
  static Future<bool> startListening() async {
    if (kIsWeb) return false;

    try {
      // Request notification permission (Android 13+)
      final perm =
          await FlutterForegroundTask.checkNotificationPermission();
      if (perm != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }

      final result = await FlutterForegroundTask.startService(
        serviceId: 500,
        notificationTitle: 'OnionTalkie — In ascolto',
        notificationText: 'In attesa di chiamate in arrivo su Tor…',
        callback: _foregroundTaskCallback,
      );

      final ok = result is ServiceRequestSuccess;
      debugPrint('ForegroundListenService: startListening → ok=$ok');
      return ok;
    } catch (e) {
      debugPrint('ForegroundListenService: startListening error → $e');
      return false;
    }
  }

  /// Update notification to signal an incoming call.
  static Future<void> notifyIncomingCall() async {
    if (kIsWeb) return;
    try {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'OnionTalkie — Chiamata in arrivo!',
        notificationText: 'Tocca per rispondere.',
      );
      // Re-vibrate notification to draw attention
      await FlutterForegroundTask.updateService(
        notificationTitle: 'OnionTalkie — Chiamata in arrivo!',
        notificationText: 'Connessione in arrivo rilevata.',
      );
    } catch (e) {
      debugPrint('ForegroundListenService: notifyIncomingCall error → $e');
    }
  }

  /// Update notification to signal an active call.
  static Future<void> notifyActiveCall() async {
    if (kIsWeb) return;
    try {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'OnionTalkie — Chiamata attiva',
        notificationText: 'Comunicazione cifrata in corso.',
      );
    } catch (e) {
      debugPrint('ForegroundListenService: notifyActiveCall error → $e');
    }
  }

  /// Stop the foreground service entirely.
  static Future<void> stop() async {
    if (kIsWeb) return;
    try {
      await FlutterForegroundTask.stopService();
      debugPrint('ForegroundListenService: stopped');
    } catch (e) {
      debugPrint('ForegroundListenService: stop error → $e');
    }
  }

  /// Whether the foreground service is currently running.
  static Future<bool> get isRunning async {
    if (kIsWeb) return false;
    return FlutterForegroundTask.isRunningService;
  }
}

// ─── Foreground task callback & handler ──────────────────────────────
//
// The callback *must* be a top‑level (or static) function annotated with
// @pragma('vm:entry-point') so that the native side can spawn it.
//
// All real work (Tor, calls) happens in the main Dart isolate.  The task
// handler here is intentionally a no‑op — its only purpose is to satisfy
// the API requirement and keep the service alive.
// ─────────────────────────────────────────────────────────────────────

@pragma('vm:entry-point')
void _foregroundTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_ListenTaskHandler());
}

class _ListenTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('_ListenTaskHandler: onStart (${starter.name})');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // eventAction is `nothing()` — this is never called.
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    debugPrint('_ListenTaskHandler: onDestroy');
  }
}
