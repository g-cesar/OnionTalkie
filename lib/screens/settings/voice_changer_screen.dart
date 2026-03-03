import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_settings.dart';
import '../../providers/settings_provider.dart';

class VoiceChangerScreen extends ConsumerWidget {
  const VoiceChangerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice Changer'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Effetti vocali applicati all\'audio in uscita prima della codifica Opus.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),

          // Presets
          ...VoiceChangerPreset.values.map((preset) {
            return RadioListTile<VoiceChangerPreset>(
              title: Text(_presetLabel(preset)),
              subtitle: Text(_presetDescription(preset)),
              value: preset,
              groupValue: settings.voiceChangerPreset,
              onChanged: (value) {
                if (value != null) {
                  ref.read(settingsProvider.notifier).setVoiceChangerPreset(value);
                }
              },
              secondary: Icon(
                _presetIcon(preset),
                color: settings.voiceChangerPreset == preset
                    ? theme.colorScheme.primary
                    : null,
              ),
            );
          }),

          // Custom settings
          if (settings.voiceChangerPreset == VoiceChangerPreset.custom) ...[
            const Divider(height: 32),
            Text(
              'Parametri personalizzati',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),

            _buildSlider(
              theme,
              'Pitch Shift',
              settings.customPitchShift,
              -12,
              12,
              (v) => ref.read(settingsProvider.notifier).updateSettings(
                settings.copyWith(customPitchShift: v),
              ),
            ),
            _buildSlider(
              theme,
              'Overdrive',
              settings.customOverdrive,
              0,
              100,
              (v) => ref.read(settingsProvider.notifier).updateSettings(
                settings.copyWith(customOverdrive: v),
              ),
            ),
            _buildSlider(
              theme,
              'Flanger',
              settings.customFlanger,
              0,
              100,
              (v) => ref.read(settingsProvider.notifier).updateSettings(
                settings.copyWith(customFlanger: v),
              ),
            ),
            _buildSlider(
              theme,
              'Echo',
              settings.customEcho,
              0,
              100,
              (v) => ref.read(settingsProvider.notifier).updateSettings(
                settings.copyWith(customEcho: v),
              ),
            ),
            _buildSlider(
              theme,
              'Highpass Filter',
              settings.customHighpass,
              0,
              4000,
              (v) => ref.read(settingsProvider.notifier).updateSettings(
                settings.copyWith(customHighpass: v),
              ),
            ),
            _buildSlider(
              theme,
              'Tremolo',
              settings.customTremolo,
              0,
              100,
              (v) => ref.read(settingsProvider.notifier).updateSettings(
                settings.copyWith(customTremolo: v),
              ),
            ),
          ],

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSlider(
    ThemeData theme,
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: theme.textTheme.bodyMedium),
              Text(
                value.toStringAsFixed(1),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  String _presetLabel(VoiceChangerPreset preset) {
    switch (preset) {
      case VoiceChangerPreset.off:
        return 'Disattivato';
      case VoiceChangerPreset.deep:
        return 'Voce profonda';
      case VoiceChangerPreset.high:
        return 'Voce alta';
      case VoiceChangerPreset.robot:
        return 'Robot';
      case VoiceChangerPreset.echo:
        return 'Echo';
      case VoiceChangerPreset.whisper:
        return 'Sussurro';
      case VoiceChangerPreset.custom:
        return 'Personalizzato';
    }
  }

  String _presetDescription(VoiceChangerPreset preset) {
    switch (preset) {
      case VoiceChangerPreset.off:
        return 'Nessun effetto applicato';
      case VoiceChangerPreset.deep:
        return 'Abbassa il tono della voce';
      case VoiceChangerPreset.high:
        return 'Alza il tono della voce';
      case VoiceChangerPreset.robot:
        return 'Effetto robotico con modulazione';
      case VoiceChangerPreset.echo:
        return 'Aggiunge riverbero e eco';
      case VoiceChangerPreset.whisper:
        return 'Effetto sussurro con filtro passa-alto';
      case VoiceChangerPreset.custom:
        return 'Configura ogni parametro manualmente';
    }
  }

  IconData _presetIcon(VoiceChangerPreset preset) {
    switch (preset) {
      case VoiceChangerPreset.off:
        return Icons.voice_over_off;
      case VoiceChangerPreset.deep:
        return Icons.arrow_downward;
      case VoiceChangerPreset.high:
        return Icons.arrow_upward;
      case VoiceChangerPreset.robot:
        return Icons.smart_toy;
      case VoiceChangerPreset.echo:
        return Icons.surround_sound;
      case VoiceChangerPreset.whisper:
        return Icons.air;
      case VoiceChangerPreset.custom:
        return Icons.tune;
    }
  }
}
