import 'package:flutter/material.dart';
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
        const SnackBar(
          content: Text('URL relay salvato'),
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
      appBar: AppBar(title: const Text('Server Relay')),
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
                      'Cos\'è il relay server?',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Nel browser non è possibile connettersi direttamente alla rete Tor. '
                  'Il relay server funge da ponte: riceve la connessione WebSocket dal browser '
                  'e la instrada attraverso Tor verso la destinazione .onion.',
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
            'URL del relay',
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
              helperText: 'Inserisci l\'URL WebSocket del tuo relay server.',
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
            label: Text(_saved ? 'Salvato' : 'Salva'),
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
                  'Come funziona',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                _buildFlowStep(theme, '1', 'Browser', 'Connessione WebSocket al relay'),
                _buildFlowArrow(theme),
                _buildFlowStep(theme, '2', 'Relay Server', 'Converte WebSocket → TCP Tor SOCKS5'),
                _buildFlowArrow(theme),
                _buildFlowStep(theme, '3', 'Rete Tor', 'Instrada il traffico verso .onion'),
                _buildFlowArrow(theme),
                _buildFlowStep(theme, '4', 'Destinazione', 'Hidden service .onion del contatto'),
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
                    'Il relay server può vedere il traffico in transito (ma NON il contenuto, '
                    'che è cifrato end-to-end). Usa solo relay server fidati o gestisci il tuo.',
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
