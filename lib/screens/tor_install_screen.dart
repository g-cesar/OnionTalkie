import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
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

/// Returns localized install option name.
String _localizedOptionName(BuildContext context, String name) {
  final l = S.of(context);
  switch (name) {
    case 'Orbot (recommended)': return l.orbotRecommended;
    case 'Orbot — Guardian Project Repo': return l.orbotGuardian;
    case 'Orbot — Direct download': return l.orbotDirect;
    case 'Onion Browser': return l.onionBrowser;
    case 'Homebrew (macOS)': return l.homebrewMacos;
    case 'Official site': return l.officialSite;
    case 'Local server (recommended)': return l.localServerRecommended;
    case 'Install Tor': return l.installTorOption;
    case 'Native Android/iOS version': return l.nativeVersionOption;
    default: return name;
  }
}

/// Returns localized install option description.
String _localizedOptionDesc(BuildContext context, String desc) {
  final l = S.of(context);
  if (desc.startsWith('Official Tor Project app for Android')) return l.orbotAndroidDesc;
  if (desc.startsWith('Guardian Project F-Droid')) return l.orbotGuardianDesc;
  if (desc.startsWith('Download the APK')) return l.orbotDirectDesc;
  if (desc.startsWith('Official Tor Project app for iOS')) return l.orbotIosDesc;
  if (desc.startsWith('Tor browser for iOS')) return l.onionBrowserDesc;
  if (desc.startsWith('Install via terminal')) return l.homebrewDesc;
  if (desc.startsWith('Download Tor from')) return l.officialSiteDesc;
  if (desc.startsWith('Start the local server')) return l.localServerDesc;
  if (desc.startsWith('macOS: brew install')) return l.installTorOptionDesc;
  if (desc.startsWith('For the best experience')) return l.nativeVersionDesc;
  return desc;
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
          SnackBar(
            content: Text(S.of(context).torFoundSnackbar),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context).torNotFoundSnackbar),
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
        title: Text(S.of(context).installTorTitle),
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
                  S.of(context).torNotFound,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  S.of(context).torInstallExplanation,
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
            S.of(context).installOptions,
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
            label: Text(_checking ? S.of(context).verifying : S.of(context).verifyTorInstalled),
          ),

          const SizedBox(height: 12),

          // Skip / dismiss
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(S.of(context).goBack),
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
                    S.of(context).torUsageExplanation,
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
                      _localizedOptionName(context, option.name),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _localizedOptionDesc(context, option.description),
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
