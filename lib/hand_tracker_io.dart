import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_ml_kit/google_ml_kit.dart';

import 'hand_tracker.dart';
import 'hand_tracker_desktop.dart';

/// Creates a platform-appropriate tracker for native (mobile / desktop) builds.
HandTracker createPlatformTracker() {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    return DesktopCameraTracker();
  }
  return MobileHandTracker();
}

// ═════════════════════════════════════════════════════════════════════════════
// MOBILE — Camera + Google ML Kit Pose Detection
// ═════════════════════════════════════════════════════════════════════════════

class MobileHandTracker implements HandTracker {
  CameraController? _cameraController;
  PoseDetector? _poseDetector;
  final StreamController<double> _yController =
      StreamController<double>.broadcast();

  bool _isRunning = false;
  int _frameCount = 0;
  static const int _frameSkip = 3;

  @override
  Stream<double> get yStream => _yController.stream;

  @override
  bool get isRunning => _isRunning;

  @override
  Future<void> initialize() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) throw Exception('No cameras available');

    final frontCamera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    _cameraController = CameraController(
      frontCamera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isIOS
          ? ImageFormatGroup.bgra8888
          : ImageFormatGroup.nv21,
    );

    await _cameraController!.initialize();

    _poseDetector = PoseDetector(
      options: PoseDetectorOptions(
        mode: PoseDetectionMode.stream,
        model: PoseDetectionModel.base,
      ),
    );
  }

  @override
  Future<void> start() async {
    if (_isRunning || _cameraController == null) return;
    _isRunning = true;
    await _cameraController!.startImageStream(_onFrame);
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
    await stop();
    await _cameraController?.dispose();
    _cameraController = null;
    await _poseDetector?.close();
    _poseDetector = null;
    await _yController.close();
  }

  @override
  CameraController? get cameraController => _cameraController;

  @override
  String get trackingModeLabel => '📷 ML Kit';

  void _onFrame(CameraImage image) {
    _frameCount++;
    if (_frameCount % _frameSkip != 0) return;

    final inputImage = _cameraImageToInputImage(image);
    if (inputImage == null) return;

    _poseDetector?.processImage(inputImage).then(_onPoses).catchError(
      (e) => debugPrint('Pose detection error: $e'),
    );
  }

  void _onPoses(List<Pose> poses) {
    if (poses.isEmpty) return;
    final pose = poses.first;

    PoseLandmark? pt = pose.landmarks[PoseLandmarkType.rightIndex];
    if (pt == null || pt.likelihood < 0.5) {
      pt = pose.landmarks[PoseLandmarkType.rightWrist];
    }
    if (pt == null || pt.likelihood < 0.3) return;

    final y = pt.y;
    if (y >= 0.0 && y <= 1.0) _yController.add(y);
  }

  InputImage? _cameraImageToInputImage(CameraImage image) {
    try {
      final camera = _cameraController!.description;
      final rotation = Platform.isIOS
          ? InputImageRotation.rotation90deg
          : _rotationForAndroid(camera.sensorOrientation);

      final format = _inputImageFormatFromRaw(image.format.raw);
      final allBytes = <int>[];
      for (final plane in image.planes) {
        allBytes.addAll(plane.bytes);
      }

      return InputImage.fromBytes(
        bytes: Uint8List.fromList(allBytes),
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );
    } catch (e) {
      debugPrint('Image conversion error: $e');
      return null;
    }
  }

  InputImageRotation _rotationForAndroid(int o) {
    switch (o) {
      case 0:   return InputImageRotation.rotation0deg;
      case 90:  return InputImageRotation.rotation90deg;
      case 180: return InputImageRotation.rotation180deg;
      case 270: return InputImageRotation.rotation270deg;
      default:  return InputImageRotation.rotation0deg;
    }
  }

  InputImageFormat _inputImageFormatFromRaw(int raw) {
    switch (raw) {
      case 35:          return InputImageFormat.yuv_420_888;
      case 17:          return InputImageFormat.nv21;
      case 1111970369:  return InputImageFormat.bgra8888;
      default:
        debugPrint('Unknown image format raw: $raw');
        return InputImageFormat.yuv_420_888;
    }
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// DESKTOP — Mouse Y simulation
// ═════════════════════════════════════════════════════════════════════════════

class WindowsMouseTracker implements HandTracker {
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

  void feedY(double mouseLocalY, double widgetHeight) {
    if (!_isRunning || widgetHeight <= 0) return;
    _yController.add((mouseLocalY / widgetHeight).clamp(0.0, 1.0));
  }
}
