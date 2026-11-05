import 'dart:math' as math;

import 'vec3.dart';

/// Unit quaternion (w, x, y, z) for the rotation from the device frame B to the
/// world frame W: v_W = q ⊗ v_B ⊗ q*.
class Quaternion {
  const Quaternion(this.w, this.x, this.y, this.z);

  static const Quaternion identity = Quaternion(1, 0, 0, 0);

  final double w;
  final double x;
  final double y;
  final double z;

  Quaternion operator *(Quaternion o) => Quaternion(
        w * o.w - x * o.x - y * o.y - z * o.z,
        w * o.x + x * o.w + y * o.z - z * o.y,
        w * o.y - x * o.z + y * o.w + z * o.x,
        w * o.z + x * o.y - y * o.x + z * o.w,
      );

  Quaternion get conjugate => Quaternion(w, -x, -y, -z);

  Quaternion normalized() {
    final n = math.sqrt(w * w + x * x + y * y + z * z);
    if (n < 1e-12) return identity;
    return Quaternion(w / n, x / n, y / n, z / n);
  }

  /// Rotation of [angle] radians around the unit [axis].
  static Quaternion fromAxisAngle(Vec3 axis, double angle) {
    final u = axis.normalized();
    final s = math.sin(angle / 2);
    return Quaternion(math.cos(angle / 2), u.x * s, u.y * s, u.z * s);
  }

  /// Exact integration of a constant body rate [omega] (rad/s) over [dt] seconds.
  static Quaternion fromRotationVector(Vec3 omega, double dt) {
    final angle = omega.norm * dt;
    if (angle < 1e-12) {
      // First-order expansion, exact enough below 1e-12 rad.
      return Quaternion(1, omega.x * dt / 2, omega.y * dt / 2, omega.z * dt / 2).normalized();
    }
    return fromAxisAngle(omega, angle);
  }

  /// Smallest rotation taking unit vector [from] onto unit vector [to].
  static Quaternion between(Vec3 from, Vec3 to) {
    final a = from.normalized();
    final b = to.normalized();
    final d = a.dot(b);
    if (d < -0.999999) {
      // Opposite vectors: any perpendicular axis works.
      var axis = const Vec3(1, 0, 0).cross(a);
      if (axis.norm < 1e-6) axis = const Vec3(0, 1, 0).cross(a);
      return fromAxisAngle(axis, math.pi);
    }
    final c = a.cross(b);
    return Quaternion(1 + d, c.x, c.y, c.z).normalized();
  }

  /// Rotates [v] from B to W.
  Vec3 rotate(Vec3 v) {
    // v' = v + 2w(u×v) + 2u×(u×v), with u = (x, y, z).
    final u = Vec3(x, y, z);
    final t = u.cross(v) * 2;
    return v + t * w + u.cross(t);
  }

  /// Rotates [v] from W to B.
  Vec3 rotateInverse(Vec3 v) => conjugate.rotate(v);

  /// Rotation angle in [0, pi], radians.
  double get angle => 2 * math.atan2(math.sqrt(x * x + y * y + z * z), w.abs());

  /// Spherical interpolation, t in [0, 1].
  static Quaternion slerp(Quaternion a, Quaternion b, double t) {
    var cos = a.w * b.w + a.x * b.x + a.y * b.y + a.z * b.z;
    var bb = b;
    if (cos < 0) {
      cos = -cos;
      bb = Quaternion(-b.w, -b.x, -b.y, -b.z);
    }
    if (cos > 0.9995) {
      return Quaternion(
        a.w + (bb.w - a.w) * t,
        a.x + (bb.x - a.x) * t,
        a.y + (bb.y - a.y) * t,
        a.z + (bb.z - a.z) * t,
      ).normalized();
    }
    final theta = math.acos(cos);
    final s = math.sin(theta);
    final ka = math.sin((1 - t) * theta) / s;
    final kb = math.sin(t * theta) / s;
    return Quaternion(
      a.w * ka + bb.w * kb,
      a.x * ka + bb.x * kb,
      a.y * ka + bb.y * kb,
      a.z * ka + bb.z * kb,
    );
  }
}
