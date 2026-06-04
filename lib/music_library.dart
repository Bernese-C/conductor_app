import 'package:flutter/foundation.dart';

/// Type of music source.
enum MusicSourceType { builtIn, url }

/// A music source that can be played by [MidiPlayer].
class MusicSource {
  final String name;
  final MusicSourceType type;
  final String? url;

  const MusicSource({required this.name, required this.type, this.url});

  /// The built-in arpeggio melody.
  static const builtIn = MusicSource(
    name: '内置旋律 (C大调琶音)',
    type: MusicSourceType.builtIn,
  );
}

/// Manages the collection of available music sources.
///
/// Provides a default built-in melody and allows users to add custom URLs.
class MusicLibrary extends ChangeNotifier {
  final List<MusicSource> _sources = [MusicSource.builtIn];
  MusicSource _active = MusicSource.builtIn;
  bool _isLoading = false;
  String? _error;

  /// All available music sources.
  List<MusicSource> get sources => List.unmodifiable(_sources);

  /// The currently active (playing) source.
  MusicSource get activeSource => _active;

  /// Whether a URL is currently being loaded.
  bool get isLoading => _isLoading;

  /// Last error message, if any.
  String? get error => _error;

  /// Add a URL source and set it as active.
  Future<void> addUrl(String name, String url) async {
    _error = null;

    // Basic validation.
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      _error = '无效的 URL';
      notifyListeners();
      return;
    }

    // Check for common audio extensions or audio hosting patterns.
    final lower = url.toLowerCase();
    final validExts = ['.mp3', '.wav', '.ogg', '.m4a', '.aac', '.flac', '.wma', '.opus'];
    final looksLikeAudio = validExts.any((e) => lower.contains(e)) ||
        lower.contains('audio') ||
        lower.contains('soundcloud') ||
        lower.contains('music.163.com'); // NetEase direct links contain this

    if (!looksLikeAudio) {
      _error = '该 URL 似乎不是直接音频文件。请使用 .mp3/.wav 等直链。\n'
          '哔哩哔哩/网易云页面链接无法直接播放。';
      notifyListeners();
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      final source = MusicSource(name: name, type: MusicSourceType.url, url: url);
      // Replace existing URL source with same URL, or add new.
      final existing = _sources.indexWhere(
          (s) => s.type == MusicSourceType.url && s.url == url);
      if (existing >= 0) {
        _sources[existing] = source;
      } else {
        _sources.add(source);
      }
      _active = source;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = '加载失败: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Switch to a different source.
  void selectSource(MusicSource source) {
    if (_active.url == source.url && _active.type == source.type) return;
    _active = source;
    _error = null;
    notifyListeners();
  }

  /// Remove a URL source (cannot remove built-in).
  void removeSource(MusicSource source) {
    if (source.type == MusicSourceType.builtIn) return;
    _sources.remove(source);
    if (_active.url == source.url) {
      _active = MusicSource.builtIn;
    }
    notifyListeners();
  }

  /// Clear error state.
  void clearError() {
    _error = null;
    notifyListeners();
  }
}
