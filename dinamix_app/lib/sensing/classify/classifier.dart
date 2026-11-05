import 'dart:math' as math;

import '../events/features.dart';
import '../motion_sample.dart';

/// Movement categories (report §9.5, §28.2).
enum MovementCategory {
  walkRun('Corsa o camminata', dangerous: false),
  shakeShort('Telefono scosso', dangerous: false),
  shakeRepeated('Telefono agitato ripetutamente', dangerous: false),
  placed('Appoggiato o spostato', dangerous: false),
  handled('Telefono manipolato o ruotato', dangerous: false),
  phoneDropped('Telefono lasciato cadere', dangerous: false),
  surfaceHit('Telefono urtato', dangerous: false),
  sport('Movimento sportivo', dangerous: false),
  brakeAccel('Frenata o accelerazione', dangerous: false),
  vibration('Vibrazioni prolungate', dangerous: false),
  personFall('Possibile caduta della persona', dangerous: true),
  dangerousImpact('Impatto potenzialmente pericoloso', dangerous: true),
  ambiguous('Situazione ambigua', dangerous: false);

  const MovementCategory(this.label, {required this.dangerous});

  final String label;
  final bool dangerous;
}

/// Levels 0–4 (report §11.5).
enum DangerLevel {
  normal(0, 'Movimento normale'),
  slight(1, 'Anomalia lieve'),
  intense(2, 'Accelerazione intensa'),
  potentiallyDangerous(3, 'Evento potenzialmente pericoloso'),
  extreme(4, 'Evento estremamente anomalo');

  const DangerLevel(this.value, this.label);
  final int value;
  final String label;
}

/// Independent groups of physical evidence (report §28.4). Peak, jerk and energy
/// of the same pulse are one group.
enum CueGroup { impact, fall, posture, inactivity, gps }

class Classification {
  Classification({
    required this.category,
    required this.level,
    required this.confidence,
    required this.severity,
    required this.scores,
    required this.cues,
    required this.margin,
    required this.alarm,
    required this.reasons,
  });

  final MovementCategory category;
  final DangerLevel level;

  /// Heuristic index in [0, 1], NOT a calibrated probability (report §11.6).
  final double confidence;
  final double severity;
  final Map<MovementCategory, double> scores;
  final Map<CueGroup, double> cues;
  final double margin;
  final bool alarm;
  final List<String> reasons;

  int get concordantGroups => cues.values.where((v) => v > 0.5).length;

  Map<String, Object?> toJson() => {
        'category': category.name,
        'level': level.value,
        'confidence': confidence,
        'severity': severity,
        'margin': margin,
        'alarm': alarm,
        'scores': {for (final e in scores.entries) e.key.name: e.value},
        'cues': {for (final e in cues.entries) e.key.name: e.value},
        'reasons': reasons,
      };
}

/// Smooth step: 0 well below [x0], 1 well above, width [s] (report §11.4).
double rise(double x, double x0, double s) => 1 / (1 + math.exp(-(x - x0) / s));
double fall(double x, double x0, double s) => 1 - rise(x, x0, s);

/// Rule-based classifier with physical anchors. Every constant is PROVVISORIO
/// and documented in docs/SOGLIE.md; they are anchored to physics, then
/// checked on the simulator. They must be recalibrated on real labelled data.
class MovementClassifier {
  const MovementClassifier({this.ambiguityMargin = 0.12, this.minQuality = 0.35});

  final double ambiguityMargin;
  final double minQuality;

