import 'dart:math' as math;

import 'package:dinamix/sensing/detection_engine.dart';
import 'package:dinamix/sensing/math/vec3.dart';
import 'package:dinamix/sensing/motion_sample.dart';
import 'package:dinamix/sensing/simulation/physics_simulator.dart';
import 'package:dinamix/sensing/simulation/scenarios.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('carico e durata: 10 minuti a 200 Hz, memoria limitata, tempo per campione', () {
    // 10 min of mixed activity, built from simulated scenarios played back to back.
    final pieces = buildScenarios(5).where((s) => !s.expectation.dangerous).toList();
    final engine = DetectionEngine(profile: SourceProfile.phone);
    var offsetNs = 0;
    var samples = 0;
    var maxPre = 0, maxEvent = 0, maxPost = 0;
    final watch = Stopwatch();
    var k = 0;
    while (offsetNs < 600e9) {
      final s = pieces[k++ % pieces.length];
      final data = PhysicsSimulator(SensorModel.phone200, seed: k).run(s);
      watch.start();
      for (final m in data) {
        engine.ingest(MotionSample(m.kind, m.tNs + offsetNs, m.v));
        samples++;
      }
      watch.stop();
      final b = engine.bufferSizes;
      maxPre = math.max(maxPre, b.pre);
      maxEvent = math.max(maxEvent, b.event);
      maxPost = math.max(maxPost, b.post);
      offsetNs += (s.durationS * 1e9).round() + 5000000;
    }
    final usPerSample = watch.elapsedMicroseconds / samples;
    // ignore: avoid_print
    print('campioni $samples, ${usPerSample.toStringAsFixed(1)} µs/campione, eventi ${engine.eventsDetected}, '
        'buffer max pre=$maxPre evento=$maxEvent post=$maxPost');
    // Bounded: pre ≤ 6 s, episode ≤ 6 s + post 8 s at 200 Hz (with margin).
    expect(maxPre, lessThan(6.5 * 200));
    expect(maxEvent + maxPost, lessThan(30 * 200));
    // 200 Hz × 2 sensors = 400 samples/s: the budget is 2500 µs per sample.
    // A generous bound for slow CI machines; the measured value is printed.
    expect(usPerSample, lessThan(200));
  });

  test('flusso con buchi, timestamp fuori ordine e valori non finiti: nessuna eccezione', () {
    final engine = DetectionEngine();
    final r = math.Random(1);
    var t = 0;
    for (var i = 0; i < 20000; i++) {
      t += r.nextInt(10) == 0 ? -1000000 : 5000000 + (r.nextInt(100) == 0 ? 400000000 : 0);
      final v = r.nextInt(500) == 0
          ? const Vec3(double.nan, 0, 0)
          : Vec3(r.nextDouble() - 0.5, r.nextDouble() - 0.5, 9.8 + r.nextDouble());
      engine.ingest(MotionSample(i.isEven ? SampleKind.acc : SampleKind.gyro, t, v));
    }
    engine.flush();
    expect(engine.framesProcessed, greaterThan(0));
    expect(engine.rejectedSamples, greaterThan(0));
    expect(engine.latest!.aW.isFinite, isTrue, reason: 'stato avvelenato da un NaN');
    expect(engine.orientation.upInBody.isFinite, isTrue);
  });
}
