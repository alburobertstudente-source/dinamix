import 'dart:math' as math;

import '../classify/classifier.dart';
import '../math/quaternion.dart';
import '../math/vec3.dart';
import '../motion_sample.dart';

/// Contribution to the motion over [startS, endS): world acceleration of the
/// sensor (m/s²) and body angular rate (rad/s), as functions of local time.
class MotionComponent {
  const MotionComponent(this.startS, this.endS, {this.acc, this.omega});

  final double startS;
  final double endS;
  final Vec3 Function(double tau)? acc;
  final Vec3 Function(double tau)? omega;

  bool covers(double t) => t >= startS && t < endS;
}

/// What a scenario must produce (ground truth of the simulator).
class Expectation {
  const Expectation({
    this.allowed = const {},
    this.alarm,
    this.mustDetect = false,
    this.dangerous = false,
  });

  /// Accepted categories of the strongest event; empty = no event expected.
  final Set<MovementCategory> allowed;

  /// true: an alarm is required; false: no alarm allowed; null: either.
  final bool? alarm;
  final bool mustDetect;

  /// Ground-truth label for the precision/recall of the alarm.
  final bool dangerous;
}

class SimScenario {
  SimScenario({
    required this.id,
    required this.title,
    required this.durationS,
    required this.components,
    required this.expectation,
    this.initial = Quaternion.identity,
    this.settleFlatAtS,
    this.gpsSpeed,
    this.gpsNoise = 0.3,
    this.gpsOutlierRate = 0,
    this.gpsDropout = 0,
    this.eventTimeS,
    this.dropHeightM,
  });

  final String id;
  final String title;
  final double durationS;
  final List<MotionComponent> components;
  final Expectation expectation;
  final Quaternion initial;

  /// After this time the body turns until its z axis is vertical (resting flat).
  final double? settleFlatAtS;

  /// True vehicle speed for the GPS (m/s), null without GPS.
  final double Function(double t)? gpsSpeed;
  final double gpsNoise;
  final double gpsOutlierRate;
  final double gpsDropout;

  /// Time of the main physical event, for the detection latency.
  final double? eventTimeS;

  /// Drop height, to check T_ff and Δv against √(2h/g) and √(2gh).
  final double? dropHeightM;
}

/// Sensor model of the simulated hardware. Values are ILLUSTRATIVE, they are not
/// a description of a real phone or of the SensorTile.
class SensorModel {
  const SensorModel({
    required this.rateHz,
    this.accNoise = 0.015,
    this.accBias = 0.05,
    this.accScaleError = 0.005,
    this.accQuantum = 0.0024,
    this.accRange = 16 * g0,
    this.gyroNoise = 0.003,
    this.gyroBias = 0.01,
    this.gyroRange = 34.9,
    this.jitterS = 0.0003,
    this.gapProbability = 0,
    this.leverArm = const Vec3(0.03, 0.05, 0.004),
  });

  final double rateHz;
  final double accNoise;
  final double accBias;
  final double accScaleError;
  final double accQuantum;
  final double accRange;
  final double gyroNoise;
  final double gyroBias;
  final double gyroRange;
  final double jitterS;
  final double gapProbability;
  final Vec3 leverArm;

  static const SensorModel phone200 = SensorModel(rateHz: 200);
  static const SensorModel phone100 = SensorModel(rateHz: 100);
  static const SensorModel sensorTile50 = SensorModel(
    rateHz: 50,
    accQuantum: g0 / 1000, // 1 mg on the BlueST wire.
    gyroRange: 3276.7 * math.pi / 180,
    jitterS: 0.0005,
    gapProbability: 0.002,
    leverArm: Vec3(0.015, 0.02, 0.003),
  );
}

/// Physically consistent generator of accelerometer, gyroscope and GPS samples:
/// f_B = Rᵀ(a_W + g e_z) + ω×(ω×r) + α×r + bias + noise (report §3.2), averaged
/// over each sampling period (a simple anti-aliasing model), then quantized and
/// clipped to the full scale.
class PhysicsSimulator {
  PhysicsSimulator(this.model, {int seed = 1}) : _random = math.Random(seed);

