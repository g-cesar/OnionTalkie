import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/settings_provider.dart';

/// Screen to configure the relay server URL (used on web).
///
/// On web, Tor cannot run locally. A relay server bridges
/// WebSocket traffic from the browser to the Tor network.
class RelaySettingsScreen extends ConsumerStatefulWidget {
  const RelaySettingsScreen({super.key});

  @override
  ConsumerState<RelaySettingsScreen> createState() =>
      _RelaySettingsScreenState();
}

class _RelaySettingsScreenState extends ConsumerState<RelaySettingsScreen> {
  late final TextEditingController _urlController;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    final current = ref.read(settingsProvider).relayServerUrl;
    _urlController = TextEditingController(text: current);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final url = _urlController.text.trim();
    await ref.read(settingsProvider.notifier).setRelayServerUrl(url);
    if (mounted) {
      setState(() => _saved = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.of(context).relayUrlSaved),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _saved = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(S.of(context).relayServer)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Explanation card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.yellow.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.dns, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      S.of(context).whatIsRelay,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  S.of(context).relayExplanation,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // URL input
          Text(
            S.of(context).relayUrl,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _urlController,
            decoration: InputDecoration(
              hintText: 'wss://relay.example.com/ws',
              prefixIcon: const Icon(Icons.link),
              border: const OutlineInputBorder(),
              helperText: S.of(context).relayUrlHelper,
              helperMaxLines: 2,
            ),
            keyboardType: TextInputType.url,
            style: const TextStyle(fontFamily: 'monospace'),
            onSubmitted: (_) => _save(),
          ),

          const SizedBox(height: 16),

          FilledButton.icon(
            onPressed: _save,
            icon: Icon(_saved ? Icons.check : Icons.save),
            label: Text(_saved ? S.of(context).saved : S.of(context).save),
          ),

          const SizedBox(height: 32),

          // Architecture diagram
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.darkCard,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  S.of(context).howItWorks,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                _buildFlowStep(theme, '1', S.of(context).relayStepBrowser, S.of(context).relayStepBrowserDesc),
                _buildFlowArrow(theme),
                _buildFlowStep(theme, '2', S.of(context).relayStepRelay, S.of(context).relayStepRelayDesc),
                _buildFlowArrow(theme),
                _buildFlowStep(theme, '3', S.of(context).relayStepTor, S.of(context).relayStepTorDesc),
                _buildFlowArrow(theme),
                _buildFlowStep(theme, '4', S.of(context).relayStepDest, S.of(context).relayStepDestDesc),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Warning
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.coral.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber,
                  size: 18,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    S.of(context).relaySecurityNote,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
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

  Widget _buildFlowStep(ThemeData theme, String num, String title, String desc) {
    return Row(
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: theme.colorScheme.primary,
          child: Text(
            num,
            style: TextStyle(
              color: theme.colorScheme.onPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              Text(desc, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFlowArrow(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(left: 13, top: 2, bottom: 2),
      child: Icon(Icons.arrow_downward, size: 16, color: theme.colorScheme.outline),
    );
  }
}
