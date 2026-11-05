import 'dart:math' as math;

import '../analysis/series_analysis.dart';
import '../ble/connection_manager.dart';
import '../domain/sensor_kind.dart';

enum RideActivity {
  mountainBike('Mountain Bike', 'Sentieri, salti, vibrazioni'),
  skiSnowboard('Sci / Snowboard', 'Curve, velocità, urti'),
  hiking('Escursionismo', 'Passo, quota, cadute');

  const RideActivity(this.label, this.subtitle);

  final String label;
  final String subtitle;
}

enum MotionLevel { waiting, calm, moving, intense }

class SessionSummary {
  const SessionSummary({
    required this.activity,
    required this.duration,
    required this.peakG,
    required this.meanG,
    required this.peakRotationDps,
    required this.impacts,
    required this.samples,
    required this.sessionId,
    required this.source,
  });

  final RideActivity activity;
  final Duration duration;
  final double peakG;
  final double meanG;
  final double peakRotationDps;
  final int impacts;
  final int samples;
  final int? sessionId;
  final DataSource? source;
}

/// Live values of the active session. Cheap enough to run on every packet: the
/// screen reads them on its own frames, it is never notified by the data.
class LiveSessionController implements ReadingSink {
  LiveSessionController({
    required this.impactThresholdG,
    this.refractoryMs = 1500,
    int Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  static const int historyLength = 150;
  static const int _historyStepMs = 40;
  static const double _tiltSmoothing = 0.12;
  static const double _energySmoothing = 0.08;

  final double impactThresholdG;
  final int refractoryMs;
  final int Function() _clock;

  /// Called when acceleration crosses the threshold (not more than once per
  /// [refractoryMs]). Experimental: it is not a certified fall detection.
  void Function(double g)? onImpact;

  final SeriesStats accelerationStats = SeriesStats();
  final List<double> history = [];

  double currentG = 0;
  double peakG = 0;
  double rotationDps = 0;
  double peakRotationDps = 0;
  double pitch = 0;
  double roll = 0;
  double motionEnergy = 0;
  int impacts = 0;
  int samples = 0;

  bool _tiltStarted = false;
  int _lastImpactMs = -1 << 40;
  int _lastHistoryMs = -1 << 40;
  double _historyMax = 0;

  bool get hasData => samples > 0;

  MotionLevel get level {
    if (!hasData) return MotionLevel.waiting;
    if (motionEnergy < 0.06) return MotionLevel.calm;
    if (motionEnergy < 0.5) return MotionLevel.moving;
    return MotionLevel.intense;
  }

  @override
  void ingest(SensorReading reading) {
    switch (reading.kind) {
      case SensorKind.accelerometer:
        _onAcceleration(reading.values, reading.receivedAtMs);
      case SensorKind.gyroscope:
        _onRotation(reading.values);
      default:
        break;
    }
  }

  void _onAcceleration(List<double> mg, int atMs) {
    final g = vectorMagnitude(mg) / 1000.0;
    if (g.isNaN) return;
    samples++;
    currentG = g;
    accelerationStats.add(g);
    if (g > peakG) peakG = g;
    motionEnergy += ((g - 1).abs() - motionEnergy) * _energySmoothing;

    final targetPitch = math.atan2(mg[1], math.sqrt(mg[0] * mg[0] + mg[2] * mg[2]));
    final targetRoll = math.atan2(mg[0], mg[2].abs() < 1 ? 1 : mg[2]);
    if (!_tiltStarted) {
      pitch = targetPitch;
      roll = targetRoll;
      _tiltStarted = true;
    } else {
      pitch += (targetPitch - pitch) * _tiltSmoothing;
      roll += (targetRoll - roll) * _tiltSmoothing;
    }

    _historyMax = math.max(_historyMax, g);
    if (atMs - _lastHistoryMs >= _historyStepMs) {
      history.add(_historyMax);
      if (history.length > historyLength) history.removeAt(0);
      _historyMax = 0;
      _lastHistoryMs = atMs;
    }

    if (g >= impactThresholdG && atMs - _lastImpactMs >= refractoryMs) {
      _lastImpactMs = atMs;
      impacts++;
      onImpact?.call(g);
    }
  }

  void _onRotation(List<double> dps) {
    final value = vectorMagnitude(dps);
    if (value.isNaN) return;
    rotationDps = value;
    if (value > peakRotationDps) peakRotationDps = value;
  }

  int get nowMs => _clock();
}