  final SensorModel model;
  final math.Random _random;
  static const double _internalHz = 2000;

  double _gauss() {
    final u1 = math.max(1e-12, _random.nextDouble());
    final u2 = _random.nextDouble();
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }

  Vec3 _randomVec(double scale) => Vec3(_gauss(), _gauss(), _gauss()) * scale;

  double _quantize(double v) =>
      (model.accQuantum > 0 ? (v / model.accQuantum).round() * model.accQuantum : v)
          .clamp(-model.accRange, model.accRange)
          .toDouble();

  List<MotionSample> run(SimScenario s) {
    final out = <MotionSample>[];
    final accBias = _randomVec(model.accBias);
    final gyroBias = _randomVec(model.gyroBias);
    final scale = Vec3(1 + _gauss() * model.accScaleError, 1 + _gauss() * model.accScaleError,
        1 + _gauss() * model.accScaleError);
    const dt = 1 / _internalHz;
    final period = 1 / model.rateHz;
    var q = s.initial;
    var t = 0.0;
    var nextSample = period;
    Vec3 fSum = Vec3.zero, wSum = Vec3.zero;
    var n = 0;
    Vec3 previousOmega = _omegaAt(s, 0, q);
    var sampleIndex = 0;
    while (t < s.durationS) {
      final omega = _omegaAt(s, t, q);
      final alpha = (omega - previousOmega) / dt;
      previousOmega = omega;
      final aW = _accAt(s, t);
      final r = model.leverArm;
      final f = q.rotateInverse(aW + const Vec3(0, 0, g0)) +
          omega.cross(omega.cross(r)) +
          alpha.cross(r);
      fSum = fSum + f;
      wSum = wSum + omega;
      n++;
      q = (q * Quaternion.fromRotationVector(omega, dt)).normalized();
      t += dt;
      if (t >= nextSample) {
        final tSample = nextSample + _gauss() * model.jitterS;
        final fMean = fSum / n.toDouble();
        final wMean = wSum / n.toDouble();
        fSum = Vec3.zero;
        wSum = Vec3.zero;
        n = 0;
        nextSample += period;
        sampleIndex++;
        if (model.gapProbability > 0 && _random.nextDouble() < model.gapProbability) {
          continue; // Lost sample.
        }
        final noisyF = Vec3(
          _quantize(fMean.x * scale.x + accBias.x + _gauss() * model.accNoise),
          _quantize(fMean.y * scale.y + accBias.y + _gauss() * model.accNoise),
          _quantize(fMean.z * scale.z + accBias.z + _gauss() * model.accNoise),
        );
        double clipW(double v) => v.clamp(-model.gyroRange, model.gyroRange).toDouble();
        final noisyW = Vec3(
          clipW(wMean.x + gyroBias.x + _gauss() * model.gyroNoise),
          clipW(wMean.y + gyroBias.y + _gauss() * model.gyroNoise),
          clipW(wMean.z + gyroBias.z + _gauss() * model.gyroNoise),
        );
        final tNs = (tSample * 1e9).round();
        // Gyro slightly before the accelerometer: the two streams are not synchronous.
        out.add(MotionSample(SampleKind.gyro, tNs - 400000, noisyW));
        out.add(MotionSample(SampleKind.acc, tNs, noisyF));
        final speed = s.gpsSpeed;
        if (speed != null && sampleIndex % model.rateHz.round() == 0) {
          if (_random.nextDouble() >= s.gpsDropout) {
            var v = speed(tSample) + _gauss() * s.gpsNoise;
            if (_random.nextDouble() < s.gpsOutlierRate) v += (_random.nextDouble() - 0.5) * 30;
            out.add(MotionSample(SampleKind.gps, tNs, Vec3(math.max(0, v), s.gpsNoise * 1.5, 0)));
          }
        }
      }
    }
    out.sort((a, b) => a.tNs.compareTo(b.tNs));
    return out;
  }

  Vec3 _accAt(SimScenario s, double t) {
    Vec3 a = Vec3.zero;
    for (final c in s.components) {
      if (c.acc != null && c.covers(t)) a = a + c.acc!(t - c.startS);
    }
    return a;
  }

