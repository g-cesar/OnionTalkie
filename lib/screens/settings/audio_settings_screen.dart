import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_settings.dart';
import '../../providers/settings_provider.dart';

class AudioSettingsScreen extends ConsumerWidget {
  const AudioSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(S.of(context).audioSettingsTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Opus Bitrate
          Text(
            S.of(context).opusBitrateLabel,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            S.of(context).bitrateHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Slider(
            value: settings.opusBitrate.toDouble(),
            min: 6,
            max: 64,
            divisions: 10,
            label: '${settings.opusBitrate} kbps',
            onChanged: (value) {
              ref.read(settingsProvider.notifier).setOpusBitrate(value.round());
            },
          ),
          Center(
            child: Text(
              '${settings.opusBitrate} kbps',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
            ),
          ),

          const Divider(height: 32),

          // Sample Rate
          Text(
            S.of(context).sampleRateLabel,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 8000, label: Text('8 kHz')),
              ButtonSegment(value: 16000, label: Text('16 kHz')),
              ButtonSegment(value: 24000, label: Text('24 kHz')),
              ButtonSegment(value: 48000, label: Text('48 kHz')),
            ],
            selected: {settings.sampleRate},
            onSelectionChanged: (values) {
              ref.read(settingsProvider.notifier).setSampleRate(values.first);
            },
          ),

          const Divider(height: 32),

          // PTT Chime
          Text(
            S.of(context).pttSoundLabel,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            S.of(context).pttSoundSubtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          ...PttChimePreset.values.map((preset) {
            return RadioListTile<PttChimePreset>(
              title: Text(_chimeLabel(context, preset)),
              value: preset,
              groupValue: settings.pttChime,
              onChanged: (value) {
                if (value != null) {
                  ref.read(settingsProvider.notifier).setPttChime(value);
                }
              },
            );
          }),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  String _chimeLabel(BuildContext context, PttChimePreset preset) {
    switch (preset) {
      case PttChimePreset.off:
        return S.of(context).soundOff;
      case PttChimePreset.tone:
        return S.of(context).soundTone;
      case PttChimePreset.doubleTone:
        return S.of(context).soundDoubleTone;
      case PttChimePreset.chirp:
        return S.of(context).soundChirp;
      case PttChimePreset.ding:
        return S.of(context).soundDing;
      case PttChimePreset.click:
        return S.of(context).soundClick;
      case PttChimePreset.custom:
        return S.of(context).soundCustom;
    }
  }
}
