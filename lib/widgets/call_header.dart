import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../models/call_state.dart';
import '../providers/settings_provider.dart';
import '../services/circuit_service.dart';
import 'circuit_path_widget.dart';

/// Header widget displayed at the top of the call screen, showing
/// remote address, cipher match status, call phase, and optionally the
/// Tor circuit path when "Mostra percorso circuito" is enabled.
class CallHeader extends ConsumerStatefulWidget {
  final CallState callState;

  const CallHeader({super.key, required this.callState});

  @override
  ConsumerState<CallHeader> createState() => _CallHeaderState();
}

class _CallHeaderState extends ConsumerState<CallHeader> {
  Timer? _circuitTimer;
  List<CircuitHop>? _circuitHops;

  @override
  void initState() {
    super.initState();
    _maybeStartCircuitPolling();
  }

  @override
  void dispose() {
    _circuitTimer?.cancel();
    super.dispose();
  }

  void _maybeStartCircuitPolling() {
    if (kIsWeb) return; // No local Tor ControlPort on web.
    final show = ref.read(settingsProvider).showCircuitPath;
    if (!show) return;
    _fetchCircuit();
    _circuitTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _fetchCircuit();
    });
  }

  Future<void> _fetchCircuit() async {
    final hops = await CircuitService.getCircuitHops();
    if (mounted && hops != null && hops.isNotEmpty) {
      setState(() => _circuitHops = hops);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final callState = widget.callState;
    final showCircuit = ref.watch(settingsProvider).showCircuitPath;

    // Start / stop polling if setting changes at runtime.
    if (showCircuit && _circuitTimer == null) {
      _maybeStartCircuitPolling();
    } else if (!showCircuit && _circuitTimer != null) {
      _circuitTimer?.cancel();
      _circuitTimer = null;
      _circuitHops = null;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        border: Border(
          bottom: BorderSide(
            color: AppColors.outline.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Top row: phase label + remote PTT indicator
            Row(
              children: [
                // Phase badge
                _PhaseBadge(phase: callState.phase),

                const Spacer(),

                // Remote PTT indicator
                if (callState.remotePttState == RemotePttState.recording)
                  _AnimatedRecordingBadge(),

                // HMAC badge
                if (callState.hmacEnabled)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Chip(
                      avatar: const Icon(Icons.verified_user, size: 14),
                      label: const Text('HMAC'),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      labelStyle: theme.textTheme.labelSmall,
                    side: BorderSide(color: AppColors.mint.withValues(alpha: 0.5)),
                    backgroundColor: AppColors.mint.withValues(alpha: 0.1),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 8),

            // Remote address
            if (callState.remoteAddress != null) ...[
              Row(
                children: [
                  Icon(
                    Icons.person,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      callState.remoteAddress!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],

            // Cipher info row
            if (callState.localCipher != null)
              _CipherRow(callState: callState),

            // Circuit path row
            if (showCircuit && _circuitHops != null)
              CircuitPathWidget(hops: _circuitHops!),
          ],
        ),
      ),
    );
  }
}

/// Badge showing the current call phase.
class _PhaseBadge extends StatelessWidget {
  final CallPhase phase;

  const _PhaseBadge({required this.phase});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color, icon) = _phaseInfo(theme);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  (String, Color, IconData) _phaseInfo(ThemeData theme) {
    switch (phase) {
      case CallPhase.idle:
        return ('Inattivo', theme.colorScheme.outline, Icons.phone_disabled);
      case CallPhase.connecting:
        return ('Connessione...', theme.colorScheme.tertiary, Icons.sync);
      case CallPhase.ringing:
        return ('In arrivo', AppColors.yellow, Icons.ring_volume);
      case CallPhase.active:
        return ('In chiamata', AppColors.mint, Icons.call);
      case CallPhase.ended:
        return ('Terminata', theme.colorScheme.outline, Icons.call_end);
      case CallPhase.error:
        return ('Errore', theme.colorScheme.error, Icons.error_outline);
    }
  }
}

/// Shows local/remote cipher with a match/mismatch indicator.
class _CipherRow extends StatelessWidget {
  final CallState callState;

  const _CipherRow({required this.callState});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final match = callState.ciphersMatch;
    final matchColor = match ? AppColors.mint : AppColors.yellow;

    return Row(
      children: [
        Icon(
          match ? Icons.lock : Icons.lock_open,
          size: 14,
          color: matchColor,
        ),
        const SizedBox(width: 6),
        Text(
          callState.localCipher ?? '—',
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface,
          ),
        ),
        if (callState.remoteCipher != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Icon(
              match ? Icons.check_circle : Icons.warning_amber,
              size: 14,
              color: matchColor,
            ),
          ),
          Expanded(
            child: Text(
              match ? 'Cipher corrispondenti' : 'Cipher diversi: ${callState.remoteCipher}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: matchColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }
}

/// Animated badge indicating the remote party is speaking.
class _AnimatedRecordingBadge extends StatefulWidget {
  @override
  State<_AnimatedRecordingBadge> createState() => _AnimatedRecordingBadgeState();
}

class _AnimatedRecordingBadgeState extends State<_AnimatedRecordingBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
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
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.coral.withValues(alpha: 0.1 + _controller.value * 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.coral.withValues(alpha: 0.3 + _controller.value * 0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.mic, size: 14, color: AppColors.coral.withValues(alpha: 0.7 + _controller.value * 0.3)),
              const SizedBox(width: 4),
              Text(
                'Parla',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.coral,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}


