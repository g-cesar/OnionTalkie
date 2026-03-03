import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/theme/app_theme.dart';
import '../models/call_state.dart';
import '../models/chat_message.dart';
import '../providers/call_provider.dart';
import '../providers/contacts_provider.dart';
import '../providers/providers.dart';
import '../providers/settings_provider.dart';
import '../widgets/call_header.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/connecting_animation.dart';
import '../widgets/connection_steps_widget.dart';
import '../widgets/incoming_call_animation.dart';
import '../widgets/ptt_button.dart';

class CallScreen extends ConsumerStatefulWidget {
  final String? remoteAddress;
  final String? contactId;

  const CallScreen({super.key, this.remoteAddress, this.contactId});

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _durationTimer;
  DateTime? _connectingStartTime;

  @override
  void initState() {
    super.initState();
    try { WakelockPlus.enable(); } catch (_) {}
    // Defer call initialization to after the widget tree is built,
    // otherwise reset() would modify providers during the build phase.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _initCall();
    });
  }

  Future<void> _initCall() async {
    final callNotifier = ref.read(callProvider.notifier);
    callNotifier.reset();
    setState(() => _connectingStartTime = DateTime.now());

    // If calling a contact, load their shared secret.
    if (widget.contactId != null) {
      final contact =
          ref.read(contactsProvider.notifier).findById(widget.contactId!);
      if (contact != null && contact.hasSecret) {
        ref.read(encryptionServiceProvider).setSharedSecret(contact.sharedSecret);
      }
    }

    if (widget.remoteAddress != null && widget.remoteAddress!.isNotEmpty) {
      // Outgoing call
      await callNotifier.call(widget.remoteAddress!, contactId: widget.contactId);
    } else {
      // Incoming — listen mode
      await callNotifier.listenForCalls();
    }

    // Start duration timer
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    try { WakelockPlus.disable(); } catch (_) {}
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final callState = ref.watch(callProvider);
    final messages = ref.watch(chatMessagesProvider);
    ref.watch(settingsProvider);
    final theme = Theme.of(context);

    // Auto-scroll on new messages
    ref.listen<List<ChatMessage>>(chatMessagesProvider, (prev, next) {
      if (next.length > (prev?.length ?? 0)) {
        _scrollToBottom();
      }
    });

    // Handle ringing → vibrate
    ref.listen<CallState>(callProvider, (prev, next) {
      if (next.phase == CallPhase.ringing && prev?.phase != CallPhase.ringing) {
        HapticFeedback.vibrate();
      }
    });

    // Handle call ended
    ref.listen<CallState>(callProvider, (prev, next) {
      if (next.phase == CallPhase.ended && prev?.phase != CallPhase.ended) {
        _showCallEndedDialog();
      }
    });

    return PopScope(
      canPop: callState.phase != CallPhase.active,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _showHangUpConfirmation();
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              // Call Header
              CallHeader(callState: callState),

              // Main Content
              Expanded(
                child: _buildMainContent(callState, messages, theme),
              ),

              // Bottom Controls
              if (callState.phase == CallPhase.active)
                _buildBottomControls(callState, theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainContent(
    CallState callState,
    List<ChatMessage> messages,
    ThemeData theme,
  ) {
    if (callState.phase == CallPhase.connecting) {
      // Determine if buttons should pulse (connection taking too long).
      final elapsed = _connectingStartTime != null
          ? DateTime.now().difference(_connectingStartTime!).inSeconds
          : 0;
      // Outgoing: 15s covers first retry cycle; listening: 30s.
      final threshold = callState.isIncoming ? 30 : 15;
      final shouldPulse = elapsed >= threshold;

      return Column(
        children: [
          Expanded(
            child: ConnectingAnimation(
              isIncoming: callState.isIncoming,
              address: callState.remoteAddress,
            ),
          ),
          ConnectionStepsWidget(
            completedSteps: callState.completedSteps,
            isIncoming: callState.isIncoming,
          ),
          const SizedBox(height: 12),
          if (shouldPulse)
            _TimeoutAlertBox(),
          _ConnectingActions(
            pulsing: shouldPulse,
            onRetry: _retry,
            onTerminate: _terminate,
          ),
          const SizedBox(height: 16),
        ],
      );
    }

    if (callState.phase == CallPhase.ringing) {
      // Look up contact name if available
      String? contactName;
      if (callState.remoteAddress != null) {
        try {
          final contact = ref
              .read(contactsProvider.notifier)
              .findByOnion(callState.remoteAddress!);
          contactName = contact?.alias;
        } catch (_) {}
      }

      return Column(
        children: [
          ConnectionStepsWidget(
            completedSteps: callState.completedSteps,
            isIncoming: callState.isIncoming,
          ),
          Expanded(
            child: IncomingCallAnimation(
              address: callState.remoteAddress,
              contactName: contactName,
              autoAcceptSeconds: 3,
              onAccept: () {
                ref.read(callProvider.notifier).acceptIncomingCall();
              },
              onReject: () {
                ref.read(callProvider.notifier).hangUp();
                context.pop();
              },
            ),
          ),
        ],
      );
    }

    if (callState.phase == CallPhase.error) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
              const SizedBox(height: 16),
              Text(
                'Errore di connessione',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                callState.errorMessage ?? 'Errore sconosciuto',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Torna al menu'),
              ),
            ],
          ),
        ),
      );
    }

    if (callState.phase == CallPhase.ended) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.call_end, size: 64, color: AppColors.textSecondary),
            SizedBox(height: 16),
            Text('Chiamata terminata'),
          ],
        ),
      );
    }

    // Active call — show message list
    if (messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.record_voice_over,
              size: 64,
              color: theme.colorScheme.primary.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'Tieni premuto il pulsante\nper parlare in tempo reale',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: messages.length,
      itemBuilder: (context, index) => ChatBubble(
        message: messages[index],
      ),
    );
  }

  Widget _buildBottomControls(CallState callState, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Stats row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildStat(
                theme,
                Icons.upload,
                _formatBytes(callState.sentBytes),
                'Inviati',
              ),
              _buildStat(
                theme,
                Icons.download,
                _formatBytes(callState.receivedBytes),
                'Ricevuti',
              ),
              _buildStat(
                theme,
                Icons.timer,
                _formatDuration(callState.callDuration),
                'Durata',
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Remote transmitting indicator
          if (callState.remotePttState == RemotePttState.recording)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.hearing,
                    size: 16,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'L\'altro sta parlando...',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

          // PTT button and controls row
          Row(
            children: [
              // Text message button
              IconButton.filled(
                onPressed: () => _showTextInput(),
                icon: const Icon(Icons.message),
                style: IconButton.styleFrom(
                  backgroundColor: theme.colorScheme.secondaryContainer,
                  foregroundColor: theme.colorScheme.onSecondaryContainer,
                ),
              ),

              const SizedBox(width: 12),

              // PTT Button — center
              Expanded(
                child: PttButton(
                  isRecording: callState.isRecording,
                  enabled: callState.remotePttState != RemotePttState.recording,
                  onPttStart: () => ref.read(callProvider.notifier).startRecording(),
                  onPttStop: () => ref.read(callProvider.notifier).stopRecording(),
                ),
              ),

              const SizedBox(width: 12),

              // Hang up button
              IconButton.filled(
                onPressed: () => _showHangUpConfirmation(),
                icon: const Icon(Icons.call_end),
                style: IconButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  foregroundColor: theme.colorScheme.onError,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStat(ThemeData theme, IconData icon, String value, String label) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  void _showTextInput() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _textController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Scrivi un messaggio cifrato...',
                ),
                onSubmitted: (text) => _sendText(text),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: () => _sendText(_textController.text),
              icon: const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }

  void _sendText(String text) {
    if (text.trim().isNotEmpty) {
      ref.read(callProvider.notifier).sendTextMessage(text.trim());
      _textController.clear();
      Navigator.pop(context);
    }
  }

  void _retry() {
    final callNotifier = ref.read(callProvider.notifier);
    callNotifier.reset();
    setState(() => _connectingStartTime = DateTime.now());

    // Reload shared secret if needed.
    if (widget.contactId != null) {
      final contact =
          ref.read(contactsProvider.notifier).findById(widget.contactId!);
      if (contact != null && contact.hasSecret) {
        ref.read(encryptionServiceProvider).setSharedSecret(contact.sharedSecret);
      }
    }

    if (widget.remoteAddress != null && widget.remoteAddress!.isNotEmpty) {
      callNotifier.call(widget.remoteAddress!, contactId: widget.contactId);
    } else {
      callNotifier.listenForCalls();
    }
  }

  void _terminate() {
    ref.read(callProvider.notifier).reset();
    context.pop();
  }

  void _showHangUpConfirmation() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Termina chiamata'),
        content: const Text('Vuoi terminare la chiamata?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(callProvider.notifier).hangUp();
              context.pop();
            },
            child: const Text('Termina'),
          ),
        ],
      ),
    );
  }

  void _showCallEndedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Chiamata terminata'),
        content: const Text('L\'altra parte ha riagganciato.'),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.pop();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return '0:00';
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

