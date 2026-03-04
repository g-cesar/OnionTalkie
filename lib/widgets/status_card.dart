import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../models/tor_status.dart';
import '../providers/tor_provider.dart';

/// Bold status banner card for the home screen.
///
/// When Tor is connected, a secondary propagation-status row is shown below
/// the main label so the user knows whether the hidden service is reachable.
class StatusCard extends ConsumerWidget {
  final TorStatus torStatus;

  const StatusCard({super.key, required this.torStatus});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final (icon, label, accentColor, description) = _statusInfo(context);
    final showPropagation = torStatus.state == TorConnectionState.connected;

    return Container(
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.18),
          width: 1.5,
        ),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Icon circle
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: _buildIcon(icon, accentColor),
              ),

              const SizedBox(width: 16),

              // Text
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: accentColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // Bootstrap progress
              if (torStatus.state == TorConnectionState.bootstrapping ||
                  torStatus.state == TorConnectionState.starting)
                SizedBox(
                  width: 44,
                  height: 44,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value:
                            torStatus.state == TorConnectionState.bootstrapping
                                ? torStatus.bootstrapProgress / 100
                                : null,
                        strokeWidth: 3,
                        color: accentColor,
                      ),
                      if (torStatus.state == TorConnectionState.bootstrapping)
                        Text(
                          '${torStatus.bootstrapProgress}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: accentColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),

          // ── Propagation status row (only when Tor is connected) ──
          if (showPropagation) ...[
            const SizedBox(height: 10),
            const Divider(height: 1, thickness: 0.5),
            const SizedBox(height: 8),
            _PropagationRow(
              torStatus: torStatus,
              onRetry:
                  () => ref.read(torProvider.notifier).checkHsPropagation(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildIcon(IconData icon, Color color) {
    if (torStatus.state == TorConnectionState.starting) {
      return Padding(
        padding: const EdgeInsets.all(14),
        child: CircularProgressIndicator(strokeWidth: 2, color: color),
      );
    }
    return Icon(icon, color: color, size: 26);
  }

  (IconData, String, Color, String) _statusInfo(BuildContext context) {
    switch (torStatus.state) {
      case TorConnectionState.stopped:
        return (
          Icons.shield_outlined,
          S.of(context).torNotActive,
          AppColors.textSecondary,
          S.of(context).torNotActiveDesc,
        );
      case TorConnectionState.notInstalled:
        return (
          Icons.download,
          S.of(context).torNotInstalledBanner,
          AppColors.coral,
          S.of(context).torNotInstalledDesc,
        );
      case TorConnectionState.starting:
        return (
          Icons.hourglass_top,
          S.of(context).startingUp,
          AppColors.yellow,
          S.of(context).startingUpDesc,
        );
      case TorConnectionState.bootstrapping:
        return (
          Icons.sync,
          S.of(context).connectingToTor,
          AppColors.yellow,
          S.of(context).connectingToTorDesc,
        );
      case TorConnectionState.connected:
        return (
          Icons.shield,
          S.of(context).torConnectedBanner,
          AppColors.mint,
          torStatus.onionAddress != null
              ? '${torStatus.onionAddress!.substring(0, 16)}...onion'
              : S.of(context).readyForCalls,
        );
      case TorConnectionState.error:
        return (
          Icons.error_outline,
          S.of(context).torErrorBanner,
          AppColors.coral,
          torStatus.errorMessage ?? S.of(context).torErrorDefault,
        );
    }
  }
}

// ── Propagation status sub-widget ─────────────────────────────────────────

class _PropagationRow extends StatelessWidget {
  final TorStatus torStatus;
  final VoidCallback onRetry;

  const _PropagationRow({required this.torStatus, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final (dot, text, showSpinner, showRetry) = _info(context);

    return Row(
      children: [
        // Dot / spinner
        if (showSpinner)
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.yellow,
            ),
          )
        else
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (showRetry)
          GestureDetector(
            onTap: onRetry,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.refresh, size: 16, color: cs.primary),
            ),
          ),
      ],
    );
  }

  (Color, String, bool showSpinner, bool showRetry) _info(
    BuildContext context,
  ) {
    switch (torStatus.propagationState) {
      case HsPropagationState.unknown:
        return (Colors.grey, S.of(context).propagationUnknown, false, false);
      case HsPropagationState.checking:
        return (
          AppColors.yellow,
          S.of(context).propagationChecking,
          true,
          false,
        );
      case HsPropagationState.ready:
        return (AppColors.mint, S.of(context).propagationReady, false, false);
      case HsPropagationState.timeout:
        return (AppColors.coral, S.of(context).propagationTimeout, false, true);
    }
  }
}
