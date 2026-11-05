import 'dart:typed_data';

import '../math/vec3.dart';

/// Time derivatives of a vector signal on irregular timestamps (report §6.2).
///
/// - First derivative: least-squares slope over the last samples spanning about
///   [windowS] (Savitzky–Golay of degree 1, irregular Δt). Variance is reduced by
///   N(N²−1)/24 compared with a two-point difference.
/// - Second derivative ("snap" when applied to acceleration): 2·c₂ of a local
///   quadratic fit over a longer window. Noise grows as 1/Δt², so it has a low weight.
class LsDerivative {
  LsDerivative({this.windowS = 0.03, this.snapWindowS = 0.08, this.capacity = 64})
      : _t = Float64List(capacity),
        _x = Float64List(capacity),
        _y = Float64List(capacity),
        _z = Float64List(capacity);

  final double windowS;
  final double snapWindowS;
  final int capacity;
  final Float64List _t;
  final Float64List _x;
  final Float64List _y;
  final Float64List _z;
  int _head = 0;
  int _length = 0;

  Vec3 slope = Vec3.zero;
  Vec3 second = Vec3.zero;

  /// Raw two-point difference, kept for diagnostics only.
  Vec3 rawDifference = Vec3.zero;

  bool get ready => _length >= 3;

  void reset() {
    _length = 0;
    _head = 0;
    slope = Vec3.zero;
    second = Vec3.zero;
    rawDifference = Vec3.zero;
  }

  int _index(int back) => (_head - 1 - back + capacity) % capacity;

  void add(double tS, Vec3 v) {
    if (_length > 0) {
      final i = _index(0);
      final dt = tS - _t[i];
      if (dt > 0) {
        rawDifference = Vec3((v.x - _x[i]) / dt, (v.y - _y[i]) / dt, (v.z - _z[i]) / dt);
      }
    }
    _t[_head] = tS;
    _x[_head] = v.x;
    _y[_head] = v.y;
    _z[_head] = v.z;
    _head = (_head + 1) % capacity;
    if (_length < capacity) _length++;
    slope = _fitSlope(tS);
    second = _fitSecond(tS);
  }

  int _count(double tS, double window, int minimum) {
    var n = 0;
    while (n < _length && tS - _t[_index(n)] <= window + 1e-9) {
      n++;
    }
    return n < minimum ? (_length < minimum ? _length : minimum) : n;
  }

  Vec3 _fitSlope(double tS) {
    final n = _count(tS, windowS, 3);
    if (n < 2) return Vec3.zero;
    var tm = 0.0, xm = 0.0, ym = 0.0, zm = 0.0;
    for (var k = 0; k < n; k++) {
      final i = _index(k);
      tm += _t[i];
      xm += _x[i];
      ym += _y[i];
      zm += _z[i];
    }
    tm /= n;
    xm /= n;
    ym /= n;
    zm /= n;
    var stt = 0.0, sx = 0.0, sy = 0.0, sz = 0.0;
    for (var k = 0; k < n; k++) {
      final i = _index(k);
      final dt = _t[i] - tm;
      stt += dt * dt;
      sx += dt * (_x[i] - xm);
      sy += dt * (_y[i] - ym);
      sz += dt * (_z[i] - zm);
    }
    if (stt <= 0) return Vec3.zero;
    return Vec3(sx / stt, sy / stt, sz / stt);
  }

  Vec3 _fitSecond(double tS) {
    final n = _count(tS, snapWindowS, 5);
    if (n < 4) return Vec3.zero;
    // Normal equations for c0 + c1·τ + c2·τ², τ = t − t_now.
    var s0 = 0.0, s1 = 0.0, s2 = 0.0, s3 = 0.0, s4 = 0.0;
    final b = List<double>.filled(9, 0);
    for (var k = 0; k < n; k++) {
      final i = _index(k);
      final tau = _t[i] - tS;
      final t2 = tau * tau;
      s0 += 1;
      s1 += tau;
      s2 += t2;
      s3 += t2 * tau;
      s4 += t2 * t2;
      final values = [_x[i], _y[i], _z[i]];
      for (var c = 0; c < 3; c++) {
        b[c * 3] += values[c];
        b[c * 3 + 1] += values[c] * tau;
        b[c * 3 + 2] += values[c] * t2;
      }
    }
    // Cramer's rule for the c2 coefficient of the symmetric 3x3 system.
    final det = s0 * (s2 * s4 - s3 * s3) - s1 * (s1 * s4 - s3 * s2) + s2 * (s1 * s3 - s2 * s2);
    if (det.abs() < 1e-30) return Vec3.zero;
    double c2(int c) {
      final b0 = b[c * 3], b1 = b[c * 3 + 1], b2 = b[c * 3 + 2];
      final d = s0 * (s2 * b2 - b1 * s3) - s1 * (s1 * b2 - b1 * s2) + b0 * (s1 * s3 - s2 * s2);
      return d / det;
    }

    return Vec3(2 * c2(0), 2 * c2(1), 2 * c2(2));
  }
}
