import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/settings_provider.dart';
import '../../providers/tor_provider.dart';

class TorSettingsScreen extends ConsumerWidget {
  const TorSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Impostazioni Tor'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Snowflake Bridge
          SwitchListTile(
            secondary: const Icon(Icons.ac_unit),
            title: const Text('Snowflake Bridge'),
            subtitle: const Text(
              'Usa proxy WebRTC Snowflake per aggirare la censura. '
              'La connessione sarà più lenta.',
            ),
            value: settings.snowflakeEnabled,
            onChanged: (value) {
              ref.read(settingsProvider.notifier).setSnowflakeEnabled(value);
            },
          ),

          const Divider(height: 24),

          // The options below require a local Tor instance with a
          // ControlPort — not available on web.
          if (!kIsWeb) ...[

          // Show Circuit Path
          SwitchListTile(
            secondary: const Icon(Icons.route),
            title: const Text('Mostra percorso circuito'),
            subtitle: const Text(
              'Visualizza relay, nomi e paesi del circuito Tor '
              'nella schermata home e durante le chiamate.',
            ),
            value: settings.showCircuitPath,
            onChanged: (value) {
              ref.read(settingsProvider.notifier).setShowCircuitPath(value);
            },
          ),

          // Circuit refresh interval (only if circuit is enabled)
          if (settings.showCircuitPath) ...[
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('Intervallo aggiornamento'),
              subtitle: Text(
                'Il circuito si aggiorna ogni ${settings.circuitRefreshSeconds} secondi',
              ),
              trailing: DropdownButton<int>(
                value: settings.circuitRefreshSeconds,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(value: 15, child: Text('15 s')),
                  DropdownMenuItem(value: 30, child: Text('30 s')),
                  DropdownMenuItem(value: 60, child: Text('60 s')),
                  DropdownMenuItem(value: 120, child: Text('2 min')),
                  DropdownMenuItem(value: 300, child: Text('5 min')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    ref
                        .read(settingsProvider.notifier)
                        .setCircuitRefreshSeconds(value);
                  }
                },
              ),
            ),
          ],

          const Divider(height: 24),

          // Exclude Countries
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Escludi paesi',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Escludi paesi specifici dai circuiti Tor. '
              'Usa ExcludeNodes con StrictNodes nel torrc.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Preset buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildPresetChip(
                  context,
                  ref,
                  'Five Eyes',
                  '{US},{GB},{CA},{AU},{NZ}',
                  settings.excludeNodes,
                ),
                _buildPresetChip(
                  context,
                  ref,
                  'Nine Eyes',
                  '{US},{GB},{CA},{AU},{NZ},{DK},{FR},{NL},{NO}',
                  settings.excludeNodes,
                ),
                _buildPresetChip(
                  context,
                  ref,
                  'Fourteen Eyes',
                  '{US},{GB},{CA},{AU},{NZ},{DK},{FR},{NL},{NO},{DE},{BE},{IT},{SE},{ES}',
                  settings.excludeNodes,
                ),
                ActionChip(
                  label: const Text('Nessuno'),
                  onPressed: () {
                    ref.read(settingsProvider.notifier).setExcludeNodes('');
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Custom country codes
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextFormField(
              initialValue: settings.excludeNodes,
              decoration: const InputDecoration(
                labelText: 'Codici paese personalizzati',
                hintText: '{US},{GB},{DE}',
                helperText: 'Formato: {XX},{YY} — Codici ISO 3166-1 alpha-2',
              ),
              onFieldSubmitted: (value) {
                ref.read(settingsProvider.notifier).setExcludeNodes(value);
              },
            ),
          ),

          const SizedBox(height: 24),

          // Restart Tor button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              onPressed: () {
                ref.read(torProvider.notifier).restart(
                  snowflake: settings.snowflakeEnabled,
                  excludeNodes: settings.excludeNodes,
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Tor in riavvio...')),
                );
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Riavvia Tor con nuove impostazioni'),
            ),
          ),

          const SizedBox(height: 32),

          ], // end !kIsWeb
        ],
      ),
    );
  }

  Widget _buildPresetChip(
    BuildContext context,
    WidgetRef ref,
    String label,
    String value,
    String currentValue,
  ) {
    final isSelected = currentValue == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) {
        ref.read(settingsProvider.notifier).setExcludeNodes(value);
      },
    );
  }
}
