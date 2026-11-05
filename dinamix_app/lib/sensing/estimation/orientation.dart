import 'dart:math' as math;

import '../math/quaternion.dart';
import '../math/vec3.dart';
import '../motion_sample.dart';

/// Gyro-aided complementary filter on the quaternion (Mahony type), report §4.
///
/// - Prediction: q ← q ⊗ exp(½ (ω − b̂ + correction) Δt), exact for constant rate.
/// - Correction: rate term Kp·w·(f̂ × û), where û = Rᵀ e_z is the predicted
///   "up" in the device frame and f̂ the measured one. The weight w goes to zero
///   when f does not represent gravity (dynamic acceleration, fast rotation).
/// - Gyro bias and local gravity are learned only during stillness.
class OrientationEstimator {
  OrientationEstimator({
    this.timeConstantS = 1.5,
    this.startupTimeConstantS = 0.2,
    this.startupS = 2.0,
    this.sigmaFRatio = 0.1,
    this.sigmaOmega = 3.0,
    this.biasRate = 0.02,
  });

  /// PROVVISORIO: τ = 1.5 s, σ_f = 0.1·g_cal, σ_ω = 3 rad/s (report §4.2).
  final double timeConstantS;
  final double startupTimeConstantS;
  final double startupS;
  final double sigmaFRatio;
  final double sigmaOmega;
  final double biasRate;

  Quaternion q = Quaternion.identity;
  Vec3 bias = Vec3.zero;
  double gCal = g0;
  bool initialized = false;
  bool hasGyro = false;
  bool biasEstimated = false;

  /// Heuristic 1-sigma attitude uncertainty, radians (report §4.3).
  double sigmaTheta = 0.2;

  Vec3 _omega = Vec3.zero;
  Vec3 _correction = Vec3.zero;
  int? _lastNs;
  double _elapsedS = 0;
  double lastWeight = 0;

  /// Body rate without bias, rad/s.
  Vec3 get omega => _omega - bias;

  /// Measured "up" direction in the device frame: Rᵀ e_z.
  Vec3 get upInBody => q.rotateInverse(Vec3.unitZ);

  void _propagate(int tNs) {
    final last = _lastNs;
    _lastNs = tNs;
    if (last == null) return;
    final dt = (tNs - last) / 1e9;
    if (dt <= 0 || dt > 0.5) return; // Gap: the next accelerometer sample re-anchors.
    _elapsedS += dt;
    final rate = (hasGyro ? _omega - bias : Vec3.zero) + _correction;
    q = (q * Quaternion.fromRotationVector(rate, dt)).normalized();
    // Uncertainty grows with unobserved rotation, shrinks with accelerometer evidence.
    final growth = 0.001 * dt + 0.002 * omega.norm * dt;
    final tau = _elapsedS < startupS ? startupTimeConstantS : timeConstantS;
    sigmaTheta = math.min(math.pi, 0.02 + (sigmaTheta - 0.02) * math.exp(-math.max(lastWeight, 0.15) * dt / tau) + growth);
  }

  void onGyro(int tNs, Vec3 omega) {
    _propagate(tNs);
    hasGyro = true;
    _omega = omega;
  }

  /// Returns nothing: read [q] after the call.
  void onAccelerometer(int tNs, Vec3 f) {
    final n = f.norm;
    if (!initialized) {
      if (n < 0.5 * g0) return; // Wait for a sample that shows gravity.
      q = Quaternion.between(f, Vec3.unitZ);
      initialized = true;
      _lastNs = tNs;
      return;
    }
    _propagate(tNs);
    final w = _weight(n);
    lastWeight = w;
    final up = upInBody;
    final error = f.normalized(up).cross(up);
    final tau = _elapsedS < startupS ? startupTimeConstantS : timeConstantS;
    if (hasGyro) {
      _correction = error * (w / tau);
    } else {
      // No gyroscope: adaptive low-pass toward the measured direction (report §2.8).
      final last = q;
      final target = Quaternion.between(f, Vec3.unitZ);
      q = Quaternion.slerp(last, target, math.min(1, w * 0.02 / tau));
      _correction = Vec3.zero;
    }
  }

  double _weight(double fNorm) {
    final df = (fNorm - gCal) / (sigmaFRatio * gCal);
    final rate = hasGyro ? omega.norm / sigmaOmega : 0.0;
    return math.exp(-df * df) * math.exp(-rate * rate);
  }

  /// Called by the stillness detector while the device is at rest.
  void learnAtRest(Vec3 meanOmega, double meanFNorm) {
    if (hasGyro) {
      bias = bias + (meanOmega - bias) * biasRate;
      biasEstimated = true;
    }
    gCal += (meanFNorm - gCal) * biasRate;
  }

  /// Dynamic acceleration in W: R f − (0, 0, g_cal), m/s² (report §5.1).
  Vec3 dynamicWorld(Vec3 f) => q.rotate(f) - Vec3(0, 0, gCal);
}