  Vec3 _omegaAt(SimScenario s, double t, Quaternion q) {
    Vec3 w = Vec3.zero;
    for (final c in s.components) {
      if (c.omega != null && c.covers(t)) w = w + c.omega!(t - c.startS);
    }
    final settle = s.settleFlatAtS;
    if (settle != null && t >= settle) {
      // Closed-loop turn of the body z axis toward the nearest vertical (lying flat).
      final up = q.rotateInverse(Vec3.unitZ);
      final target = up.z >= 0 ? Vec3.unitZ : -Vec3.unitZ;
      final error = up.cross(target);
      w = w + error * -12.0;
    }
    return w;
  }
}

// ---------------------------------------------------------------------------
// Motion primitives (all in SI units).

/// Half-sine pulse with integral [dv] (m/s) along [dir], lasting [durationS].
MotionComponent pulse(double atS, double durationS, double dv, Vec3 dir) {
  final u = dir.normalized();
  final peak = dv * math.pi / (2 * durationS);
  return MotionComponent(atS, atS + durationS,
      acc: (tau) => u * (peak * math.sin(math.pi * tau / durationS)));
}

/// Free fall: the true acceleration of the sensor is −g.
MotionComponent freeFall(double atS, double durationS, {Vec3? spin}) => MotionComponent(
      atS,
      atS + durationS,
      acc: (_) => const Vec3(0, 0, -g0),
      omega: spin == null ? null : (_) => spin,
    );

/// Minimum-jerk reach of [distance] m along [dir] in [durationS] (hand motion).
MotionComponent reach(double atS, double durationS, double distance, Vec3 dir) {
  final u = dir.normalized();
  return MotionComponent(atS, atS + durationS, acc: (tau) {
    final x = tau / durationS;
    final a = distance / (durationS * durationS) * (60 * x - 180 * x * x + 120 * x * x * x);
    return u * a;
  });
}

/// Rotation by [angle] rad about body [axis] with a half-sine rate profile.
MotionComponent turn(double atS, double durationS, double angle, Vec3 axis) {
  final u = axis.normalized();
  final peak = angle * math.pi / (2 * durationS);
  return MotionComponent(atS, atS + durationS,
      omega: (tau) => u * (peak * math.sin(math.pi * tau / durationS)));
}

/// Walking with the phone in a trouser pocket (illustrative amplitudes).
MotionComponent walking(double atS, double durationS, {double stepHz = 1.8, double phase = 0}) =>
    MotionComponent(
      atS,
      atS + durationS,
      acc: (tau) {
        final w = 2 * math.pi * stepHz * tau + phase;
        return Vec3(0.2 * g0 * math.sin(w + 0.6), 0.05 * g0 * math.sin(w / 2),
            0.3 * g0 * math.sin(w) + 0.12 * g0 * math.sin(2 * w + 0.3));
      },
      omega: (tau) {
        final w = 2 * math.pi * stepHz * tau + phase;
        // Thigh swing of ±0.3 rad at half the step frequency.
        return Vec3(0.3 * math.pi * stepHz * math.cos(w / 2), 0.2 * math.sin(w), 0.15 * math.cos(w));
      },
    );

/// Running: support impulse during contact, free fall during the flight phase.
MotionComponent running(double atS, double durationS, {double stepHz = 2.8, double flight = 0.11}) {
  final period = 1 / stepHz;
  final contact = period - flight;
  return MotionComponent(atS, atS + durationS, acc: (tau) {
    final p = tau % period;
    var fz = 0.0;
    if (p < contact) {
      // ∫ f_z over the contact = g·period, so the mean acceleration is zero.
      fz = g0 * period * math.pi / (2 * contact) * math.sin(math.pi * p / contact);
    }
    final w = 2 * math.pi * stepHz * tau;
    return Vec3(0.25 * g0 * math.sin(w + 1), 0.08 * g0 * math.sin(w / 2), fz - g0);
  }, omega: (tau) {
    final w = 2 * math.pi * stepHz * tau;
    return Vec3(0.5 * math.pi * stepHz * math.cos(w / 2), 0.4 * math.sin(w), 0.3 * math.cos(w));
  });
}

