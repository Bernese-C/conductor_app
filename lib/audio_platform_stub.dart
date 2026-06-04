import 'dart:typed_data';

// Default stub — no-op audio (used when neither web nor native conditions match).

Future<void> platformInit(Uint8List wavBytes) async {}
void platformPlay() {}
void platformPause() {}
void platformStop() {}
void platformDispose() {}
void platformSetSpeed(double rate) {}
void platformSetVolume(double vol) {}
Future<void> platformLoadUrl(String url) async {}
