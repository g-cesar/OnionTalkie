import 'dart:math';
import 'dart:typed_data';

import '../models/app_settings.dart';

/// DSP voice effect processor that operates on raw PCM int16 samples.
///
/// Implements the same voice effects as the bash script's sox pipeline:
/// pitch shifting, overdrive, flanger, echo, highpass filter, and tremolo.
class VoiceProcessor {
  VoiceProcessor._();

  /// Apply voice effects to PCM audio data based on the preset.
  ///
  /// [pcmData] is raw 16-bit PCM audio (mono).
  /// [sampleRate] is the audio sample rate in Hz.
  static Uint8List applyPreset(
    Uint8List pcmData,
    VoiceChangerPreset preset,
    int sampleRate, {
    double customPitch = 0,
    double customOverdrive = 0,
    double customFlanger = 0,
    double customEcho = 0,
    double customHighpass = 0,
    double customTremolo = 0,
  }) {
    if (preset == VoiceChangerPreset.off) return pcmData;

    var samples = _toFloat64(pcmData);

    switch (preset) {
      case VoiceChangerPreset.deep:
        samples = _pitchShift(samples, sampleRate, -300);
        samples = _overdrive(samples, 5.0, 5.0);
        break;
      case VoiceChangerPreset.high:
        samples = _pitchShift(samples, sampleRate, 500);
        break;
      case VoiceChangerPreset.robot:
        samples = _overdrive(samples, 30.0, 20.0);
        samples = _flanger(samples, sampleRate, 0, 5, 0, 70, 0.5);
        samples = _echo(samples, sampleRate, 0.6, 0.7, 10, 0.8);
        break;
      case VoiceChangerPreset.echo:
        samples = _echo(samples, sampleRate, 0.8, 0.9, 50, 0.7);
        samples = _echo(samples, sampleRate, 0.8, 0.3, 100, 0.5);
        break;
      case VoiceChangerPreset.whisper:
        samples = _highpass(samples, sampleRate, 1000.0);
        samples = _overdrive(samples, 5.0, 5.0);
        samples = _tremolo(samples, sampleRate, 5.0, 100.0);
        break;
      case VoiceChangerPreset.custom:
        if (customPitch != 0) {
          samples = _pitchShift(samples, sampleRate, customPitch * 600 - 300);
        }
        if (customOverdrive > 0) {
          samples = _overdrive(samples, customOverdrive * 40, customOverdrive * 20);
        }
        if (customFlanger > 0) {
          samples = _flanger(
              samples, sampleRate, 0, customFlanger * 10, 0, 70, 0.5);
        }
        if (customEcho > 0) {
          samples = _echo(
              samples, sampleRate, 0.8, customEcho, (customEcho * 100).toInt(), 0.7);
        }
        if (customHighpass > 0) {
          samples = _highpass(samples, sampleRate, customHighpass * 4000);
        }
        if (customTremolo > 0) {
          samples = _tremolo(samples, sampleRate, customTremolo * 10, 100);
        }
        break;
      case VoiceChangerPreset.off:
        break;
    }

    return _toInt16(samples);
  }

  /// Convert PCM bytes (int16) to Float64List for processing.
  static Float64List _toFloat64(Uint8List pcmBytes) {
    final int16 = pcmBytes.buffer.asInt16List();
    final result = Float64List(int16.length);
    for (int i = 0; i < int16.length; i++) {
      result[i] = int16[i] / 32768.0;
    }
    return result;
  }

  /// Convert Float64List back to PCM bytes (int16).
  static Uint8List _toInt16(Float64List samples) {
    final int16 = Int16List(samples.length);
    for (int i = 0; i < samples.length; i++) {
      int16[i] = (samples[i].clamp(-1.0, 1.0) * 32767).round();
    }
    return int16.buffer.asUint8List();
  }

  /// Pitch shift by resampling.
  ///
  /// [cents] is the pitch shift in cents (e.g., -300 for lower, 500 for higher).
  static Float64List _pitchShift(
      Float64List samples, int sampleRate, double cents) {
    // Convert cents to ratio: ratio = 2^(cents/1200)
    final ratio = pow(2.0, cents / 1200.0).toDouble();
    final newLength = (samples.length / ratio).round();
    if (newLength <= 0) return Float64List(0);

    final result = Float64List(newLength);
    for (int i = 0; i < newLength; i++) {
      final srcPos = i * ratio;
      final srcIndex = srcPos.floor();
      final frac = srcPos - srcIndex;

      if (srcIndex + 1 < samples.length) {
        result[i] =
            samples[srcIndex] * (1.0 - frac) + samples[srcIndex + 1] * frac;
      } else if (srcIndex < samples.length) {
        result[i] = samples[srcIndex];
      }
    }
    return result;
  }

