import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../models/tor_status.dart';

/// Bold status banner card for the home screen.
class StatusCard extends StatelessWidget {
  final TorStatus torStatus;

  const StatusCard({super.key, required this.torStatus});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, label, accentColor, description) = _statusInfo();

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

  (IconData, String, Color, String) _statusInfo() {
    switch (torStatus.state) {
      case TorConnectionState.stopped:
        return (
          Icons.shield_outlined,
          'Tor non attivo',
          AppColors.textSecondary,
          'Avvia Tor per poter effettuare o ricevere chiamate cifrate.',
        );
      case TorConnectionState.notInstalled:
        return (
          Icons.download,
          'Tor non installato',
          AppColors.coral,
          'Installa il client Tor per utilizzare OnionTalkie.',
        );
      case TorConnectionState.starting:
        return (
          Icons.hourglass_top,
          'Avvio in corso...',
          AppColors.yellow,
          'Inizializzazione del servizio Tor.',
        );
      case TorConnectionState.bootstrapping:
        return (
          Icons.sync,
          'Connessione a Tor...',
          AppColors.yellow,
          'Bootstrap in corso — costruzione del circuito.',
        );
      case TorConnectionState.connected:
        return (
          Icons.shield,
          'Tor connesso',
          AppColors.mint,
          torStatus.onionAddress != null
              ? '${torStatus.onionAddress!.substring(0, 16)}...onion'
              : 'Pronto per chiamate cifrate.',
        );
      case TorConnectionState.error:
        return (
          Icons.error_outline,
          'Errore Tor',
          AppColors.coral,
          torStatus.errorMessage ?? 'Si è verificato un errore.',
        );
    }
  }
}
