import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/app_settings.dart';
import '../../providers/settings_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Impostazioni'),
      ),
      body: ListView(
        children: [
          // Security Section
          _buildSectionHeader(theme, 'Sicurezza'),
          ListTile(
            leading: const Icon(Icons.lock),
            title: const Text('Sicurezza'),
            subtitle: Text('Cifra: ${settings.cipher.toUpperCase()}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/security'),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.handshake),
            title: const Text('PAKE (SPAKE2)'),
            subtitle: Text(
              settings.keyExchangeMode == KeyExchangeMode.pake
                  ? 'Scambio chiave zero-knowledge attivo'
                  : 'Chiave manuale statica (PBKDF2)',
            ),
            value: settings.keyExchangeMode == KeyExchangeMode.pake,
            onChanged: (value) {
              ref.read(settingsProvider.notifier).setKeyExchangeMode(
                    value ? KeyExchangeMode.pake : KeyExchangeMode.manual,
                  );
            },
          ),

          const Divider(),

          // Audio Section
          _buildSectionHeader(theme, 'Audio'),
          ListTile(
            leading: const Icon(Icons.music_note),
            title: const Text('Impostazioni audio'),
            subtitle: Text('Opus ${settings.opusBitrate}kbps, ${settings.sampleRate}Hz'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/audio'),
          ),
          ListTile(
            leading: const Icon(Icons.voice_chat),
            title: const Text('Voice Changer'),
            subtitle: Text(settings.voiceChangerPreset.name == 'off'
                ? 'Disattivato'
                : settings.voiceChangerPreset.name),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/voice-changer'),
          ),

          const Divider(),

          // Tor Section
          _buildSectionHeader(theme, 'Tor'),
          ListTile(
            leading: const Icon(Icons.router),
            title: const Text('Impostazioni Tor'),
            subtitle: Text(settings.snowflakeEnabled
                ? 'Snowflake abilitato'
                : 'Connessione diretta'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/tor'),
          ),

          const Divider(),

          // General Section
          _buildSectionHeader(theme, 'Generale'),
          SwitchListTile(
            secondary: const Icon(Icons.notifications),
            title: const Text('Suono PTT'),
            subtitle: Text(settings.pttChime.name == 'off'
                ? 'Nessun suono'
                : 'Preset: ${settings.pttChime.name}'),
            value: settings.pttChime.name != 'off',
            onChanged: (value) {
              // Toggle between off and tone
              ref.read(settingsProvider.notifier).setPttChime(
                value
                    ? PttChimePreset.tone
                    : PttChimePreset.off,
              );
            },
          ),

          const Divider(),

          // About Section
          _buildSectionHeader(theme, 'Info'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('OnionTalkie'),
            subtitle: Text('v1.0.0 — Comunicazione cifrata PTT su Tor'),
          ),
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('Codice sorgente'),
            subtitle: const Text('Licenza open source'),
            onTap: () {
              // Could open GitLab link
            },
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
