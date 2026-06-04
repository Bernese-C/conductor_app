import 'package:flutter/foundation.dart';

import 'audio_platform.dart';
import 'music_library.dart';
import 'wav_synthesizer.dart';

/// Cross-platform melody player with speed and volume control.
///
/// Supports both the built-in WAV melody and external HTTP audio URLs.
/// Playback is managed via the conditional [audio_platform] backend.
class MidiPlayer {
  bool _isInitialized = false;
  bool _isPlaying = false;

  double _currentSpeed = 1.0;
  double _currentVolume = 0.5;

  MusicSource? _currentSource;

  bool get isPlaying => _isPlaying;
  MusicSource? get currentSource => _currentSource;

  // ── Public API ──────────────────────────────────────────────────────────

  /// Initialize with the active source from [MusicLibrary].
  Future<void> initialize({MusicSource? source}) async {
    final src = source ?? MusicSource.builtIn;
    await _loadSourceInternal(src);
    _isInitialized = true;
  }

  /// Hot-swap to a different music source.
  Future<void> loadSource(MusicSource source) async {
    if (!_isInitialized) {
      _currentSource = source;
      return;
    }
    final wasPlaying = _isPlaying;
    await _loadSourceInternal(source);
    if (wasPlaying) {
      platformPlay();
      _isPlaying = true;
    }
  }

  Future<void> _loadSourceInternal(MusicSource source) async {
    try {
      if (source.type == MusicSourceType.url && source.url != null) {
        await platformLoadUrl(source.url!);
      } else {
        // Built-in: generate the WAV from our synthesizer.
        final wav = generateMelodyWav();
        await platformInit(wav);
      }
      _currentSource = source;
      debugPrint('MidiPlayer: loaded "${source.name}"');
    } catch (e) {
      debugPrint('MidiPlayer load error: $e');
      rethrow;
    }
  }

  Future<void> play() async {
    if (!_isInitialized) await initialize();
    if (_isPlaying) return;
    platformPlay();
    _isPlaying = true;
  }

  Future<void> pause() async {
    if (!_isPlaying) return;
    platformPause();
    _isPlaying = false;
  }

  Future<void> stop() async {
    platformStop();
    _isPlaying = false;
  }

  Future<void> dispose() async {
    platformDispose();
    _isInitialized = false;
    _isPlaying = false;
  }

  Future<void> setSpeed(double rate) async {
    final clamped = rate.clamp(0.5, 2.0);
    if ((clamped - _currentSpeed).abs() < 0.01) return;
    _currentSpeed = clamped;
    platformSetSpeed(clamped);
  }

  Future<void> setVolume(double vol) async {
    final clamped = vol.clamp(0.0, 1.0);
    if ((clamped - _currentVolume).abs() < 0.01) return;
    _currentVolume = clamped;
    platformSetVolume(clamped);
  }

  Future<void> syncToConductor(double bpm, double volume) async {
    if (!_isInitialized || !_isPlaying) return;
    await Future.wait([
      setSpeed(bpm / 120.0),
      setVolume(volume),
    ]);
  }
}
