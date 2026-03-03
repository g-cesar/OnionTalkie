import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../providers/tor_provider.dart';
import '../services/tor_service.dart';

/// Screen shown when Tor is not installed on the device.
/// Guides the user through installation options.
class TorInstallScreen extends ConsumerStatefulWidget {
  const TorInstallScreen({super.key});

  @override
  ConsumerState<TorInstallScreen> createState() => _TorInstallScreenState();
}

class _TorInstallScreenState extends ConsumerState<TorInstallScreen> {
  bool _checking = false;

  Future<void> _recheckInstallation() async {
    setState(() => _checking = true);
    final installed = await ref.read(torProvider.notifier).checkTorInstalled();
    if (mounted) {
      setState(() => _checking = false);
      if (installed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tor trovato! Ora puoi avviare il servizio.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tor non ancora trovato. Completa l\'installazione e riprova.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final torService = ref.read(torServiceProvider);
    final options = torService.getInstallOptions();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Installa Tor'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header illustration
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppColors.coral.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.shield_outlined,
                  size: 64,
                  color: AppColors.coral,
                ),
                const SizedBox(height: 16),
                Text(
                  'Tor non trovato',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Per utilizzare OnionTalkie è necessario un client Tor '
                  'installato sul dispositivo. Scegli una delle opzioni '
                  'qui sotto per installarlo.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          Text(
            'Opzioni di installazione',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 12),

          // Install options
          ...options.map((option) => _InstallOptionCard(
                option: option,
                onTap: () => torService.openInstallOption(option),
              )),

          const SizedBox(height: 24),

          // Re-check button
          FilledButton.icon(
            onPressed: _checking ? null : _recheckInstallation,
            icon: _checking
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            label: Text(_checking ? 'Verifica in corso...' : 'Ho installato Tor — Verifica'),
          ),

          const SizedBox(height: 12),

          // Skip / dismiss
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Torna indietro'),
          ),

          const SizedBox(height: 16),

          // Info note
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.darkCard,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'OnionTalkie utilizza il client Tor per instradare le '
                    'comunicazioni attraverso hidden service .onion, garantendo '
                    'anonimato e cifratura end-to-end.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _InstallOptionCard extends StatelessWidget {
  final TorInstallOption option;
  final VoidCallback onTap;

  const _InstallOptionCard({required this.option, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.yellow.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  _iconFor(option.iconType),
                  color: AppColors.yellow,
                ),
              ),

              const SizedBox(width: 16),

              // Text
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      option.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              Icon(
                Icons.open_in_new,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconFor(IconType type) {
    switch (type) {
      case IconType.store:
        return Icons.storefront;
      case IconType.download:
        return Icons.download;
      case IconType.terminal:
        return Icons.terminal;
      case IconType.web:
        return Icons.language;
    }
  }
}
