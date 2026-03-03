import 'package:flutter/material.dart';

import '../models/call_state.dart';

/// Horizontal stepper widget showing connection establishment phases.
///
/// Displays each phase as an icon on a timeline. Completed phases
/// turn green, the current phase pulses, and pending phases appear grey.
/// This gives users real-time visual feedback on the connection progress
/// through the Tor network.
class ConnectionStepsWidget extends StatefulWidget {
  final Set<ConnectionStep> completedSteps;
  final bool isIncoming;

  const ConnectionStepsWidget({
    super.key,
    required this.completedSteps,
    required this.isIncoming,
  });

  @override
  State<ConnectionStepsWidget> createState() => _ConnectionStepsWidgetState();
}

class _ConnectionStepsWidgetState extends State<ConnectionStepsWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  static const _completedColor = Color(0xFF4CAF50);
  static const _pendingColor = Color(0xFF616161);
  static const _circleSize = 36.0;
  static const _iconSize = 18.0;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  List<_StepData> get _steps => [
        _StepData(
          ConnectionStep.torCircuit,
          Icons.security,
          widget.isIncoming ? 'Hidden\nService' : 'Circuito\nTor',
        ),
        _StepData(
          ConnectionStep.peerConnected,
          Icons.link,
          widget.isIncoming ? 'Peer\nconnesso' : 'Peer\nraggiunto',
        ),
        _StepData(
          ConnectionStep.keyExchange,
          Icons.swap_horiz,
          'Scambio\nchiavi',
        ),
        _StepData(
          ConnectionStep.keyVerified,
          Icons.verified_user,
          'Verifica\nchiavi',
        ),
        _StepData(
          ConnectionStep.encrypted,
          Icons.lock,
          'Canale\ncifrato',
        ),
      ];

  ConnectionStep? get _currentStep {
    for (final s in _steps) {
      if (!widget.completedSteps.contains(s.step)) return s.step;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final steps = _steps;
    final current = _currentStep;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Step icons with connectors ──
          Row(
            children: [
              for (int i = 0; i < steps.length; i++) ...[
                if (i > 0)
                  Expanded(
                    child: _buildConnector(steps[i - 1], steps[i], theme),
                  ),
                _buildStepCircle(steps[i], current, theme),
              ],
            ],
          ),
          const SizedBox(height: 6),
          // ── Labels ──
          Row(
            children: [
              for (int i = 0; i < steps.length; i++) ...[
                if (i > 0) const Spacer(),
                SizedBox(
                  width: _circleSize + 20,
                  child: Text(
                    steps[i].label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 9,
                      height: 1.2,
                      color: widget.completedSteps.contains(steps[i].step)
                          ? _completedColor
                          : steps[i].step == current
                              ? theme.colorScheme.primary
                              : _pendingColor.withValues(alpha: 0.5),
                      fontWeight:
                          widget.completedSteps.contains(steps[i].step)
                              ? FontWeight.w600
                              : FontWeight.normal,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStepCircle(
    _StepData data,
    ConnectionStep? current,
    ThemeData theme,
  ) {
    final isCompleted = widget.completedSteps.contains(data.step);
    final isCurrent = data.step == current;

    if (isCurrent) {
      return AnimatedBuilder(
        animation: _pulseController,
        builder: (context, _) {
          final t = _pulseController.value;
          return Container(
            width: _circleSize,
            height: _circleSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.primary
                  .withValues(alpha: 0.08 + t * 0.12),
              border: Border.all(
                color: theme.colorScheme.primary
                    .withValues(alpha: 0.5 + t * 0.5),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.primary
                      .withValues(alpha: t * 0.25),
                  blurRadius: 8 * t,
                  spreadRadius: 2 * t,
                ),
              ],
            ),
            child: Icon(
              data.icon,
              size: _iconSize,
              color: theme.colorScheme.primary,
            ),
          );
        },
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOut,
      width: _circleSize,
      height: _circleSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isCompleted
            ? _completedColor
            : _pendingColor.withValues(alpha: 0.08),
        border: Border.all(
          color: isCompleted
              ? _completedColor
              : _pendingColor.withValues(alpha: 0.25),
          width: isCompleted ? 0 : 1.5,
        ),
      ),
      child: Icon(
        data.icon,
        size: _iconSize,
        color: isCompleted
            ? Colors.white
            : _pendingColor.withValues(alpha: 0.4),
      ),
    );
  }

  Widget _buildConnector(_StepData from, _StepData to, ThemeData theme) {
    final fromDone = widget.completedSteps.contains(from.step);
    final toDone = widget.completedSteps.contains(to.step);

    Color color;
    if (fromDone && toDone) {
      color = _completedColor;
    } else if (fromDone) {
      color = theme.colorScheme.primary.withValues(alpha: 0.35);
    } else {
      color = _pendingColor.withValues(alpha: 0.12);
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOut,
      height: 2,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }
}

class _StepData {
  final ConnectionStep step;
  final IconData icon;
  final String label;

  const _StepData(this.step, this.icon, this.label);
}