/// Sum of sines: vibration in a band, amplitude in m/s² per axis.
MotionComponent vibration(double atS, double durationS, double amplitude, List<double> hz,
    {int seed = 3}) {
  final r = math.Random(seed);
  final phases = [for (var i = 0; i < hz.length * 3; i++) r.nextDouble() * 2 * math.pi];
  return MotionComponent(atS, atS + durationS, acc: (tau) {
    var x = 0.0, y = 0.0, z = 0.0;
    for (var i = 0; i < hz.length; i++) {
      final w = 2 * math.pi * hz[i] * tau;
      x += math.sin(w + phases[i * 3]);
      y += math.sin(w + phases[i * 3 + 1]);
      z += math.sin(w + phases[i * 3 + 2]);
    }
    final k = amplitude / math.sqrt(hz.length.toDouble());
    return Vec3(x * k * 0.6, y * k * 0.6, z * k);
  });
}

/// Hand shake: sinusoidal acceleration along [dir], whole number of cycles.
MotionComponent shake(double atS, int cycles, double hz, double amplitude, Vec3 dir,
    {double wristRate = 4}) {
  final u = dir.normalized();
  final duration = cycles / hz;
  return MotionComponent(atS, atS + duration,
      acc: (tau) => u * (amplitude * math.sin(2 * math.pi * hz * tau)),
      omega: (tau) => const Vec3(0, 0, 1) * (wristRate * math.cos(2 * math.pi * hz * tau)));
}

/// Hand tremor while holding the phone (tiny, keeps the scene realistic).
MotionComponent holding(double atS, double durationS) => MotionComponent(atS, atS + durationS,
    acc: (tau) => Vec3(0.02 * math.sin(2 * math.pi * 7.3 * tau), 0.015 * math.sin(2 * math.pi * 5.1 * tau),
        0.02 * math.sin(2 * math.pi * 6.2 * tau)),
    omega: (tau) => Vec3(0.01 * math.sin(2 * math.pi * 6 * tau), 0.012 * math.sin(2 * math.pi * 4.7 * tau), 0));

/// Inverted-pendulum fall of a standing person, phone in the trouser pocket.
/// Simplified model, stated as such: point at height [hipHeight] on a rigid body
/// pivoting at the feet, θ'' = (g/L) sin θ, from θ₀ to 90°, then a soft impact.
List<MotionComponent> personFall(double atS, {double hipHeight = 0.9, double theta0 = 0.08}) {
  const steps = 4000;
  final thetas = <double>[];
  final rates = <double>[];
  var theta = theta0;
  var rate = 0.0;
  const h = 0.0005;
  var time = 0.0;
  while (theta < math.pi / 2 && thetas.length < steps) {
    thetas.add(theta);
    rates.add(rate);
    final acc = g0 / hipHeight * math.sin(theta);
    rate += acc * h;
    theta += rate * h;
    time += h;
  }
  final fallTime = time;
  final impactSpeed = hipHeight * rates.last;
  final fallPart = MotionComponent(atS, atS + fallTime, acc: (tau) {
    final i = math.min(thetas.length - 1, (tau / h).floor());
    final th = thetas[i];
    final w = rates[i];
    final dd = g0 / hipHeight * math.sin(th);
    return Vec3(hipHeight * (dd * math.cos(th) - w * w * math.sin(th)), 0,
        -hipHeight * (dd * math.sin(th) + w * w * math.cos(th)));
  }, omega: (tau) {
    final i = math.min(rates.length - 1, (tau / h).floor());
    // Phone y axis up in the pocket, falling forward: rotation about body −z.
    return Vec3(0, 0, -rates[i]);
  });
  const impactS = 0.07;
  final end = atS + fallTime;
  final stopRotation = MotionComponent(end, end + impactS,
      omega: (tau) => Vec3(0, 0, -rates.last * (1 - tau / impactS)));
  return [
    fallPart,
    pulse(end, impactS, impactSpeed, const Vec3(0, 0, 1)),
    stopRotation,
  ];
}
