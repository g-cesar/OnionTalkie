import 'package:flutter/material.dart';
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
        title: const Text('Stato del sistema'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Tor Status
          _buildSection(
            theme,
            'Tor',
            Icons.security,
            [
              _buildStatusRow(
                theme,
                'Stato',
                _torStateLabel(torStatus.state),
                _torStateColor(torStatus.state),
              ),
              _buildStatusRow(
                theme,
                'Bootstrap',
                '${torStatus.bootstrapProgress}%',
                torStatus.bootstrapProgress == 100 ? AppColors.mint : AppColors.yellow,
              ),
              _buildStatusRow(
                theme,
                'Indirizzo Onion',
                torStatus.onionAddress ?? 'Non disponibile',
                torStatus.onionAddress != null ? AppColors.mint : AppColors.textSecondary,
              ),
              _buildStatusRow(
                theme,
                'Snowflake',
                settings.snowflakeEnabled ? 'Abilitato' : 'Disabilitato',
                settings.snowflakeEnabled ? AppColors.yellow : AppColors.textSecondary,
              ),
              if (settings.excludeNodes.isNotEmpty)
                _buildStatusRow(
                  theme,
                  'Nodi esclusi',
                  settings.excludeNodes,
                  AppColors.yellow,
                ),
            ],
          ),

          const SizedBox(height: 16),

          // Encryption Status
          _buildSection(
            theme,
            'Cifratura',
            Icons.lock,
            [
              _buildStatusRow(
                theme,
                'Cifra',
                settings.cipher.toUpperCase(),
                AppColors.yellow,
              ),
              _buildStatusRow(
                theme,
                'Segreto condiviso',
                encryption.hasSecret ? 'Configurato' : 'Non impostato',
                encryption.hasSecret ? AppColors.mint : AppColors.coral,
              ),
              _buildStatusRow(
                theme,
                'HMAC',
                settings.hmacEnabled ? 'Abilitato' : 'Disabilitato',
                settings.hmacEnabled ? AppColors.mint : AppColors.textSecondary,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Audio Status
          _buildSection(
            theme,
            'Audio',
            Icons.mic,
            [
              _buildStatusRow(
                theme,
                'Bitrate Opus',
                '${settings.opusBitrate} kbps',
                AppColors.yellow,
              ),
              _buildStatusRow(
                theme,
                'Sample Rate',
                '${settings.sampleRate} Hz',
                AppColors.yellow,
              ),
              _buildStatusRow(
                theme,
                'Voice Changer',
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
              'Errori',
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

  String _torStateLabel(TorConnectionState state) {
    switch (state) {
      case TorConnectionState.stopped:
        return 'Fermo';
      case TorConnectionState.notInstalled:
        return 'Non installato';
      case TorConnectionState.starting:
        return 'In avvio...';
      case TorConnectionState.bootstrapping:
        return 'Bootstrap...';
      case TorConnectionState.connected:
        return 'Connesso';
      case TorConnectionState.error:
        return 'Errore';
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
