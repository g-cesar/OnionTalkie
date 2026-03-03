import 'dart:math';
import 'dart:typed_data';

import '../models/app_settings.dart';

/// PTT chime tone generator.
///
/// Generates synthetic audio tones for Push-to-Talk chime sounds,
/// matching the bash script's sox-generated tones.
class ChimeService {
  ChimeService._();

  /// Generate chime PCM audio data based on the preset.
  ///
  /// Returns 16-bit PCM audio data at [sampleRate] Hz, mono.
  /// Returns null if the chime is off.
  static Uint8List? generateChime(PttChimePreset preset, int sampleRate) {
    switch (preset) {
      case PttChimePreset.off:
        return null;
      case PttChimePreset.tone:
        return _generateTone(sampleRate, 800, 0.20);
      case PttChimePreset.doubleTone:
        return _generateDoubleTone(sampleRate);
      case PttChimePreset.chirp:
        return _generateChirp(sampleRate, 500, 1200, 0.15);
      case PttChimePreset.ding:
        return _generateDing(sampleRate, 1200, 0.30);
      case PttChimePreset.click:
        return _generateClick(sampleRate, 0.05);
      case PttChimePreset.custom:
        // For custom, generate a neutral beep — custom recording
        // would use recorded audio instead of this.
        return _generateTone(sampleRate, 660, 0.15);
    }
  }

  /// Generate a simple sine wave tone.
  static Uint8List _generateTone(
      int sampleRate, double frequency, double durationSec) {
    final numSamples = (sampleRate * durationSec).round();
    final samples = Int16List(numSamples);
    final amplitude = 0.6;

    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      // Apply fade in/out envelope (10ms)
      final fadeLength = (sampleRate * 0.01).round();
      double envelope = 1.0;
      if (i < fadeLength) {
        envelope = i / fadeLength;
      } else if (i > numSamples - fadeLength) {
        envelope = (numSamples - i) / fadeLength;
      }

      samples[i] =
          (sin(2 * pi * frequency * t) * amplitude * envelope * 32767).round();
    }

    return samples.buffer.asUint8List();
  }

  /// Generate a double tone (600Hz 100ms + silence 30ms + 900Hz 150ms).
  static Uint8List _generateDoubleTone(int sampleRate) {
    final tone1 = _generateTone(sampleRate, 600, 0.10);
    final silence = Uint8List((sampleRate * 0.03 * 2).round()); // 30ms silence
    final tone2 = _generateTone(sampleRate, 900, 0.15);

    final combined = Uint8List(tone1.length + silence.length + tone2.length);
    combined.setAll(0, tone1);
    combined.setAll(tone1.length, silence);
    combined.setAll(tone1.length + silence.length, tone2);
    return combined;
  }

  /// Generate a chirp (frequency sweep from startFreq to endFreq).
  static Uint8List _generateChirp(
      int sampleRate, double startFreq, double endFreq, double durationSec) {
    final numSamples = (sampleRate * durationSec).round();
    final samples = Int16List(numSamples);
    final amplitude = 0.6;

    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      final progress = i / numSamples;
      final freq = startFreq + (endFreq - startFreq) * progress;

      double envelope = 1.0;
      final fadeLength = (sampleRate * 0.01).round();
      if (i < fadeLength) {
        envelope = i / fadeLength;
      } else if (i > numSamples - fadeLength) {
        envelope = (numSamples - i) / fadeLength;
      }

      samples[i] =
          (sin(2 * pi * freq * t) * amplitude * envelope * 32767).round();
    }

    return samples.buffer.asUint8List();
  }

  /// Generate a ding (plucked string simulation with exponential decay).
  static Uint8List _generateDing(
      int sampleRate, double frequency, double durationSec) {
    final numSamples = (sampleRate * durationSec).round();
    final samples = Int16List(numSamples);
    final amplitude = 0.7;

    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      // Exponential decay
      final decay = exp(-t * 10.0);
      // Mix fundamental with harmonics for metallic sound
      final fundamental = sin(2 * pi * frequency * t);
      final harmonic2 = sin(2 * pi * frequency * 2 * t) * 0.5;
      final harmonic3 = sin(2 * pi * frequency * 3 * t) * 0.25;
      final mix = fundamental + harmonic2 + harmonic3;

      samples[i] =
          (mix / 1.75 * amplitude * decay * 32767).round().clamp(-32767, 32767);
    }

    return samples.buffer.asUint8List();
  }

  /// Generate a click (short burst of filtered noise).
  static Uint8List _generateClick(int sampleRate, double durationSec) {
    final numSamples = (sampleRate * durationSec).round();
    final samples = Int16List(numSamples);
    final amplitude = 0.5;
    final random = Random(42); // Deterministic for consistency

    for (int i = 0; i < numSamples; i++) {
      final decay = exp(-i / numSamples * 8.0);
      final noise = random.nextDouble() * 2.0 - 1.0;
      samples[i] = (noise * amplitude * decay * 32767).round();
    }

    return samples.buffer.asUint8List();
  }
}
