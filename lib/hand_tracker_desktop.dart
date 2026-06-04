import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import 'hand_tracker.dart';

/// Desktop hand tracker using in-frame skin-colour detection.
///
/// Opens a camera, samples pixels for skin-colour regions, and streams the
/// centroid Y coordinate.  No native ML dependencies — works immediately
/// on Windows / macOS / Linux.  Falls back to mouse tracking if no camera.
class DesktopCameraTracker implements HandTracker {
  final StreamController<double> _yController =
      StreamController<double>.broadcast();

  CameraController? _cameraController;
  bool _isRunning = false;
  int _frameCount = 0;
  static const int _frameSkip = 1;   // process every 2nd frame
  static const int _pixelStep = 4;   // sample every 4th pixel (16× speed-up)

  @override
  Stream<double> get yStream => _yController.stream;

  @override
  bool get isRunning => _isRunning;

  @override
  Future<void> initialize() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw Exception('No cameras');
      _cameraController = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isWindows
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.nv21,
      );
      await _cameraController!.initialize();
      debugPrint('DesktopCameraTracker: camera ready');
    } catch (e) {
      debugPrint('DesktopCameraTracker: no camera ($e) — mouse only');
    }
  }

  @override
  Future<void> start() async {
    _isRunning = true;
    if (_cameraController != null) {
      try {
        await _cameraController!.startImageStream(_onFrame);
        debugPrint('DesktopCameraTracker: streaming');
      } catch (e) {
        debugPrint('DesktopCameraTracker: no image stream ($e) — '
            'camera preview only, using mouse for tracking');
        // Camera preview works but frame processing doesn't.
        // Mouse tracking handles the actual conducting.
      }
    }
  }

  @override
  Future<void> stop() async {
    _isRunning = false;
    if (_cameraController != null) {
      await _cameraController!.stopImageStream();
    }
  }

  @override
  Future<void> dispose() async {
    _isRunning = false;
    await _cameraController?.dispose();
    _cameraController = null;
    await _yController.close();
  }

  @override
  dynamic get cameraController => _cameraController;

  bool get cameraAvailable =>
      _cameraController != null && _cameraController!.value.isInitialized;

  @override
  String get trackingModeLabel =>
      cameraAvailable ? '📷 手势追踪' : '🖱️ 鼠标';

  /// Mouse fallback.
  void feedY(double mouseLocalY, double widgetHeight) {
    if (!_isRunning || widgetHeight <= 0) return;
    _yController.add((mouseLocalY / widgetHeight).clamp(0.0, 1.0));
  }

  // ── Frame processing ──────────────────────────────────────────────────

  void _onFrame(CameraImage image) {
    _frameCount++;
    if (_frameCount % _frameSkip != 0) return;

    try {
      final y = _detectHandY(image);
      if (y != null) {
        _yController.add(y.clamp(0.0, 1.0));
      }
    } catch (_) {
      // Skip bad frames silently.
    }
  }

  /// Find the Y-centroid of skin-coloured pixels in [image].
  /// Returns a normalised Y (0=top, 1=bottom) or null.
  double? _detectHandY(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final bool isBgra = image.format.raw == 1111970369;

    if (isBgra && image.planes.isNotEmpty) {
      return _detectInBgra(image.planes[0].bytes, width, height,
          image.planes[0].bytesPerRow);
    } else if (image.planes.length >= 3) {
      return _detectInYuv(image.planes[0].bytes, image.planes[1].bytes,
          image.planes[2].bytes, width, height,
          image.planes[0].bytesPerRow, image.planes[1].bytesPerRow,
          image.planes[1].bytesPerPixel ?? 1);
    }
    return null;
  }

  /// Skin detection in BGRA8888 frames (Windows / iOS camera).
  double? _detectInBgra(
      Uint8List bytes, int w, int h, int rowStride) {
    double sumY = 0;
    int count = 0;

    for (int y = 0; y < h; y += _pixelStep) {
      for (int x = 0; x < w; x += _pixelStep) {
        final idx = y * rowStride + x * 4;
        if (idx + 3 >= bytes.length) continue;

        final int b = bytes[idx];
        final int g = bytes[idx + 1];
        final int r = bytes[idx + 2];

        if (_isSkinRgb(r, g, b)) {
          sumY += y;
          count++;
        }
      }
    }

    if (count < 50) return null; // not enough skin pixels — hand not in frame
    return (sumY / count) / h; // normalise to [0, 1]
  }

  /// Skin detection in YUV420 frames (Android / Linux camera).
  double? _detectInYuv(Uint8List yPlane, Uint8List uPlane, Uint8List vPlane,
      int w, int h, int yRowStride, int uvRowStride, int uvPixelStride) {
    double sumY = 0;
    int count = 0;

    for (int y = 0; y < h; y += _pixelStep) {
      for (int x = 0; x < w; x += _pixelStep) {
        final yIdx = y * yRowStride + x;
        final uvIdx = (y ~/ 2) * uvRowStride + (x ~/ 2) * uvPixelStride;

        if (yIdx >= yPlane.length || uvIdx + 1 >= uPlane.length) continue;

        final int yy = yPlane[yIdx];
        final int uu = uPlane[uvIdx];
        final int vv = vPlane[uvIdx];

        // YUV → RGB
        final c = yy - 16;
        final d = uu - 128;
        final e = vv - 128;
        final r = ((298 * c + 409 * e + 128) >> 8).clamp(0, 255);
        final g = ((298 * c - 100 * d - 208 * e + 128) >> 8).clamp(0, 255);
        final b = ((298 * c + 516 * d + 128) >> 8).clamp(0, 255);

        if (_isSkinRgb(r, g, b)) {
          sumY += y;
          count++;
        }
      }
    }

    if (count < 50) return null;
    return (sumY / count) / h;
  }

  /// Simple skin-colour classifier in RGB space.
  ///
  /// Uses well-established thresholds from peer-reviewed skin detection
  /// literature (Kovac et al., 2003).  Works under typical indoor lighting.
  bool _isSkinRgb(int r, int g, int b) {
    // Rule 1: brightness bounds
    if (r <= 95 || g <= 40 || b <= 20) return false;
    // Rule 2: saturation / colour variation
    final maxC = math.max(r, math.max(g, b));
    final minC = math.min(r, math.min(g, b));
    if ((maxC - minC) <= 15) return false;
    // Rule 3: red dominance (skin has more red than blue/green)
    if ((r - g).abs() <= 15) return false;
    if (r <= g || r <= b) return false;
    return true;
  }
}
