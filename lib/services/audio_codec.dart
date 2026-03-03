import 'dart:typed_data';

/// IMA ADPCM audio codec for voice compression.
///
/// Compresses 16-bit PCM to 4-bit ADPCM samples (4:1 ratio).
/// Standard IMA/DVI ADPCM algorithm used widely for voice applications.
class AudioCodec {
  AudioCodec._();

  /// Magic header to identify ADPCM-compressed audio.
  static const List<int> adpcmMagic = [0x41, 0x44, 0x50, 0x43]; // "ADPC"

  /// IMA ADPCM step size table.
  static const List<int> _stepTable = [
    7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31,
    34, 37, 41, 45, 50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 130, 143,
    157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494, 544,
    598, 658, 724, 796, 876, 963, 1060, 1166, 1282, 1411, 1552, 1707,
    1878, 2066, 2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871,
    5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635,
    13899, 15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794,
    32767,
  ];

  /// IMA ADPCM index adjustment table.
  static const List<int> _indexTable = [
    -1, -1, -1, -1, 2, 4, 6, 8,
    -1, -1, -1, -1, 2, 4, 6, 8,
  ];

  /// Check if audio data is ADPCM-compressed (has magic header).
  static bool isCompressed(Uint8List data) {
    if (data.length < 4) return false;
    return data[0] == adpcmMagic[0] &&
        data[1] == adpcmMagic[1] &&
        data[2] == adpcmMagic[2] &&
        data[3] == adpcmMagic[3];
  }

  /// Encode 16-bit PCM samples to IMA ADPCM.
  ///
  /// Format: [magic(4)] [predictor(2)] [stepIndex(1)] [sampleCount(4)] [adpcm nibbles...]
  static Uint8List encode(Uint8List pcmData) {
    final samples = pcmData.buffer.asInt16List();
    final sampleCount = samples.length;

    // Each sample produces 4 bits -> 2 samples per byte
    final adpcmSize = (sampleCount + 1) ~/ 2;
    // Header: 4 (magic) + 2 (predictor) + 1 (stepIndex) + 4 (sampleCount)
    final headerSize = 11;
    final output = Uint8List(headerSize + adpcmSize);

    // Write magic
    output.setAll(0, adpcmMagic);

    int predictor = samples.isNotEmpty ? samples[0] : 0;
    int stepIndex = 0;

    // Write initial predictor (little-endian int16)
    final bd = ByteData.sublistView(output);
    bd.setInt16(4, predictor, Endian.little);
    output[6] = stepIndex;

    // Write sample count (little-endian uint32)
    bd.setUint32(7, sampleCount, Endian.little);

    int outputIndex = headerSize;
    bool highNibble = false;

    for (int i = 0; i < sampleCount; i++) {
      final sample = samples[i];
      final step = _stepTable[stepIndex];

      int diff = sample - predictor;
      int nibble = 0;

      if (diff < 0) {
        nibble = 8;
        diff = -diff;
      }

      if (diff >= step) {
        nibble |= 4;
        diff -= step;
      }
      if (diff >= (step >> 1)) {
        nibble |= 2;
        diff -= (step >> 1);
      }
      if (diff >= (step >> 2)) {
        nibble |= 1;
      }

      // Update predictor
      int delta = (step >> 3);
      if (nibble & 4 != 0) delta += step;
      if (nibble & 2 != 0) delta += (step >> 1);
      if (nibble & 1 != 0) delta += (step >> 2);

      if (nibble & 8 != 0) {
        predictor -= delta;
      } else {
        predictor += delta;
      }
      predictor = predictor.clamp(-32768, 32767);

      // Update step index
      stepIndex = (stepIndex + _indexTable[nibble]).clamp(0, 88);

      // Pack nibbles into bytes
      if (!highNibble) {
        output[outputIndex] = nibble & 0x0F;
        highNibble = true;
      } else {
        output[outputIndex] |= (nibble << 4) & 0xF0;
        outputIndex++;
        highNibble = false;
      }
    }

    return Uint8List.sublistView(output, 0, highNibble ? outputIndex + 1 : outputIndex);
  }

  /// Decode IMA ADPCM back to 16-bit PCM.
  static Uint8List decode(Uint8List adpcmData) {
    if (adpcmData.length < 11) {
      throw ArgumentError('ADPCM data too short');
    }

    final bd = ByteData.sublistView(adpcmData);
    int predictor = bd.getInt16(4, Endian.little);
    int stepIndex = adpcmData[6];
    final sampleCount = bd.getUint32(7, Endian.little);

    final pcmSamples = Int16List(sampleCount);
    int inputIndex = 11;
    bool highNibble = false;

    for (int i = 0; i < sampleCount; i++) {
      int nibble;
      if (!highNibble) {
        nibble = adpcmData[inputIndex] & 0x0F;
        highNibble = true;
      } else {
        nibble = (adpcmData[inputIndex] >> 4) & 0x0F;
        inputIndex++;
        highNibble = false;
      }

      final step = _stepTable[stepIndex];

      int delta = (step >> 3);
      if (nibble & 4 != 0) delta += step;
      if (nibble & 2 != 0) delta += (step >> 1);
      if (nibble & 1 != 0) delta += (step >> 2);

      if (nibble & 8 != 0) {
        predictor -= delta;
      } else {
        predictor += delta;
      }
      predictor = predictor.clamp(-32768, 32767);

      pcmSamples[i] = predictor;

      stepIndex = (stepIndex + _indexTable[nibble]).clamp(0, 88);
    }

    return pcmSamples.buffer.asUint8List();
  }
}
