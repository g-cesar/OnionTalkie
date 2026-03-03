import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_theme.dart';

/// Push-to-talk circular button.
/// Hold down to record, release to stop.
/// When [enabled] is false the button is greyed out and unresponsive
/// (used to enforce walkie-talkie mutual exclusion).
class PttButton extends StatefulWidget {
  final bool isRecording;
  final bool enabled;
  final VoidCallback onPttStart;
  final VoidCallback onPttStop;

  const PttButton({
    super.key,
    required this.isRecording,
    this.enabled = true,
    required this.onPttStart,
    required this.onPttStop,
  });

  @override
  State<PttButton> createState() => _PttButtonState();
}

class _PttButtonState extends State<PttButton> {
  bool _isPressed = false;

  void _onPointerDown(PointerDownEvent event) {
    if (!widget.enabled) return;
    setState(() => _isPressed = true);
    HapticFeedback.mediumImpact();
    widget.onPttStart();
  }

  void _onPointerUp(PointerEvent event) {
    if (_isPressed) {
      setState(() => _isPressed = false);
      HapticFeedback.lightImpact();
      widget.onPttStop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recording = widget.isRecording;
    final enabled = widget.enabled;

    return Listener(
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerUp,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 72,
        decoration: BoxDecoration(
          color: !enabled
              ? theme.colorScheme.surfaceContainerHighest
              : recording
                  ? AppColors.coral
                  : theme.colorScheme.primary,
          borderRadius: BorderRadius.circular(36),
          boxShadow: [
            BoxShadow(
              color: (!enabled
                      ? Colors.grey
                      : recording
                          ? AppColors.coral
                          : theme.colorScheme.primary)
                  .withValues(alpha: recording ? 0.4 : 0.2),
              blurRadius: recording ? 20 : 8,
              spreadRadius: recording ? 2 : 0,
            ),
          ],
        ),
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                !enabled
                    ? Icons.mic_off
                    : recording
                        ? Icons.mic
                        : Icons.mic_none,
                color: !enabled
                    ? theme.colorScheme.onSurfaceVariant
                    : Colors.white,
                size: 28,
              ),
              const SizedBox(width: 8),
              Text(
                !enabled
                    ? 'STA PARLANDO...'
                    : recording
                        ? 'TRASMETTENDO...'
                        : 'TIENI PER PARLARE',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: !enabled
                      ? theme.colorScheme.onSurfaceVariant
                      : Colors.white,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
