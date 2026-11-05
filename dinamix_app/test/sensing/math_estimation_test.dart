import 'dart:math' as math;

import 'package:dinamix/sensing/estimation/derivative.dart';
import 'package:dinamix/sensing/estimation/orientation.dart';
import 'package:dinamix/sensing/estimation/statistics.dart';
import 'package:dinamix/sensing/estimation/tick_clock.dart';
import 'package:dinamix/sensing/math/quaternion.dart';
import 'package:dinamix/sensing/math/vec3.dart';
import 'package:dinamix/sensing/motion_sample.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Quaternion', () {
    test('rotates a vector by a known angle', () {
      final q = Quaternion.fromAxisAngle(const Vec3(0, 0, 1), math.pi / 2);
      final v = q.rotate(const Vec3(1, 0, 0));
      expect(v.x, closeTo(0, 1e-12));
      expect(v.y, closeTo(1, 1e-12));
      expect(q.rotateInverse(v).x, closeTo(1, 1e-12));
    });

    test('between maps one direction onto another, including opposite ones', () {
      for (final pair in [
        (const Vec3(0, 1, 0), Vec3.unitZ),
        (const Vec3(0.3, -0.2, 0.9), const Vec3(-1, 0, 0)),
        (Vec3.unitZ, -Vec3.unitZ),
      ]) {
        final q = Quaternion.between(pair.$1, pair.$2);
        final r = q.rotate(pair.$1.normalized());
        expect(r.angleTo(pair.$2), lessThan(1e-9));
      }
    });

    test('integration of a constant rate is exact', () {
      var q = Quaternion.identity;
      const omega = Vec3(0, 0, 2);
      for (var i = 0; i < 1000; i++) {
        q = q * Quaternion.fromRotationVector(omega, 0.001);
      }
      expect(q.angle, closeTo(2, 1e-9));
    });
  });

  group('Orientation estimator', () {
    test('converges to a static tilt and leaves no dynamic acceleration', () {
      final est = OrientationEstimator();
      final up = const Vec3(0.4, 0.5, 0.77).normalized();
      final f = up * g0;
      for (var i = 0; i < 2000; i++) {
        final t = i * 5000000;
        est.onGyro(t, Vec3.zero);
        est.onAccelerometer(t, f);
      }
      expect(est.upInBody.angleTo(up), lessThan(0.002));
      expect(est.dynamicWorld(f).norm, lessThan(0.02));
    });

    test('a fast rotation tracked by the gyro does not create false acceleration', () {
      // Low-pass alone would leave 2g·sin(θ/2) = 1.41 g after a 90° step (report §4.1).
      final est = OrientationEstimator();
      var q = Quaternion.identity;
      const dt = 0.005;
      var worst = 0.0;
      for (var i = 0; i < 1600; i++) {
        final t = i * dt;
        final rate = t >= 4 && t < 4.3 ? Vec3(math.pi / 2 / 0.3, 0, 0) : Vec3.zero;
        q = (q * Quaternion.fromRotationVector(rate, dt)).normalized();
        final f = q.rotateInverse(const Vec3(0, 0, g0));
        final tNs = (t * 1e9).round();
        est.onGyro(tNs, rate);
        est.onAccelerometer(tNs, f);
        if (t > 3) worst = math.max(worst, est.dynamicWorld(f).norm);
      }
      expect(worst, lessThan(0.15 * g0));
    });

    test('learns the gyro bias at rest', () {
      final est = OrientationEstimator();
      const bias = Vec3(0.01, -0.02, 0.005);
      for (var i = 0; i < 4000; i++) {
        final t = i * 5000000;
        est.onGyro(t, bias);
        est.onAccelerometer(t, const Vec3(0, 0, g0));
        if (i > 200) est.learnAtRest(bias, g0);
      }
      expect((est.bias - bias).norm, lessThan(1e-4));
    });
  });

  group('Least-squares derivative', () {
    test('slope of a ramp and second derivative of a parabola are exact', () {
      final d = LsDerivative();
      for (var i = 0; i < 100; i++) {
        final t = i * 0.005 + (i.isEven ? 0.0007 : 0); // irregular timestamps
        d.add(t, Vec3(3 * t, -2 * t, 5 * t * t));
      }
      expect(d.slope.x, closeTo(3, 1e-9));
      expect(d.slope.y, closeTo(-2, 1e-9));
      expect(d.second.z, closeTo(10, 1e-6));
    });

    test('reduces the noise of the two-point difference', () {
      final r = math.Random(7);
      double gauss() =>
          math.sqrt(-2 * math.log(r.nextDouble() + 1e-12)) * math.cos(2 * math.pi * r.nextDouble());
      final d = LsDerivative(windowS: 0.03);
      final raw = <double>[];
      final ls = <double>[];
      for (var i = 0; i < 4000; i++) {
        d.add(i * 0.005, Vec3(gauss() * 0.02, 0, 0));
        if (i > 20) {
          raw.add(d.rawDifference.x);
          ls.add(d.slope.x);
        }
      }
      double rms(List<double> v) => math.sqrt(v.map((e) => e * e).reduce((a, b) => a + b) / v.length);
      // 7 samples: theoretical variance ratio N(N²−1)/24 = 14, so RMS ratio ≈ 3.7.
      expect(rms(raw) / rms(ls), greaterThan(3));
    });
  });

  group('Robust baseline', () {
    test('a burst of outliers does not drag the median', () {
      final b = RobustBaseline(initialMedian: 0, minMad: 0.01);
      for (var i = 0; i < 2000; i++) {
        final v = i % 50 == 0 ? 50.0 : 1.0 + (i % 7) * 0.01;
        b.add(i * 0.01, v);
      }
      expect(b.median, closeTo(1.03, 0.03));
      expect(b.z(1.03).abs(), lessThan(1));
      expect(b.z(50), greaterThan(100));
    });
  });

  group('BLE tick clock', () {
    test('recovers the tick period under positive latency and counter wraps', () {
      final r = math.Random(3);
      final clock = TickClock();
      const tickS = 0.001; // unknown to the estimator
      var raw = 64000;
      var trueT = 100.0;
      final errors = <double>[];
      for (var i = 0; i < 3000; i++) {
        raw = (raw + 20) & 0xFFFF; // 50 Hz, wraps every ~65 s
        trueT += 20 * tickS;
        final latency = 0.007 + r.nextDouble() * 0.03 * r.nextDouble();
        final est = clock.add(raw, trueT + latency);
        if (i > 300) errors.add(est - trueT);
      }
      expect(clock.tickPeriodS, closeTo(tickS, tickS * 0.002));
      // Lower envelope: the estimate keeps only the minimum latency (~7 ms) as offset,
      // and its jitter is far below the receive jitter.
      final mean = errors.reduce((a, b) => a + b) / errors.length;
      final spread = errors.map((e) => (e - mean).abs()).reduce(math.max);
      expect(mean, closeTo(0.007, 0.002));
      expect(spread, lessThan(0.003));
    });
  });
}
