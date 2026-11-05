import 'dart:math' as math;

/// Immutable 3D vector, used for every physical quantity of the engine (SI units).
class Vec3 {
  const Vec3(this.x, this.y, this.z);

  static const Vec3 zero = Vec3(0, 0, 0);
  static const Vec3 unitZ = Vec3(0, 0, 1);

  final double x;
  final double y;
  final double z;

  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
  Vec3 operator -(Vec3 o) => Vec3(x - o.x, y - o.y, z - o.z);
  Vec3 operator -() => Vec3(-x, -y, -z);
  Vec3 operator *(double k) => Vec3(x * k, y * k, z * k);
  Vec3 operator /(double k) => Vec3(x / k, y / k, z / k);

  double dot(Vec3 o) => x * o.x + y * o.y + z * o.z;

  Vec3 cross(Vec3 o) => Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);

  double get norm2 => x * x + y * y + z * z;
  double get norm => math.sqrt(norm2);

  /// Unit vector; [fallback] when the norm is (almost) zero.
  Vec3 normalized([Vec3 fallback = unitZ]) {
    final n = norm;
    return n < 1e-12 ? fallback : this / n;
  }

  bool get isFinite => x.isFinite && y.isFinite && z.isFinite;

  /// Angle between two vectors, in radians, robust near 0 and pi.
  double angleTo(Vec3 o) => math.atan2(cross(o).norm, dot(o));

  @override
  String toString() =>
      '(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)}, ${z.toStringAsFixed(3)})';
}
