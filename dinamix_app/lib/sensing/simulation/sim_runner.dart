import 'dart:math' as math;

import '../classify/classifier.dart';
import '../detection_engine.dart';
import '../motion_sample.dart';
import 'physics_simulator.dart';

class ScenarioResult {
  ScenarioResult(this.scenario, this.events, this.alarmAtS, this.profileName);

  final SimScenario scenario;
  final List<DetectionEvent> events;

  /// Stream time at which the first alarm was raised (null: no alarm).
  final double? alarmAtS;
  final String profileName;

  bool get alarm => alarmAtS != null;

  /// The most severe final event (level, then Δv).
  DetectionEvent? get strongest {
    DetectionEvent? best;
    for (final e in events) {
      if (best == null ||
          e.level.value > best.level.value ||
          (e.level.value == best.level.value && e.features.dvImpact > best.features.dvImpact)) {
        best = e;
      }
    }
    return best;
  }

  double? get latencyS {
    final t0 = scenario.expectation.alarm == true ? scenario.eventTimeS : null;
    final a = alarmAtS;
    return t0 != null && a != null ? a - t0 : null;
  }

  bool get categoryOk {
    final allowed = scenario.expectation.allowed;
    final s = strongest;
    if (s == null) return !scenario.expectation.mustDetect;
    if (allowed.isEmpty) return s.level.value <= 2;
    return allowed.contains(s.category);
  }

  bool get alarmOk {
    final expected = scenario.expectation.alarm;
    return expected == null || expected == alarm;
  }

  bool get passed => categoryOk && alarmOk;
}

/// Runs one scenario through the shared engine with a given sensor model.
ScenarioResult runScenario(SimScenario s, SensorModel model, SourceProfile profile, {int seed = 1}) {
  final samples = PhysicsSimulator(model, seed: seed).run(s);
  final engine = DetectionEngine(profile: profile.copyWith(nominalRateHz: model.rateHz));
  final events = <DetectionEvent>[];
  double? alarmAt;
  var now = 0.0;
  engine.addListener((e) {
    if (e.provisional) return;
    events.add(e);
    if (e.classification.alarm && alarmAt == null) alarmAt = now;
  });
  for (final sample in samples) {
    now = sample.tS;
    engine.ingest(sample);
  }
  engine.flush();
  return ScenarioResult(s, events, alarmAt, profile.name);
}

class Metrics {
  int tp = 0, fp = 0, fn = 0, tn = 0;

  double get precision => tp + fp == 0 ? double.nan : tp / (tp + fp);
  double get recall => tp + fn == 0 ? double.nan : tp / (tp + fn);
  double get f1 {
    final p = precision, r = recall;
    return (p + r) == 0 || p.isNaN || r.isNaN ? double.nan : 2 * p * r / (p + r);
  }

  void add(bool expectedDangerous, bool alarm) {
    if (expectedDangerous && alarm) tp++;
    if (!expectedDangerous && alarm) fp++;
    if (expectedDangerous && !alarm) fn++;
    if (!expectedDangerous && !alarm) tn++;
  }
}

/// Wilson score interval for a proportion k/n at 95%.
(double, double) wilson(int k, int n) {
  if (n == 0) return (double.nan, double.nan);
  const z = 1.959964;
  final p = k / n;
  final den = 1 + z * z / n;
  final centre = (p + z * z / (2 * n)) / den;
  final half = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / den;
  return (math.max(0, centre - half), math.min(1, centre + half));
}

/// Confusion between expected (first allowed category) and predicted categories.
Map<String, Map<String, int>> confusion(List<ScenarioResult> results) {
  final m = <String, Map<String, int>>{};
  for (final r in results) {
    final expected = r.scenario.id.replaceAll(RegExp(r'_\d+(cm|ms)$'), '');
    final predicted = r.strongest?.category.label ?? 'nessun evento';
    m.putIfAbsent(expected, () => {});
    m[expected]![predicted] = (m[expected]![predicted] ?? 0) + 1;
  }
  return m;
}

String levelLabel(DangerLevel l) => '${l.value} — ${l.label}';
