import 'math/vec3.dart';

/// State of the engine at one accelerometer sample: everything the event
/// analysis needs, so that it never re-runs the filters.
class Frame {
  Frame({
    required this.tS,
    required this.f,
    required this.aW,
    required this.jerk,
    required this.snap,
    required this.omega,
    required this.alpha,
    required this.up,
    required this.still,
    required this.freeFall,
    required this.zA,
    required this.highPass,
    required this.aLow,
    required this.fVertical,
    required this.saturated,
    required this.gapBefore,
  })  : fNorm = f.norm,
        aNorm = aW.norm,
        jNorm = jerk.norm,
        omegaNorm = omega.norm;

  final double tS;

  /// Specific force in the device frame (m/s²).
  final Vec3 f;
  final double fNorm;

  /// Dynamic acceleration in the world frame (m/s²): z is vertical, up.
  final Vec3 aW;
  final double aNorm;

  /// Filtered jerk of aW (m/s³) and its second derivative (m/s⁴).
  final Vec3 jerk;
  final double jNorm;
  final Vec3 snap;

  /// Body rate without bias (rad/s) and angular acceleration (rad/s²).
  final Vec3 omega;
  final double omegaNorm;
  final Vec3 alpha;

  /// Estimated "up" direction in the device frame (unit).
  final Vec3 up;
  final bool still;
  final bool freeFall;

  /// Robust z-score of |a| against the adaptive baseline.
  final double zA;

  /// Norm of the high-pass (vibration band) vector of a_W, m/s².
  final double highPass;

  /// Low-pass (body motion band, 2 Hz) a_W, m/s²: used for sustained accelerations.
  final Vec3 aLow;

  /// Vertical component of the specific force in W: ≈ g with gravity, ≈ 0 in free fall.
  final double fVertical;
  final bool saturated;
  final bool gapBefore;

  double get aVertical => aW.z;
  double get aHorizontal => Vec3(aW.x, aW.y, 0).norm;
  double get aLowHorizontal => Vec3(aLow.x, aLow.y, 0).norm;
}
