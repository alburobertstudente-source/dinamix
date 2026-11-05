import 'dart:math' as math;

import 'package:dinamix/sensing/motion_sample.dart';
import 'package:dinamix/sensing/simulation/physics_simulator.dart';
import 'package:dinamix/sensing/simulation/scenarios.dart';
import 'package:dinamix/sensing/simulation/sim_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final sources = [
    ('telefono 200 Hz', SensorModel.phone200, SourceProfile.phone),
    ('telefono 100 Hz', SensorModel.phone100, SourceProfile.phone),
    ('SensorTile 50 Hz', SensorModel.sensorTile50, SourceProfile.sensorTile),
  ];

  for (final (name, model, profile) in sources) {
    group('Scenari simulati, $name', () {
      for (final s in buildScenarios(1)) {
        test(s.title, () {
          final r = runScenario(s, model, profile, seed: 1);
          final e = r.strongest;
          final what = e == null ? 'nessun evento' : '${e.category.label} L${e.level.value}';
          expect(r.categoryOk, isTrue, reason: 'categoria non attesa: $what');
          expect(r.alarmOk, isTrue, reason: 'allarme=${r.alarm}, atteso ${s.expectation.alarm}');
        });
      }
    });
  }

  test('caduta libera misurata coerente con √(2h/g) e Δv con √(2gh)', () {
    for (final s in buildScenarios(2).where((s) => s.dropHeightM != null && s.id.startsWith('caduta_tavolo'))) {
      final r = runScenario(s, SensorModel.phone200, SourceProfile.phone, seed: 2);
      final f = r.strongest!.features;
      final h = s.dropHeightM!;
      final expectedT = math.sqrt(2 * h / g0);
      expect(f.freeFallS, closeTo(expectedT, 0.15 * expectedT + 0.01), reason: s.id);
      expect(f.dvKinematic, closeTo(math.sqrt(2 * g0 * h), 0.15 * math.sqrt(2 * g0 * h) + 0.1),
          reason: s.id);
    }
  });

  test('proprietà anti-falsi allarmi: un picco isolato non attiva mai l\'allarme', () {
    final random = math.Random(2026);
    var runs = 0;
    for (var i = 0; i < 120; i++) {
      final s = isolatedSpike(random, walkingBackground: i.isOdd);
      final model = i % 3 == 0 ? SensorModel.sensorTile50 : SensorModel.phone200;
      final profile = i % 3 == 0 ? SourceProfile.sensorTile : SourceProfile.phone;
      final r = runScenario(s, model, profile, seed: i);
      expect(r.alarm, isFalse, reason: s.title);
      runs++;
    }
    expect(runs, 120);
  });
}
