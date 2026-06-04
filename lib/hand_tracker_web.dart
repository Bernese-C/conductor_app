import 'dart:async';

import 'hand_tracker.dart';

/// Creates a mouse-based tracker for web builds.
HandTracker createPlatformTracker() => WebMouseTracker();

// ═════════════════════════════════════════════════════════════════════════════
// WEB — Mouse Y simulation (browser)
// ═════════════════════════════════════════════════════════════════════════════

class WebMouseTracker implements HandTracker {
  final StreamController<double> _yController =
      StreamController<double>.broadcast();

  bool _isRunning = false;

  @override
  Stream<double> get yStream => _yController.stream;

  @override
  bool get isRunning => _isRunning;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> start() async { _isRunning = true; }

  @override
  Future<void> stop() async { _isRunning = false; }

  @override
  Future<void> dispose() async {
    _isRunning = false;
    await _yController.close();
  }

  @override
  dynamic get cameraController => null;

  @override
  String get trackingModeLabel => '🖱️ 鼠标';

  /// Feed a mouse Y position with widget height for normalisation.
  void feedY(double mouseLocalY, double widgetHeight) {
    if (!_isRunning || widgetHeight <= 0) return;
    _yController.add((mouseLocalY / widgetHeight).clamp(0.0, 1.0));
  }
}
