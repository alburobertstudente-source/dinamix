import 'dart:math' as math;

import '../classify/classifier.dart';
import '../math/quaternion.dart';
import '../math/vec3.dart';
import '../motion_sample.dart';
import 'physics_simulator.dart';

typedef C = MovementCategory;

/// Phone upright in a trouser pocket: body y axis vertical.
final Quaternion pocket = Quaternion.fromAxisAngle(const Vec3(1, 0, 0), math.pi / 2);

/// Phone held in front of the user, screen tilted 40° toward the face.
final Quaternion inHand = Quaternion.fromAxisAngle(const Vec3(1, 0, 0), 40 * math.pi / 180);

Vec3 _randomAxis(math.Random r) =>
    Vec3(r.nextDouble() - 0.5, r.nextDouble() - 0.5, r.nextDouble() - 0.5).normalized();

/// Bounces of a free object after a drop from [height] (restitution [e]).
List<MotionComponent> dropWithBounces(double atS, double height, math.Random r,
    {double e = 0.3, double contactS = 0.004, Vec3? spin}) {
  final parts = <MotionComponent>[];
  final tff = math.sqrt(2 * height / g0);
  final rate = spin ?? _randomAxis(r) * (4 + r.nextDouble() * 8);
  parts.add(freeFall(atS, tff, spin: rate));
  var t = atS + tff;
  var v = g0 * tff;
  for (var k = 0; k < 4 && v > 0.25; k++) {
    final rebound = e * v;
    parts.add(pulse(t, contactS, v + rebound, const Vec3(0, 0, 1)));
    t += contactS;
    final flight = 2 * rebound / g0;
    if (flight < 0.015) break;
    parts.add(freeFall(t, flight, spin: rate * (0.4 / (k + 1))));
    t += flight;
    v = rebound;
  }
  return parts;
}

