import 'package:flutter/foundation.dart';

/// The conductor's intention as inferred from gesture analysis.
enum ConductorState {
  /// No hand detected, or hand not in conducting position.
  idle,

  /// Hand raised (baton up) — waiting for the first downbeat to start music.
  ready,

  /// Actively beating time — music is playing.
  conducting,
}

/// Core conducting logic — beat detection, BPM estimation, volume mapping,
/// and a gesture-based state machine that controls music start/stop.
///
/// This class is platform-agnostic: it only receives a normalized Y coordinate
/// (0.0 = top of frame, 1.0 = bottom) via [processY].
class ConductorLogic extends ChangeNotifier {
  // ── Public read-only state ────────────────────────────────────────────────

  double get avgBpm => _avgBpm;
  double get instantBpm => _instantBpm;
  double get volume => _volume;
  double get currentY => _currentY;
  bool get isTracking => _isTracking;

  double get playbackRate {
    final rate = _avgBpm / 120.0;
    return rate.clamp(0.5, 2.0);
  }

  /// Current conductor state (idle → ready → conducting).
  ConductorState get conductorState => _state;

  /// Increments on every detected beat — UI can watch for animations.
  int get beatCount => _beatCount;

  /// Whether the conductor is actively beating.
  bool get isConducting => _state == ConductorState.conducting;

  /// Whether the conductor has raised the baton (armed, ready to start).
  bool get isReady => _state == ConductorState.ready;

  // ── Callbacks (set by UI layer) ────────────────────────────────────────────

  /// Called when the conductor begins beating (ready → conducting).
  VoidCallback? onConductingStarted;

  /// Called when the conductor stops beating (conducting → idle timeout).
  VoidCallback? onConductingStopped;

  // ── Tunable parameters ─────────────────────────────────────────────────────

  /// Raw Y must be below this value to enter the ready zone (hand raised high).
  static const double readyZoneThreshold = 0.35;

  /// Seconds of inactivity before conducting → idle.
  static const int idleTimeoutSeconds = 3;

  /// Milliseconds the hand must stay in the ready zone before arming.
  static const int readyHoldMs = 500;

  // ── Private beat-detection state ──────────────────────────────────────────

  double _avgBpm = 120.0;
  double _instantBpm = 120.0;
  double _volume = 0.5;
  double _currentY = 0.5;
  bool _isTracking = false;

  double _prevY = 0.5;
  double _lastY = 0.5;
  int _lastBeatTimeMs = 0;
  double _strokePeakY = 0.5;

  // ── State-machine fields ──────────────────────────────────────────────────

  ConductorState _state = ConductorState.idle;
  DateTime? _readySince;  // when hand first entered the ready zone
  DateTime? _loweredSince; // when hand dropped below ready zone (ready→idle)
  DateTime? _lastBeatTime; // timestamp of the most recent beat (for timeout)
  int _beatCount = 0;
  bool _beatJustDetected = false; // set true in beat-detection block

  // ── Public API ────────────────────────────────────────────────────────────

  /// Feed a new raw Y coordinate from the tracker.
  ///
  /// [rawY] is 0.0–1.0 (0 = top, 1 = bottom).
  void processY(double rawY) {
    rawY = rawY.clamp(0.0, 1.0);
    _currentY = rawY;

    final double y = 1.0 - rawY; // invert: high finger → large value

    if (!_isTracking) {
      _prevY = y;
      _lastY = y;
      _strokePeakY = y;
      _isTracking = true;
      _lastBeatTimeMs = DateTime.now().millisecondsSinceEpoch;
      return;
    }

    if (y > _strokePeakY) {
      _strokePeakY = y;
    }

    // ── Beat detection ──────────────────────────────────────────────────
    // local minimum: prevY > lastY (descending) AND y > lastY (ascending).
    if (_prevY > _lastY && y > _lastY) {
      final int nowMs = DateTime.now().millisecondsSinceEpoch;
      final int deltaMs = nowMs - _lastBeatTimeMs;

      if (deltaMs > 300) {
        _instantBpm = (60000.0 / deltaMs).clamp(40.0, 300.0);
        _avgBpm = _avgBpm * 0.7 + _instantBpm * 0.3;

        final double amplitude = (_strokePeakY - _lastY).abs();
        final double normalizedAmp =
            ((amplitude - 0.02) / (0.5 - 0.02)).clamp(0.0, 1.0);
        _volume = 0.2 + normalizedAmp * 0.8;

        _lastBeatTimeMs = nowMs;
        _strokePeakY = y;
        _beatJustDetected = true;
        _lastBeatTime = DateTime.now();
      }
    }

    _prevY = _lastY;
    _lastY = y;

    // ── State machine ───────────────────────────────────────────────────
    _runStateMachine(rawY);

    _beatJustDetected = false;
    notifyListeners();
  }

  // ── State machine ───────────────────────────────────────────────────────

  void _runStateMachine(double rawY) {
    final now = DateTime.now();

    switch (_state) {
      case ConductorState.idle:
        if (rawY < readyZoneThreshold) {
          _readySince ??= now;
          if (now.difference(_readySince!).inMilliseconds >= readyHoldMs) {
            _state = ConductorState.ready;
            _loweredSince = null;
          }
        } else {
          _readySince = null;
        }
        break;

      case ConductorState.ready:
        if (_beatJustDetected) {
          _state = ConductorState.conducting;
          _beatCount = 1;
          _readySince = null;
          _loweredSince = null;
          debugPrint('Conductor: conducting started');
          onConductingStarted?.call();
        } else if (rawY > 0.7) {
          _loweredSince ??= now;
          if (now.difference(_loweredSince!).inMilliseconds >= 1500) {
            _state = ConductorState.idle;
            _readySince = null;
            _loweredSince = null;
          }
        } else {
          _loweredSince = null;
        }
        break;

      case ConductorState.conducting:
        if (_beatJustDetected) {
          _beatCount++;
          _lastBeatTime = now;
        }
        if (_lastBeatTime != null &&
            now.difference(_lastBeatTime!).inSeconds >= idleTimeoutSeconds) {
          _state = ConductorState.idle;
          _readySince = null;
          debugPrint('Conductor: conducting stopped (timeout)');
          onConductingStopped?.call();
        }
        break;
    }
  }

  /// Reset all state to defaults.
  void reset() {
    _avgBpm = 120.0;
    _instantBpm = 120.0;
    _volume = 0.5;
    _currentY = 0.5;
    _isTracking = false;
    _prevY = 0.5;
    _lastY = 0.5;
    _lastBeatTimeMs = 0;
    _strokePeakY = 0.5;
    _state = ConductorState.idle;
    _readySince = null;
    _loweredSince = null;
    _lastBeatTime = null;
    _beatCount = 0;
    _beatJustDetected = false;
    notifyListeners();
  }
}