  Classification classify(MovementFeatures m, {bool provisional = false}) {
    final reasons = <String>[];
    final dvImpact = m.dvImpact;
    final pureFreeFall = rise(m.freeFallS, 0.10, 0.025) * fall(m.freeFallMeanFRatio, 0.3, 0.06);
    final active = rise(m.preActivity, 0.8, 0.25) * fall(m.preStillFraction, 0.6, 0.1);
    final resumed = rise(m.resumeRatio, 0.45, 0.1);
    final notResumed = 1 - resumed;
    final postKnown = !provisional && m.postWindowS >= 2;

    // Independent cue groups.
    final cues = <CueGroup, double>{
      // 2 m/s ≈ impact speed of a 0.2 m drop: √(2gh).
      CueGroup.impact: rise(dvImpact, 2.0, 0.35),
      CueGroup.fall: math.max(pureFreeFall, rise(m.lowForceS, 0.2, 0.05)),
      CueGroup.posture: rise(m.postureChangeDeg, 50, 8),
      CueGroup.inactivity:
          postKnown ? rise(m.postStillS, 3, 0.8) * notResumed * active : 0,
      if (m.gpsSpeedDrop != null) CueGroup.gps: rise(m.gpsSpeedDrop!, 3, 1),
    };
    const weights = {
      CueGroup.impact: 0.9,
      CueGroup.fall: 0.6,
      CueGroup.posture: 0.6,
      CueGroup.inactivity: 0.7,
      CueGroup.gps: 0.5,
    };
    var keep = 1.0;
    cues.forEach((k, v) => keep *= 1 - weights[k]! * v);
    final severity = 1 - keep;

    final noFreeFall = fall(m.freeFallS, 0.06, 0.02);
    // Shake: alternating similar pulses, or a regular oscillation above the step
    // frequencies (3–12 Hz) with hand-like amplitude.
    // A hand shakes at 3–8 Hz: two pulses per cycle, so ≥ 3 pulses/s (reaching
    // for something gives about one).
    final pulseRate = m.pulseCount / math.max(m.durationS, 0.1);
    final pulseShake = rise(m.alternation, 0.55, 0.1) *
        fall(m.dominance, 0.55, 0.1) *
        rise(m.pulseCount.toDouble(), 2.5, 0.4) *
        rise(pulseRate, 3, 0.6);
    final oscillationShake = rise(m.periodicity, 0.5, 0.1) *
        rise(m.dominantFrequencyHz, 3.0, 0.3) *
        fall(m.dominantFrequencyHz, 12, 1) *
        rise(m.peakG, 1.2, 0.3);
    final shakeShape = math.max(pulseShake, oscillationShake) *
        noFreeFall *
        fall(m.highFrequencyRatio, 0.5, 0.08);
    final stepLike = rise(m.periodicity, 0.45, 0.1) *
        rise(m.dominantFrequencyHz, 1.2, 0.15) *
        fall(m.dominantFrequencyHz, 3.4, 0.2);
    final bouncy = math.max(rise(m.bounces.toDouble(), 0.5, 0.2) * (0.5 + 0.5 * m.bounceRegularity),
        m.finalFlat ? 0.6 : 0.0);

    final scores = <MovementCategory, double>{
      MovementCategory.shakeShort: shakeShape * fall(m.durationS, 1.2, 0.3) * resumedOr(postKnown, resumed),
      MovementCategory.shakeRepeated: shakeShape * rise(m.durationS, 1.2, 0.3) *
          math.max(0.5, rise(m.periodicity, 0.3, 0.1)),
      // Flight phases of running are periodic free falls: allowed here.
      MovementCategory.walkRun: stepLike * fall(m.peakG, 4.0, 0.5) * fall(m.dvImpulse, 2.5, 0.4) *
          rise(m.durationS, 1.5, 0.4),
      MovementCategory.placed: fall(dvImpact, 0.9, 0.2) * noFreeFall *
          (postKnown ? rise(m.postStillS, 1.5, 0.5) : 0.5) * fall(m.pulseCount.toDouble(), 3.5, 0.5) *
          (m.finalFlat ? 1.0 : 0.6) * fall(stepLike, 0.5, 0.1),
      MovementCategory.handled: rise(m.rotationPath, 1.2, 0.3) * fall(dvImpact, 1.6, 0.3) *
          fall(shakeShape, 0.5, 0.1) * noFreeFall * fall(stepLike, 0.5, 0.1),
      MovementCategory.phoneDropped: pureFreeFall * rise(dvImpact, 1.0, 0.3) * bouncy *
          (postKnown ? notResumed : 0.7),
      MovementCategory.surfaceHit: rise(m.dominance, 0.55, 0.1) * rise(dvImpact, 0.5, 0.15) *
          fall(dvImpact, 3.0, 0.4) * noFreeFall * fall(m.postureChangeDeg, 45, 8) *
          fall(shakeShape, 0.5, 0.1) * fall(m.preActivity, 6, 1.5),
      MovementCategory.sport: (postKnown ? resumed : 0.4) * rise(m.preActivity, 2.0, 0.5) *
          math.max(rise(m.peakG, 2.0, 0.4), rise(dvImpact, 1.5, 0.4)) *
          fall(m.postureChangeDeg, 50, 8) * fall(shakeShape, 0.5, 0.1),
      MovementCategory.brakeAccel: rise(m.sustainedS, 0.8, 0.2) * rise(m.sustainedMeanG, 0.12, 0.03) *
          fall(dvImpact - m.sustainedS * m.sustainedMeanG * g0, 2.0, 0.5) * noFreeFall,
      MovementCategory.vibration: rise(m.highFrequencyRatio, 0.45, 0.08) * rise(m.durationS, 2.5, 0.7) *
          fall(dvImpact, 1.5, 0.3),
      MovementCategory.personFall: cues[CueGroup.posture]! * rise(dvImpact, 1.5, 0.35) *
          (1 - pureFreeFall * 0.85) * fall(m.bounces.toDouble(), 1.5, 0.3) *
          (postKnown ? notResumed : 0.6) * fall(shakeShape, 0.5, 0.1),
      // One dominant impulse in one direction (a push–pull has two equal ones).
      MovementCategory.dangerousImpact: rise(dvImpact, 3.0, 0.45) * (postKnown ? notResumed : 0.6) *
          math.max(rise(m.dominance, 0.6, 0.08), m.freeFallS > 0.1 ? 1.0 : 0.0) *
          (1 - pureFreeFall * bouncy * 0.8) * fall(shakeShape, 0.5, 0.1),
    };

    final ranked = scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final best = ranked.first;
    final second = ranked.length > 1 ? ranked[1] : best;
    final margin = best.value - second.value;
    var category = best.key;

    if (best.value < 0.2) {
      category = MovementCategory.ambiguous;
      reasons.add('nessuno schema riconosciuto (punteggio ${best.value.toStringAsFixed(2)})');
    } else if (margin < ambiguityMargin && best.key.dangerous != second.key.dangerous) {
      category = MovementCategory.ambiguous;
      reasons.add('${best.key.label} e ${second.key.label} quasi equivalenti');
    }
    if (m.quality < minQuality && category != MovementCategory.ambiguous) {
      reasons.add('qualità dei dati bassa (${m.quality.toStringAsFixed(2)})');
      category = MovementCategory.ambiguous;
    }

    final impact = cues[CueGroup.impact]!;
    final groups = cues.values.where((v) => v > 0.5).length;
    final dangerousContext = category.dangerous ||
        (category == MovementCategory.ambiguous &&
            ((best.key.dangerous && best.value >= 0.2) ||
                (second.key.dangerous && second.value >= 0.2) ||
                m.quality < minQuality) &&
            impact > 0.5);

    DangerLevel level;
    if (dangerousContext && impact > 0.5 && groups >= 2) {
      final extreme = (dvImpact >= 6 || (m.saturated && dvImpact >= 4)) &&
          groups >= 3 &&
          cues[CueGroup.inactivity]! > 0.5;
      level = extreme ? DangerLevel.extreme : DangerLevel.potentiallyDangerous;
      reasons.add('$groups gruppi di indizi concordi');
    } else if (impact > 0.5 ||
        (m.peakG > 4 && dvImpact > 1.0) ||
        (category == MovementCategory.brakeAccel && m.sustainedMeanG > 0.4)) {
      level = DangerLevel.intense;
    } else if (category == MovementCategory.walkRun || category == MovementCategory.vibration) {
      level = m.peakG > 2 ? DangerLevel.slight : DangerLevel.normal;
    } else {
      level = DangerLevel.slight;
    }
    if (impact > 0.5 && groups < 2) {
      reasons.add('un solo gruppo di indizi: un picco da solo non basta');
    }

    // The alarm needs the post-event phase, except for extreme events (§28.4).
    final alarm = level.value >= 3 && (postKnown || level == DangerLevel.extreme);
    final confidence = (math.min(1.0, m.quality) *
            math.sqrt(best.value.clamp(0, 1)) *
            (0.5 + 0.5 * math.min(1.0, margin / 0.3)))
        .clamp(0.0, 1.0)
        .toDouble();
    return Classification(
      category: category,
      level: level,
      confidence: confidence,
      severity: severity,
      scores: scores,
      cues: cues,
      margin: margin,
      alarm: alarm,
      reasons: reasons,
    );
  }

  static double resumedOr(bool postKnown, double resumed) => postKnown ? 0.4 + 0.6 * resumed : 0.8;
}

/// Severity reference used by the diagnostics: equivalent drop height of Δv.
double equivalentDropHeight(double dv) => dv * dv / (2 * g0);