// ─── Connecting-phase action buttons ────────────────────────────

/// Row with RIPROVA and TERMINA buttons shown during connecting phase.
class _ConnectingActions extends StatelessWidget {
  final bool pulsing;
  final VoidCallback onRetry;
  final VoidCallback onTerminate;

  const _ConnectingActions({
    required this.pulsing,
    required this.onRetry,
    required this.onTerminate,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Expanded(
            child: _PulsingActionButton(
              onPressed: onRetry,
              icon: Icons.refresh_rounded,
              label: 'RIPROVA',
              color: AppColors.yellow,
              pulsing: pulsing,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _PulsingActionButton(
              onPressed: onTerminate,
              icon: Icons.close_rounded,
              label: 'TERMINA',
              color: AppColors.coral,
              pulsing: false,
            ),
          ),
        ],
      ),
    );
  }
}

/// A [FilledButton] that pulses (scale + glow) when [pulsing] is true,
/// drawing the user's attention when the connection is taking too long.
class _PulsingActionButton extends StatefulWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final String label;
  final Color color;
  final bool pulsing;

  const _PulsingActionButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    required this.color,
    this.pulsing = false,
  });

  @override
  State<_PulsingActionButton> createState() => _PulsingActionButtonState();
}

class _PulsingActionButtonState extends State<_PulsingActionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.pulsing) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _PulsingActionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulsing && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.pulsing && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = widget.pulsing ? _controller.value : 0.0;
        return Transform.scale(
          scale: 1.0 + t * 0.03,
          child: Container(
            decoration: widget.pulsing
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: widget.color.withValues(alpha: 0.25 + t * 0.25),
                        blurRadius: 8 + t * 12,
                        spreadRadius: t * 2,
                      ),
                    ],
                  )
                : null,
            child: child,
          ),
        );
      },
      child: FilledButton.icon(
        onPressed: widget.onPressed,
        icon: Icon(widget.icon, size: 18),
        label: Text(
          widget.label,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: widget.color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      ),
    );
  }
}

// ─── Timeout alert ──────────────────────────────────────────────

/// Alert box shown when the connection seems to be taking too long.
class _TimeoutAlertBox extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.yellow.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.yellow.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                Icons.warning_amber_rounded,
                size: 20,
                color: AppColors.yellow,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'La connessione sta impiegando troppo tempo. '
                'Potrebbe essere fallita — prova a riprovare '
                'oppure termina e riprova più tardi.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textPrimary.withValues(alpha: 0.85),
                      height: 1.4,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