/// The catalogue of the specification (§15, §29) plus the anti-false-alarm cases.
/// Ground truth is set by construction; categories list what is acceptable.
List<SimScenario> buildScenarios(int seed) {
  final r = math.Random(seed);
  final scenarios = <SimScenario>[];

  scenarios.add(SimScenario(
    id: 'fermo',
    title: 'Smartphone completamente fermo',
    durationS: 20,
    components: const [],
    expectation: const Expectation(alarm: false),
  ));

  scenarios.add(SimScenario(
    id: 'camminata_tasca',
    title: 'Smartphone in tasca mentre si cammina',
    durationS: 30,
    initial: pocket,
    components: [walking(3, 27, stepHz: 1.7 + r.nextDouble() * 0.3)],
    expectation: const Expectation(allowed: {C.walkRun, C.handled, C.sport}, alarm: false),
  ));

  scenarios.add(SimScenario(
    id: 'corsa',
    title: 'Smartphone mentre si corre',
    durationS: 30,
    initial: pocket,
    components: [running(3, 27, stepHz: 2.6 + r.nextDouble() * 0.4)],
    expectation: const Expectation(allowed: {C.walkRun, C.sport, C.handled, C.ambiguous}, alarm: false),
  ));

  final handAxis = _randomAxis(r);
  scenarios.add(SimScenario(
    id: 'mano',
    title: 'Smartphone mosso con la mano',
    durationS: 20,
    initial: inHand,
    components: [
      holding(0, 20),
      reach(4, 0.6, 0.35, handAxis),
      turn(4.2, 0.8, 1.1, _randomAxis(r)),
      reach(8, 0.7, 0.4, -handAxis),
      turn(11, 0.6, -0.9, _randomAxis(r)),
    ],
    expectation: const Expectation(allowed: {C.handled, C.placed, C.surfaceHit, C.shakeShort}, alarm: false),
  ));

  for (final h in [0.3, 0.5, 0.75, 1.0, 1.5]) {
    scenarios.add(SimScenario(
      id: 'caduta_tavolo_${(h * 100).round()}cm',
      title: 'Smartphone lasciato cadere da ${h.toStringAsFixed(2)} m',
      durationS: 20,
      initial: inHand,
      components: [holding(0, 5), ...dropWithBounces(5, h, r)],
      settleFlatAtS: 5 + math.sqrt(2 * h / g0) + 0.3,
      eventTimeS: 5 + math.sqrt(2 * h / g0),
      dropHeightM: h,
      expectation: Expectation(
        allowed: const {C.phoneDropped, C.ambiguous, C.surfaceHit},
        alarm: h >= 1.0 ? null : false,
        mustDetect: true,
      ),
    ));
  }

  scenarios.add(SimScenario(
    id: 'caduta_tasca',
    title: 'Smartphone che cade da una tasca',
    durationS: 22,
    initial: pocket,
    components: [walking(2, 6), ...dropWithBounces(8, 0.75, r, e: 0.25)],
    settleFlatAtS: 8.7,
    eventTimeS: 8 + math.sqrt(1.5 / g0),
    dropHeightM: 0.75,
    expectation: const Expectation(allowed: {C.phoneDropped, C.ambiguous}, mustDetect: true),
  ));

  scenarios.add(SimScenario(
    id: 'urto',
    title: 'Smartphone che subisce un urto',
    durationS: 18,
    initial: inHand,
    components: [holding(0, 18), reach(5, 0.4, 0.15, const Vec3(0, 0, -1)), pulse(5.4, 0.008, 1.2, const Vec3(0, 0, 1))],
    eventTimeS: 5.4,
    expectation: const Expectation(allowed: {C.surfaceHit, C.placed, C.handled}, alarm: false, mustDetect: true),
  ));

  scenarios.add(SimScenario(
    id: 'lancio_morbido',
    title: 'Smartphone lanciato su una superficie morbida',
    durationS: 20,
    initial: inHand,
    components: [
      holding(0, 5),
      pulse(5, 0.25, 3.2, const Vec3(0.6, 0, 0.8)),
      freeFall(5.25, 0.5, spin: _randomAxis(r) * 7),
      pulse(5.75, 0.08, 4.2, const Vec3(-0.3, 0, 1)),
    ],
    settleFlatAtS: 5.9,
    eventTimeS: 5.75,
    // A thrown phone is in free fall like a person falling from ~1.2 m: with an
    // inertial sensor alone the case can be ambiguous, so an alarm is accepted.
    expectation: const Expectation(
        allowed: {C.phoneDropped, C.ambiguous, C.surfaceHit, C.handled}, mustDetect: true),
  ));

  scenarios.add(SimScenario(
    id: 'caduta_persona',
    title: 'Persona che cade con lo smartphone in tasca',
    durationS: 26,
    initial: pocket,
    components: [walking(2, 6), ...personFall(8.2)],
    eventTimeS: 8.9,
    expectation: const Expectation(
        allowed: {C.personFall, C.dangerousImpact, C.ambiguous}, alarm: true, mustDetect: true, dangerous: true),
  ));

  double brakeSpeed(double t, double start, double decel, double hold) {
    if (t < start) return 20;
    final v = 20 - decel * math.min(t - start, hold);
    return math.max(0, v);
  }

  scenarios.add(SimScenario(
    id: 'frenata',
    title: 'Frenata improvvisa (telefono nel supporto)',
    durationS: 22,
    components: [
      vibration(0, 22, 0.4, [13, 19, 27], seed: r.nextInt(1000)),
      _ramp(8, 2.6, -0.65 * g0, const Vec3(1, 0, 0)),
    ],
    gpsSpeed: (t) => brakeSpeed(t, 8, 0.65 * g0, 2.6),
    eventTimeS: 8,
    expectation: const Expectation(allowed: {C.brakeAccel, C.vibration, C.ambiguous}, alarm: false),
  ));

  scenarios.add(SimScenario(
    id: 'accelerazione',
    title: 'Accelerazione improvvisa',
    durationS: 20,
    components: [
      vibration(0, 20, 0.4, [13, 19, 27], seed: r.nextInt(1000)),
      _ramp(7, 3.0, 0.5 * g0, const Vec3(1, 0, 0)),
    ],
    gpsSpeed: (t) => t < 7 ? 2 : 2 + 0.5 * g0 * math.min(t - 7, 3),
    expectation: const Expectation(allowed: {C.brakeAccel, C.vibration, C.ambiguous}, alarm: false),
  ));

  scenarios.add(SimScenario(
    id: 'vibrazioni',
    title: 'Vibrazioni prolungate',
    durationS: 30,
    components: [vibration(4, 22, 3.0, [12, 17, 23, 31], seed: r.nextInt(1000))],
    expectation: const Expectation(allowed: {C.vibration, C.shakeRepeated, C.ambiguous, C.walkRun}, alarm: false),
  ));

  scenarios.add(SimScenario(
    id: 'rotazione',
    title: 'Rotazione improvvisa',
    durationS: 16,
    initial: inHand,
    components: [holding(0, 16), turn(6, 0.25, math.pi, _randomAxis(r))],
    eventTimeS: 6,
    // Above ~1000 °/s the lever-arm term ω²r can cancel gravity: ambiguous is honest.
    expectation: const Expectation(
        allowed: {C.handled, C.shakeShort, C.surfaceHit, C.placed, C.ambiguous}, alarm: false),
  ));

  scenarios.add(SimScenario(
    id: 'impatto_immobilita',
    title: 'Impatto seguito da immobilità',
    durationS: 28,
    initial: pocket,
    components: [
      walking(2, 6),
      pulse(8, 0.05, 4.5, const Vec3(1, 0, 0.2)),
      turn(8.02, 0.35, math.pi / 2, const Vec3(0, 0, -1)),
    ],
    eventTimeS: 8,
    expectation: const Expectation(
        allowed: {C.dangerousImpact, C.personFall, C.ambiguous}, alarm: true, mustDetect: true, dangerous: true),
  ));

  scenarios.add(SimScenario(
    id: 'gps_disturbato',
    title: 'Frenata con GPS disturbato',
    durationS: 22,
    components: [
      vibration(0, 22, 0.4, [13, 19, 27], seed: r.nextInt(1000)),
      _ramp(8, 2.6, -0.65 * g0, const Vec3(1, 0, 0)),
    ],
    gpsSpeed: (t) => brakeSpeed(t, 8, 0.65 * g0, 2.6),
    gpsNoise: 2.5,
    gpsOutlierRate: 0.2,
    gpsDropout: 0.3,
    expectation: const Expectation(allowed: {C.brakeAccel, C.vibration, C.ambiguous}, alarm: false),
  ));

  // Specific tests of §29.
  for (final cycles in [1, 2, 3]) {
    final hz = 6.0;
    scenarios.add(SimScenario(
      id: 'scossa_${(cycles / hz * 1000).round()}ms',
      title: 'Scuotimento violento di ${(cycles / hz).toStringAsFixed(2)} s',
      durationS: 16,
      initial: inHand,
      components: [holding(0, 16), shake(6, cycles, hz, (3 + r.nextDouble() * 3) * g0, _randomAxis(r))],
      eventTimeS: 6,
      expectation: const Expectation(
          allowed: {C.shakeShort, C.handled, C.surfaceHit, C.placed, C.ambiguous}, alarm: false, mustDetect: true),
    ));
  }

  scenarios.add(SimScenario(
    id: 'scossa_ripetuta',
    title: 'Scuotimento ripetuto per diversi secondi',
    durationS: 22,
    initial: inHand,
    components: [holding(0, 22), shake(6, 28, 4.5, 2.5 * g0, _randomAxis(r), wristRate: 6)],
    eventTimeS: 6,
    expectation: const Expectation(
        allowed: {C.shakeRepeated, C.shakeShort, C.handled, C.vibration, C.ambiguous}, alarm: false, mustDetect: true),
  ));

  scenarios.add(SimScenario(
    id: 'mtb_salto',
    title: 'Movimento sportivo intenso (MTB con salto)',
    durationS: 30,
    initial: pocket,
    components: [
      vibration(0, 30, 2.5, [9, 14, 21], seed: r.nextInt(1000)),
      for (var k = 0; k < 12; k++) pulse(3 + k * 1.7, 0.06, 0.9, const Vec3(0.2, 0, 1)),
      freeFall(12.3, 0.35),
      pulse(12.65, 0.15, 3.4, const Vec3(0, 0, 1)),
    ],
    eventTimeS: 12.65,
    expectation: const Expectation(
        allowed: {C.sport, C.vibration, C.walkRun, C.phoneDropped, C.surfaceHit, C.ambiguous, C.brakeAccel},
        alarm: false),
  ));

  scenarios.add(SimScenario(
    id: 'appoggio_tavolo',
    title: 'Smartphone appoggiato sul tavolo',
    durationS: 16,
    initial: inHand,
    components: [holding(0, 6), reach(5.5, 0.5, 0.25, const Vec3(0, 0, -1)), pulse(6.0, 0.012, 0.25, const Vec3(0, 0, 1))],
    settleFlatAtS: 5.6,
    expectation: const Expectation(allowed: {C.placed, C.handled, C.surfaceHit}, alarm: false),
  ));

  return scenarios;
}