  /// Overdrive / distortion effect.
  ///
  /// [gain] controls input amplification. [color] controls tone shaping.
  static Float64List _overdrive(
      Float64List samples, double gain, double color) {
    final g = gain.clamp(1.0, 100.0);
    final colorFactor = (color / 100.0).clamp(0.0, 1.0);
    final result = Float64List(samples.length);

    for (int i = 0; i < samples.length; i++) {
      double s = samples[i] * g;
      // Soft clipping (tanh-like)
      s = s / (1.0 + s.abs());
      // Color: mix with squared signal
      s = s * (1.0 - colorFactor) + (s * s.abs()) * colorFactor;
      result[i] = s.clamp(-1.0, 1.0);
    }
    return result;
  }

  /// Flanger effect.
  ///
  /// Creates a swept comb-filter effect by mixing with a delayed copy.
  static Float64List _flanger(
    Float64List samples,
    int sampleRate,
    double delayMs,
    double depthMs,
    double regenPercent,
    double widthPercent,
    double speed,
  ) {
    final maxDelaySamples =
        ((delayMs + depthMs) * sampleRate / 1000.0).round();
    if (maxDelaySamples <= 0) return samples;

    final result = Float64List(samples.length);
    final regen = regenPercent / 100.0;
    final width = widthPercent / 100.0;
    final delayBase = delayMs * sampleRate / 1000.0;
    final depth = depthMs * sampleRate / 1000.0;

    // Use a buffer for the delayed signal with feedback
    final delayBuffer = Float64List(samples.length + maxDelaySamples);
    for (int i = 0; i < samples.length; i++) {
      delayBuffer[i + maxDelaySamples] = samples[i];
    }

    for (int i = 0; i < samples.length; i++) {
      final lfoPhase = 2.0 * pi * speed * i / sampleRate;
      final lfo = (sin(lfoPhase) + 1.0) / 2.0; // 0..1
      final currentDelay = delayBase + depth * lfo;
      final delaySamples = currentDelay.round();

      final delayedIdx = i + maxDelaySamples - delaySamples;
      double delayed = 0;
      if (delayedIdx >= 0 && delayedIdx < delayBuffer.length) {
        delayed = delayBuffer[delayedIdx];
      }

      result[i] = samples[i] * (1.0 - width) + delayed * width;
      // Feedback
      if (i + maxDelaySamples < delayBuffer.length) {
        delayBuffer[i + maxDelaySamples] += delayed * regen;
      }
    }
    return result;
  }

  /// Echo / delay effect.
  ///
  /// [gainIn] input gain, [gainOut] output gain,
  /// [delayMs] delay time, [decay] feedback decay.
  static Float64List _echo(
    Float64List samples,
    int sampleRate,
    double gainIn,
    double gainOut,
    int delayMs,
    double decay,
  ) {
    final delaySamples = (delayMs * sampleRate / 1000.0).round();
    if (delaySamples <= 0) return samples;

    final result = Float64List(samples.length);
    for (int i = 0; i < samples.length; i++) {
      double s = samples[i] * gainIn;
      if (i >= delaySamples) {
        s += result[i - delaySamples] * decay * gainOut;
      }
      result[i] = s.clamp(-1.0, 1.0);
    }
    return result;
  }

  /// First-order highpass filter.
  ///
  /// [cutoffHz] is the cutoff frequency.
  static Float64List _highpass(
      Float64List samples, int sampleRate, double cutoffHz) {
    if (cutoffHz <= 0) return samples;

    final rc = 1.0 / (2.0 * pi * cutoffHz);
    final dt = 1.0 / sampleRate;
    final alpha = rc / (rc + dt);

    final result = Float64List(samples.length);
    if (samples.isEmpty) return result;

    result[0] = samples[0];
    for (int i = 1; i < samples.length; i++) {
      result[i] = alpha * (result[i - 1] + samples[i] - samples[i - 1]);
    }
    return result;
  }

  /// Tremolo effect (amplitude modulation by LFO).
  ///
  /// [speed] LFO frequency in Hz. [depth] modulation depth percentage.
  static Float64List _tremolo(
      Float64List samples, int sampleRate, double speed, double depth) {
    final d = (depth / 100.0).clamp(0.0, 1.0);
    final result = Float64List(samples.length);

    for (int i = 0; i < samples.length; i++) {
      final lfo = sin(2.0 * pi * speed * i / sampleRate);
      final mod = 1.0 - d * (lfo + 1.0) / 2.0; // 1.0 .. (1-d)
      result[i] = samples[i] * mod;
    }
    return result;
  }
}
