import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'hand_tracker.dart';

/// Displays the camera preview (mirrored for front camera) or a mouse-
/// tracking placeholder on desktop platforms.
///
/// On mobile ([CameraController] is provided) the widget shows the live
/// camera feed with a small reticle that follows the tracked finger position.
/// On desktop it renders a dark area with a mouse-tracking overlay.
class CameraPreviewWidget extends StatelessWidget {
  const CameraPreviewWidget({
    super.key,
    this.cameraController,
    this.trackedY,
    this.onMouseYChanged,
  });

  /// The camera controller (non-null on mobile).
  final CameraController? cameraController;

  /// Current tracked Y position (0.0–1.0), for overlay reticle.
  final double? trackedY;

  /// Called with the normalised Y position when the user moves the mouse
  /// inside this widget (desktop only).
  final ValueChanged<double>? onMouseYChanged;

  @override
  Widget build(BuildContext context) {
    if (isDesktopPlatform) {
      return _buildDesktopTracking(context);
    }
    return _buildMobilePreview(context);
  }

  // ── Mobile: real camera preview ────────────────────────────────────────

  Widget _buildMobilePreview(BuildContext context) {
    if (cameraController == null || !cameraController!.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return ClipRect(
      child: Transform(
        // Mirror the preview for a natural selfie view.
        alignment: Alignment.center,
        // Always mirror the front-camera preview for natural selfie view.
        transform: Matrix4.rotationY(3.1415926535),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CameraPreview(cameraController!),
            // Finger position reticle
            if (trackedY != null)
              Positioned(
                left: 0,
                right: 0,
                top: trackedY! *
                    MediaQuery.of(context).size.height *
                    0.6, // approx preview height
                child: const _Reticle(),
              ),
          ],
        ),
      ),
    );
  }

  // ── Desktop: mouse tracking placeholder ─────────────────────────────────

  Widget _buildDesktopTracking(BuildContext context) {
    final hasCamera = cameraController != null &&
        cameraController!.value.isInitialized;

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        return MouseRegion(
          onHover: (event) {
            if (onMouseYChanged != null && height > 0) {
              onMouseYChanged!(event.localPosition.dy / height);
            }
          },
          child: Container(
            width: double.infinity,
            height: double.infinity,
            color: const Color(0xFF1A1A2E),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Camera preview (mirrored) when available.
                if (hasCamera)
                  Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.rotationY(3.1415926535),
                    child: CameraPreview(cameraController!),
                  ),
                // Instruction text (only when no camera).
                if (!hasCamera)
                  const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.mouse, size: 48, color: Colors.white54),
                        SizedBox(height: 12),
                        Text(
                          'Move mouse up & down\nto simulate conducting',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                // Reticle at tracked Y
                if (trackedY != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: trackedY! * height - 20,
                    child: const _Reticle(),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Small glowing dot that follows the tracked finger / mouse position.
class _Reticle extends StatelessWidget {
  const _Reticle();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.redAccent.withValues(alpha: 0.8),
              boxShadow: [
                BoxShadow(
                  color: Colors.redAccent.withValues(alpha: 0.6),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          // Dashed horizontal line
          const Expanded(
            child: Divider(
              color: Colors.white30,
              thickness: 1,
              endIndent: 12,
              indent: 12,
            ),
          ),
        ],
      ),
    );
  }
}
