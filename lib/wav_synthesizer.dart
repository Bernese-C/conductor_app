import 'dart:math' as math;
import 'dart:typed_data';

/// Generates a simple 4-bar arpeggio WAV loop.
///
/// Extracted from MidiPlayer so the synthesis logic is reusable.
/// Returns a complete little-endian 16-bit PCM mono WAV file as bytes.

Uint8List generateMelodyWav() {
  const sampleRate = 16000;
  const baseBpm = 120.0;
  const beatDur = 60.0 / baseBpm;

  // C-E-G-C' arpeggio, 2x loop = ~4 s
  const melody = <_MelodyNote>[
    _MelodyNote(60, 0.5), _MelodyNote(64, 0.5), _MelodyNote(67, 0.5), _MelodyNote(72, 0.5),
    _MelodyNote(67, 0.5), _MelodyNote(64, 0.5), _MelodyNote(60, 1.0),
    _MelodyNote(60, 0.5), _MelodyNote(64, 0.5), _MelodyNote(67, 0.5), _MelodyNote(72, 0.5),
    _MelodyNote(67, 0.5), _MelodyNote(64, 0.5), _MelodyNote(60, 1.0),
  ];

  final samples = <int>[];
  final double sr = sampleRate.toDouble();

  for (final note in melody) {
    final double freq = 440.0 * math.pow(2.0, (note.midi - 69) / 12.0);
    final double dur = note.beats * beatDur;
    final int total = (dur * sr).round();
    final int attack = (0.005 * sr).round().clamp(1, total ~/ 2);
    final int release = (0.03 * sr).round().clamp(1, total ~/ 2);
    final int gap = (0.015 * sr).round();

    // Attack
    for (int i = 0; i < attack; i++) {
      final t = i / sr;
      final env = (i / attack) * 0.6;
      final pcm = (math.sin(2.0 * math.pi * freq * t) * env * 12000).round();
      samples.add(pcm.clamp(-32768, 32767));
    }
    // Sustain
    for (int i = attack; i < total - release - gap; i++) {
      final t = i / sr;
      final pcm = (math.sin(2.0 * math.pi * freq * t) * 0.6 * 12000).round();
      samples.add(pcm.clamp(-32768, 32767));
    }
    // Release
    for (int i = total - release - gap; i < total - gap; i++) {
      final t = i / sr;
      final env = 0.6 * (total - gap - i) / release;
      final pcm = (math.sin(2.0 * math.pi * freq * t) * env * 12000).round();
      samples.add(pcm.clamp(-32768, 32767));
    }
    // Gap
    for (int i = 0; i < gap; i++) {
      samples.add(0);
    }
  }

  return _buildWav(samples, sampleRate);
}

Uint8List _buildWav(List<int> samples, int sampleRate) {
  final dataSize = samples.length * 2;
  final fileSize = 44 + dataSize;
  final bytes = ByteData(fileSize);
  int off = 0;

  void u32(int v) { bytes.setUint32(off, v, Endian.little); off += 4; }
  void u16(int v) { bytes.setUint16(off, v, Endian.little); off += 2; }
  void i16(int v) { bytes.setInt16(off, v, Endian.little); off += 2; }

  bytes.setUint8(off++, 0x52); bytes.setUint8(off++, 0x49);
  bytes.setUint8(off++, 0x46); bytes.setUint8(off++, 0x46);
  u32(fileSize - 8);
  bytes.setUint8(off++, 0x57); bytes.setUint8(off++, 0x41);
  bytes.setUint8(off++, 0x56); bytes.setUint8(off++, 0x45);
  bytes.setUint8(off++, 0x66); bytes.setUint8(off++, 0x6D);
  bytes.setUint8(off++, 0x74); bytes.setUint8(off++, 0x20);
  u32(16); u16(1); u16(1);
  u32(sampleRate); u32(sampleRate * 2);
  u16(2); u16(16);
  bytes.setUint8(off++, 0x64); bytes.setUint8(off++, 0x61);
  bytes.setUint8(off++, 0x74); bytes.setUint8(off++, 0x61);
  u32(dataSize);
  for (final s in samples) { i16(s); }

  return bytes.buffer.asUint8List();
}

class _MelodyNote {
  final int midi;
  final double beats;
  const _MelodyNote(this.midi, this.beats);
}
