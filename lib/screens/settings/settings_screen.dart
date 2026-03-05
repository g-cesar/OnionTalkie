import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
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
      appBar: AppBar(title: Text(S.of(context).settings)),
      body: ListView(
        children: [
          // Security Section
          _buildSectionHeader(theme, S.of(context).security),
          ListTile(
            leading: const Icon(Icons.lock),
            title: Text(S.of(context).security),
            subtitle: Text(
              '${S.of(context).cipher}: ${settings.cipher.toUpperCase()}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/security'),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.handshake),
            title: const Text('PAKE (SPAKE2)'),
            subtitle: Text(
              settings.keyExchangeMode == KeyExchangeMode.pake
                  ? S.of(context).pakeActive
                  : S.of(context).manualKey,
            ),
            value: settings.keyExchangeMode == KeyExchangeMode.pake,
            onChanged: (value) {
              ref
                  .read(settingsProvider.notifier)
                  .setKeyExchangeMode(
                    value ? KeyExchangeMode.pake : KeyExchangeMode.manual,
                  );
            },
          ),

          const Divider(),

          // Audio Section
          _buildSectionHeader(theme, S.of(context).audioSettings),
          ListTile(
            leading: const Icon(Icons.music_note),
            title: Text(S.of(context).audioSettings),
            subtitle: Text(
              'Opus ${settings.opusBitrate}kbps, ${settings.sampleRate}Hz',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/audio'),
          ),
          ListTile(
            leading: const Icon(Icons.voice_chat),
            title: Text(S.of(context).voiceChangerTitle),
            subtitle: Text(
              settings.voiceChangerPreset.name == 'off'
                  ? S.of(context).voiceChangerOff
                  : settings.voiceChangerPreset.name,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/voice-changer'),
          ),

          const Divider(),

          // Tor Section
          _buildSectionHeader(theme, S.of(context).torSettings),
          ListTile(
            leading: const Icon(Icons.router),
            title: Text(S.of(context).torSettings),
            subtitle: Text(
              settings.snowflakeEnabled
                  ? S.of(context).snowflakeEnabled
                  : S.of(context).directConnection,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/tor'),
          ),

          const Divider(),

          // General Section
          _buildSectionHeader(theme, S.of(context).general),
          SwitchListTile(
            secondary: const Icon(Icons.notifications),
            title: Text(S.of(context).pttSound),
            subtitle: Text(
              settings.pttChime.name == 'off'
                  ? S.of(context).noSound
                  : 'Preset: ${settings.pttChime.name}',
            ),
            value: settings.pttChime.name != 'off',
            onChanged: (value) {
              // Toggle between off and tone
              ref
                  .read(settingsProvider.notifier)
                  .setPttChime(
                    value ? PttChimePreset.tone : PttChimePreset.off,
                  );
            },
          ),

          // Language selector
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(S.of(context).language),
            subtitle: Text(_currentLanguageLabel(context, settings.locale)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showLanguagePicker(context, ref, settings.locale),
          ),

          const Divider(),

          // About Section
          _buildSectionHeader(theme, S.of(context).info),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('OnionTalkie'),
            subtitle: Text(S.of(context).versionInfo),
          ),
          ListTile(
            leading: const Icon(Icons.code),
            title: Text(S.of(context).sourceCode),
            subtitle: Text(S.of(context).openSourceLicense),
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

  String _currentLanguageLabel(BuildContext context, String locale) {
    switch (locale) {
      case 'en':
        return S.of(context).languageEn;
      case 'it':
        return S.of(context).languageIt;
      case 'es':
        return S.of(context).languageEs;
      case 'fr':
        return S.of(context).languageFr;
      case 'de':
        return S.of(context).languageDe;
      case 'pt':
        return S.of(context).languagePt;
      case 'ru':
        return S.of(context).languageRu;
      case 'ar':
        return S.of(context).languageAr;
      case 'fa':
        return S.of(context).languageFa;
      case 'zh':
        return S.of(context).languageZh;
      case 'ja':
        return S.of(context).languageJa;
      case 'ko':
        return S.of(context).languageKo;
      default:
        return S.of(context).languageSystem;
    }
  }

  void _showLanguagePicker(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  S.of(context).language,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              RadioListTile<String>(
                title: Text(S.of(context).languageSystem),
                value: '',
                groupValue: current,
                onChanged: (v) {
                  ref.read(settingsProvider.notifier).setLocale(v!);
                  Navigator.pop(ctx);
                },
              ),
              Expanded(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    _buildLanguageItem(
                      context,
                      ref,
                      S.of(context).languageEn,
                      'en',
                      current,
                      ctx,
                    ),
                    _buildLanguageItem(
                      context,
                      ref,
                      S.of(context).languageIt,
                      'it',
                      current,
                      ctx,
                    ),
                    _buildLanguageItem(
                      context,
                      ref,
                      S.of(context).languageEs,
                      'es',
                      current,
                      ctx,
                    ),
                    _buildLanguageItem(
                      context,
                      ref,
                      S.of(context).languageFr,
                      'fr',
                      current,
                      ctx,
                    ),
                    _buildLanguageItem(
                      context,
                      ref,
                      S.of(context).languageDe,
                      'de',
                      current,
                      ctx,
                    ),
                    _buildLanguageItem(
                      context,
                      ref,
                      S.of(context).languagePt,
                      'pt',
                      current,
                      ctx,
                    ),
                    _buildLanguageItem(
                      context,
                      ref,
                      S.of(context).languageRu,
                      'ru',
                      current,
                      ctx,
                    ),
                    _buildLanguageItem(
                      context,
                      ref,
                      S.of(context).languageAr,
                      'ar',
                      current,
                      ctx,
                    ),
                    _buildLanguageItem(
                      context,
                      ref,
                      S.of(context).languageFa,
                      'fa',
                      current,
                      ctx,
                    ),
                    _buildLanguageItem(
                      context,
                      ref,
                      S.of(context).languageZh,
                      'zh',
                      current,
                      ctx,
                    ),
                    _buildLanguageItem(
                      context,
                      ref,
                      S.of(context).languageJa,
                      'ja',
                      current,
                      ctx,
                    ),
                    _buildLanguageItem(
                      context,
                      ref,
                      S.of(context).languageKo,
                      'ko',
                      current,
                      ctx,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLanguageItem(
    BuildContext context,
    WidgetRef ref,
    String title,
    String value,
    String current,
    BuildContext ctx,
  ) {
    return RadioListTile<String>(
      title: Text(title),
      value: value,
      groupValue: current,
      onChanged: (v) {
        ref.read(settingsProvider.notifier).setLocale(v!);
        Navigator.pop(ctx);
      },
    );
  }
}
