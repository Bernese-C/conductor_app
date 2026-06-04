import 'package:flutter/foundation.dart';

// Conditional import: dart:io is NOT available on web.
import 'hand_tracker_web.dart'
    if (dart.library.io) 'hand_tracker_io.dart';

/// Abstract interface for a hand-position tracker.
abstract class HandTracker {
  Stream<double> get yStream;
  bool get isRunning;
  Future<void> initialize();
  Future<void> start();
  Future<void> stop();
  Future<void> dispose();

  /// Returns a [CameraController] if this tracker uses the device camera.
  /// Defaults to null (desktop / web mouse trackers have no camera).
  dynamic get cameraController => null;

  /// Human-readable tracking mode label for the UI.
  String get trackingModeLabel => '鼠标';
}

/// Create the appropriate [HandTracker] for the current platform.
HandTracker createHandTracker() => createPlatformTracker();

/// Returns true if we are on a desktop / mouse-emulated platform.
bool get isDesktopPlatform => kIsWeb || !_isMobile;

/// Checked lazily to avoid dart:io on web.
bool get _isMobile {
  try {
    // Only dart:io code here — skipped on web thanks to lazy getter.
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
  } catch (_) {
    return false;
  }
}
