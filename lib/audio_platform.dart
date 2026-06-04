// Single conditional import: picks the right audio backend.
// Priority: html > io > stub
export 'audio_platform_stub.dart'
    if (dart.library.html) 'audio_platform_web.dart'
    if (dart.library.io) 'audio_platform_native.dart';
