import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../models/tor_status.dart';
import '../providers/providers.dart';
import '../providers/settings_provider.dart';
import '../providers/tor_provider.dart';

class StatusScreen extends ConsumerWidget {
  const StatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final torStatus = ref.watch(torProvider);
    final settings = ref.watch(settingsProvider);
    final encryption = ref.watch(encryptionServiceProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(S.of(context).statusScreenTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Tor Status
          _buildSection(
            theme,
            S.of(context).tor,
            Icons.security,
            [
              _buildStatusRow(
                theme,
                S.of(context).statusLabel,
                _torStateLabel(context, torStatus.state),
                _torStateColor(torStatus.state),
              ),
              _buildStatusRow(
                theme,
                S.of(context).bootstrap,
                '${torStatus.bootstrapProgress}%',
                torStatus.bootstrapProgress == 100 ? AppColors.mint : AppColors.yellow,
              ),
              _buildStatusRow(
                theme,
                S.of(context).onionAddressLabel,
                torStatus.onionAddress ?? S.of(context).notAvailable,
                torStatus.onionAddress != null ? AppColors.mint : AppColors.textSecondary,
              ),
              _buildStatusRow(
                theme,
                S.of(context).snowflake,
                settings.snowflakeEnabled ? S.of(context).enabled : S.of(context).disabled,
                settings.snowflakeEnabled ? AppColors.yellow : AppColors.textSecondary,
              ),
              if (settings.excludeNodes.isNotEmpty)
                _buildStatusRow(
                  theme,
                  S.of(context).excludedNodes,
                  settings.excludeNodes,
                  AppColors.yellow,
                ),
            ],
          ),

          const SizedBox(height: 16),

          // Encryption Status
          _buildSection(
            theme,
            S.of(context).encryption,
            Icons.lock,
            [
              _buildStatusRow(
                theme,
                S.of(context).cipher,
                settings.cipher.toUpperCase(),
                AppColors.yellow,
              ),
              _buildStatusRow(
                theme,
                S.of(context).sharedSecretStatus,
                encryption.hasSecret ? S.of(context).configured : S.of(context).notConfigured,
                encryption.hasSecret ? AppColors.mint : AppColors.coral,
              ),
              _buildStatusRow(
                theme,
                'HMAC',
                settings.hmacEnabled ? S.of(context).enabled : S.of(context).disabled,
                settings.hmacEnabled ? AppColors.mint : AppColors.textSecondary,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Audio Status
          _buildSection(
            theme,
            S.of(context).audio,
            Icons.mic,
            [
              _buildStatusRow(
                theme,
                S.of(context).opusBitrate,
                '${settings.opusBitrate} kbps',
                AppColors.yellow,
              ),
              _buildStatusRow(
                theme,
                S.of(context).sampleRate,
                '${settings.sampleRate} Hz',
                AppColors.yellow,
              ),
              _buildStatusRow(
                theme,
                S.of(context).voiceChanger,
                settings.voiceChangerPreset.name,
                settings.voiceChangerPreset.name != 'off'
                    ? AppColors.mint
                    : AppColors.textSecondary,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Error log
          if (torStatus.errorMessage != null)
            _buildSection(
              theme,
              S.of(context).errors,
              Icons.error_outline,
              [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    torStatus.errorMessage!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSection(
    ThemeData theme,
    String title,
    IconData icon,
    List<Widget> children,
  ) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ...children,
        ],
      ),
    );
  }

  Widget _buildStatusRow(
    ThemeData theme,
    String label,
    String value,
    Color statusColor,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Flexible(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _torStateLabel(BuildContext context, TorConnectionState state) {
    switch (state) {
      case TorConnectionState.stopped:
        return S.of(context).torStopped;
      case TorConnectionState.notInstalled:
        return S.of(context).torNotInstalled;
      case TorConnectionState.starting:
        return S.of(context).torStartingStatus;
      case TorConnectionState.bootstrapping:
        return S.of(context).torBootstrapping;
      case TorConnectionState.connected:
        return S.of(context).torConnected;
      case TorConnectionState.error:
        return S.of(context).torError;
    }
  }

  Color _torStateColor(TorConnectionState state) {
    switch (state) {
      case TorConnectionState.stopped:
        return AppColors.textSecondary;
      case TorConnectionState.notInstalled:
        return AppColors.coral;
      case TorConnectionState.starting:
      case TorConnectionState.bootstrapping:
        return AppColors.yellow;
      case TorConnectionState.connected:
        return AppColors.mint;
      case TorConnectionState.error:
        return AppColors.coral;
    }
  }
}
