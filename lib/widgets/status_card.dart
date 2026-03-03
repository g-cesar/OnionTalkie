import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../core/theme/app_theme.dart';
import '../models/tor_status.dart';

/// Bold status banner card for the home screen.
class StatusCard extends StatelessWidget {
  final TorStatus torStatus;

  const StatusCard({super.key, required this.torStatus});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, label, accentColor, description) = _statusInfo(context);

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
      child: Row(
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
                    value: torStatus.state == TorConnectionState.bootstrapping
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
