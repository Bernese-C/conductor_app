// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// HTML5 Audio element — blob URL from WAV bytes.

html.AudioElement? _el;
String? _blobUrl;

Future<void> platformInit(Uint8List wavBytes) async {
  platformDispose();
  final c = Completer<void>();

  final blob = html.Blob([wavBytes], 'audio/wav');
  _blobUrl = html.Url.createObjectUrl(blob);
  debugPrint('audio: blob URL ready (${wavBytes.length} bytes)');

  _el = html.AudioElement(_blobUrl!)
    ..loop = true
    ..autoplay = false
    ..preload = 'auto'
    ..style.display = 'none';

  _el!.onCanPlay.listen((_) {
    if (!c.isCompleted) c.complete();
  });
  _el!.onError.listen((_) {
    if (!c.isCompleted) c.completeError('load error');
  });

  html.document.body?.append(_el!);

  try {
    await c.future.timeout(const Duration(seconds: 5));
  } catch (_) {
    // continue even on timeout
  }
}

void platformPlay() {
  _el?.play();
  debugPrint('audio: play()');
}

void platformPause() => _el?.pause();
void platformStop() {
  _el?.pause();
  if (_el != null) _el!.currentTime = 0;
}

void platformDispose() {
  _el?.onCanPlay.drain();
  _el?.onError.drain();
  _el?.pause();
  _el?.remove();
  _el = null;
  if (_blobUrl != null) {
    html.Url.revokeObjectUrl(_blobUrl!);
    _blobUrl = null;
  }
}

void platformSetSpeed(double rate) {
  if (_el != null) _el!.playbackRate = rate;
}

void platformSetVolume(double vol) {
  if (_el != null) _el!.volume = vol;
}

Future<void> platformLoadUrl(String url) async {
  platformDispose();
  _el = html.AudioElement(url)
    ..loop = true
    ..autoplay = false
    ..preload = 'auto'
    ..style.display = 'none'
    ..crossOrigin = 'anonymous';
  html.document.body?.append(_el!);
  debugPrint('audio_web: loaded URL');
}
