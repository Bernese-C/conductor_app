import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

final AudioPlayer _player = AudioPlayer();
bool _ready = false;
File? _tempFile;

Future<void> platformInit(Uint8List wavBytes) async {
  await _player.stop();
  // Clean up previous temp file.
  _tempFile?.deleteSync();
  _tempFile = null;

  // Write WAV to a temporary file — Windows audioplayers doesn't
  // support data URIs, only file paths.
  final dir = Directory.systemTemp;
  _tempFile = File('${dir.path}/conductor_melody.wav');
  await _tempFile!.writeAsBytes(wavBytes);

  await _player.setSource(DeviceFileSource(_tempFile!.path));
  await _player.setReleaseMode(ReleaseMode.loop);
  _ready = true;
  debugPrint('audio_native: ready (temp file)');
}

void platformPlay() {
  if (_ready) _player.resume();
}

void platformPause() => _player.pause();
void platformStop() => _player.stop();

void platformDispose() {
  _ready = false;
  _tempFile?.deleteSync();
  _tempFile = null;
  _player.dispose();
}

void platformSetSpeed(double rate) => _player.setPlaybackRate(rate);
void platformSetVolume(double vol) => _player.setVolume(vol);

Future<void> platformLoadUrl(String url) async {
  await _player.stop();
  await _player.setSource(UrlSource(url));
  await _player.setReleaseMode(ReleaseMode.loop);
  _ready = true;
  debugPrint('audio_native: loaded URL');
}