/// Jerk-limited ramp to a constant acceleration [level] along [dir], holding it.
MotionComponent _ramp(double atS, double holdS, double level, Vec3 dir) {
  const rise = 0.35;
  final u = dir.normalized();
  return MotionComponent(atS, atS + holdS + 2 * rise, acc: (tau) {
    double k;
    if (tau < rise) {
      k = 0.5 - 0.5 * math.cos(math.pi * tau / rise);
    } else if (tau < rise + holdS) {
      k = 1;
    } else {
      k = 0.5 + 0.5 * math.cos(math.pi * (tau - rise - holdS) / rise);
    }
    return u * (level * k);
  });
}

/// Isolated spike on a still or walking background (property test §28.4).
SimScenario isolatedSpike(math.Random r, {required bool walkingBackground}) {
  final amplitudeG = 2 + r.nextDouble() * 13;
  final duration = 0.003 + r.nextDouble() * 0.027;
  final dv = amplitudeG * g0 * duration * 2 / math.pi;
  return SimScenario(
    id: 'picco_isolato',
    title: 'Picco isolato ${amplitudeG.toStringAsFixed(1)} g, ${(duration * 1000).toStringAsFixed(0)} ms',
    durationS: 18,
    initial: walkingBackground ? pocket : inHand,
    components: [
      if (walkingBackground) walking(1, 17) else holding(0, 18),
      pulse(7 + r.nextDouble(), duration, dv, _randomAxis(r)),
    ],
    expectation: const Expectation(alarm: false),
  );
}
