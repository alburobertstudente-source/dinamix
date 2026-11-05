import 'dart:math' as math;

import '../frame.dart';
import '../math/vec3.dart';
import '../motion_sample.dart';

/// One acceleration pulse inside an event: a contiguous run above the pulse level.
class Pulse {
  Pulse(this.startS, this.endS, this.dv, this.peak, {required this.afterFreeFallS});

  final double startS;
  final double endS;

  /// ∫ a_W dt over the pulse (m/s), trapezoidal on the real timestamps.
  final Vec3 dv;
  final double peak;

  /// Free-fall time ending right before this pulse (0 if none).
  final double afterFreeFallS;

  double get durationS => endS - startS;
}

/// Mathematical description of one movement (report §27.2).
class MovementFeatures {
  MovementFeatures();

  double startS = 0;
  double endS = 0;
  double get durationS => endS - startS;

  // Intensity.
  double peakA = 0;
  double get peakG => peakA / g0;
  double peakJerk = 0;
  double meanJerk = 0;
  double peakSnap = 0;
  double peakOmega = 0;
  double peakAlpha = 0;
  double rmsA = 0;
  bool saturated = false;

  /// ∫|a|² dt (m²/s³): intensity, not a physical energy.
  double signalEnergy = 0;

  /// Fraction of the signal energy in the vibration band.
  double highFrequencyRatio = 0;

  // Velocity.
  Vec3 dvNet = Vec3.zero;
  double dvImpulse = 0;
  double dvKinematic = 0;
  double get dvImpact => math.max(dvImpulse, dvKinematic);

  /// ½|Δv|² of the impact (J/kg).
  double get specificKineticEnergy => 0.5 * dvImpact * dvImpact;
  double? velocityStart;
  double? velocityEnd;

  /// Displacement estimate and 1-sigma, only when §27.4 allows it.
  double? displacement;
  double? displacementSigma;

  // Pulses.
  List<Pulse> pulses = const [];
  int get pulseCount => pulses.length;
  double dominance = 0;
  double alternation = 0;
  int bounces = 0;
  double bounceRegularity = 0;

  // Free fall.
  double freeFallS = 0;
  double freeFallMeanFRatio = 1;

  /// Time with |f| below 0.75 g in the 1.5 s before the main pulse (partial fall).
  double lowForceS = 0;

  // Orientation.
  double rotationPath = 0;
  double rotationNetDeg = 0;
  double postureChangeDeg = 0;
  bool finalFlat = false;

  // Oscillation.
  double dominantFrequencyHz = 0;
  double periodicity = 0;
  double zeroCrossingRate = 0;

  // Sustained acceleration (braking).
  double sustainedS = 0;
  double sustainedMeanG = 0;

  // Context.
  double preActivity = 0;
  double postActivity = 0;
  double preStillFraction = 0;
  double postStillS = 0;
  double postWindowS = 0;
  double get resumeRatio => postActivity / math.max(preActivity, 0.3);

  // GPS.
  double? gpsSpeedDrop;

  // Quality.
  double quality = 1;
  int gaps = 0;

  Map<String, Object?> toJson() => {
        'duration_s': durationS,
        'peak_a': peakA,
        'peak_g': peakG,
        'peak_jerk': peakJerk,
        'mean_jerk': meanJerk,
        'peak_snap': peakSnap,
        'peak_omega': peakOmega,
        'peak_alpha': peakAlpha,
        'rms_a': rmsA,
        'saturated': saturated,
        'signal_energy': signalEnergy,
        'hf_ratio': highFrequencyRatio,
        'dv_net': dvNet.norm,
        'dv_impulse': dvImpulse,
        'dv_kinematic': dvKinematic,
        'dv_impact': dvImpact,
        'specific_energy': specificKineticEnergy,
        'v_start': velocityStart,
        'v_end': velocityEnd,
        'displacement': displacement,
        'displacement_sigma': displacementSigma,
        'pulses': pulseCount,
        'dominance': dominance,
        'alternation': alternation,
        'bounces': bounces,
        'bounce_regularity': bounceRegularity,
        'free_fall_s': freeFallS,
        'free_fall_f_ratio': freeFallMeanFRatio,
        'low_force_s': lowForceS,
        'rotation_path_rad': rotationPath,
        'rotation_net_deg': rotationNetDeg,
        'posture_change_deg': postureChangeDeg,
        'final_flat': finalFlat,
        'dominant_hz': dominantFrequencyHz,
        'periodicity': periodicity,
        'zero_crossing_rate': zeroCrossingRate,
        'sustained_s': sustainedS,
        'sustained_mean_g': sustainedMeanG,
        'pre_activity': preActivity,
        'post_activity': postActivity,
        'pre_still': preStillFraction,
        'post_still_s': postStillS,
        'resume_ratio': resumeRatio,
        'gps_speed_drop': gpsSpeedDrop,
        'quality': quality,
        'gaps': gaps,
      };
}

class GpsFix {
  const GpsFix(this.tS, this.speed, this.accuracy);
  final double tS;
  final double speed;
  final double accuracy;
}

/// Computes [MovementFeatures] from the frames before, during and after an event.
class FeatureExtractor {
  const FeatureExtractor({
    this.pulseFloor = 0.3 * g0,
    this.pulseRelative = 0.15,
    this.maxImpactPulseS = 0.25,
    this.lowForceRatio = 0.75,
    this.sustainedLevel = 0.12 * g0,
    this.sustainedMaxJerk = 40,
  });

  /// PROVVISORIO: pulse level = max(0.3 g, 0.15·peak). The relative part keeps
  /// the smaller bounces visible after a strong impact.
  final double pulseFloor;
  final double pulseRelative;

  /// Contacts of falls and impacts last tens to a few hundred ms; longer runs are
  /// sustained accelerations (braking) and do not count as impact pulses.
  final double maxImpactPulseS;
  final double lowForceRatio;
  final double sustainedLevel;
  final double sustainedMaxJerk;

  MovementFeatures extract({
    required List<Frame> pre,
    required List<Frame> event,
    required List<Frame> post,
    List<GpsFix> gps = const [],
    double quality = 1,
    double leverArm = 0.08,
  }) {
    final m = MovementFeatures()..quality = quality;
    if (event.isEmpty) return m;
    m.startS = event.first.tS;
    m.endS = event.last.tS;

    // Intensity, energies and rotation over the event.
    var sumA2 = 0.0, sumHp2 = 0.0, sumJ = 0.0, energyT = 0.0;
    Vec3 dv = Vec3.zero;
    for (var i = 0; i < event.length; i++) {
      final fr = event[i];
      m.peakA = math.max(m.peakA, fr.aNorm);
      m.peakJerk = math.max(m.peakJerk, fr.jNorm);
      m.peakSnap = math.max(m.peakSnap, fr.snap.norm);
      m.peakOmega = math.max(m.peakOmega, fr.omegaNorm);
      m.peakAlpha = math.max(m.peakAlpha, fr.alpha.norm);
      m.saturated |= fr.saturated;
      if (fr.gapBefore) m.gaps++;
      sumJ += fr.jNorm;
      if (i > 0) {
        final prev = event[i - 1];
        final dt = fr.tS - prev.tS;
        if (dt > 0 && !fr.gapBefore) {
          dv = dv + (fr.aW + prev.aW) * (dt / 2);
          sumA2 += (fr.aNorm * fr.aNorm + prev.aNorm * prev.aNorm) * dt / 2;
          sumHp2 += (fr.highPass * fr.highPass + prev.highPass * prev.highPass) * dt / 2;
          m.rotationPath += (fr.omegaNorm + prev.omegaNorm) * dt / 2;
          energyT += dt;
        }
      }
    }
    m.dvNet = dv;
    m.signalEnergy = sumA2;
    m.rmsA = energyT > 0 ? math.sqrt(sumA2 / energyT) : event.first.aNorm;
    m.meanJerk = sumJ / event.length;
    m.highFrequencyRatio = sumA2 > 0 ? (sumHp2 / sumA2).clamp(0, 1).toDouble() : 0;

    _freeFall(m, [...pre.where((f) => f.tS >= m.startS - 1.5), ...event], leverArm);
    _pulses(m, pre, event);
    _orientation(m, pre, event, post);
    _oscillation(m, event);
    _sustained(m, event);
    _context(m, pre, post);
    _kinematics(m, pre, event, post);
    _gps(m, gps);
    return m;
  }

  void _freeFall(MovementFeatures m, List<Frame> frames, double leverArm) {
    var best = 0.0, bestSum = 0.0, bestCount = 0;
    double? runStart;
    var runSum = 0.0;
    var runCount = 0;
    for (var i = 0; i < frames.length; i++) {
      final fr = frames[i];
      if (fr.freeFall) {
        runStart ??= fr.tS;
        // Purity: |f| left after removing the largest lever-arm term ω²·r_max.
        runSum += math.max(0, fr.fNorm - fr.omega.norm2 * leverArm);
        runCount++;
        final length = fr.tS - runStart;
        if (length > best) {
          best = length;
          bestSum = runSum;
          bestCount = runCount;
        }
      } else {
        runStart = null;
        runSum = 0;
        runCount = 0;
      }
    }
    // A run of n samples spans n·Δt; add one period to the endpoint difference.
    if (bestCount > 0 && frames.length > 1) {
      final dt = (frames.last.tS - frames.first.tS) / (frames.length - 1);
      best += dt;
    }
    m.freeFallS = best;
    m.freeFallMeanFRatio = bestCount > 0 ? bestSum / bestCount / g0 : 1;
  }

  void _pulses(MovementFeatures m, List<Frame> pre, List<Frame> event) {
    final level = math.max(pulseFloor, pulseRelative * m.peakA);
    final pulses = <Pulse>[];
    var freeFallBefore = 0.0;
    double? ffStart;
    var i = 0;
    while (i < event.length) {
      final fr = event[i];
      if (fr.freeFall) {
        ffStart ??= fr.tS;
        freeFallBefore = fr.tS - ffStart;
      } else if (fr.aNorm < level) {
        ffStart = null;
      }
      if (fr.aNorm >= level && !fr.freeFall) {
        final start = i;
        while (i + 1 < event.length && event[i + 1].aNorm >= level * 0.8) {
          i++;
        }
        // Integrate from the sample before to the sample after the run.
        final a = math.max(0, start - 1);
        final b = math.min(event.length - 1, i + 1);
        Vec3 dv = Vec3.zero;
        var peak = 0.0;
        for (var k = a + 1; k <= b; k++) {
          final dt = event[k].tS - event[k - 1].tS;
          if (dt > 0) dv = dv + (event[k].aW + event[k - 1].aW) * (dt / 2);
        }
        for (var k = start; k <= i; k++) {
          peak = math.max(peak, event[k].aNorm);
        }
        pulses.add(Pulse(event[a].tS, event[b].tS, dv, peak,
            afterFreeFallS: ffStart != null || freeFallBefore > 0 ? freeFallBefore : 0));
        freeFallBefore = 0;
        ffStart = null;
      }
      i++;
    }
    // Merge pulses closer than 15 ms with the same direction (one physical contact).
    final merged = <Pulse>[];
    for (final p in pulses) {
      if (merged.isNotEmpty) {
        final last = merged.last;
        if (p.startS - last.endS < 0.015 && p.dv.dot(last.dv) > 0 && p.afterFreeFallS < 0.02) {
          merged[merged.length - 1] = Pulse(last.startS, p.endS, last.dv + p.dv,
              math.max(last.peak, p.peak),
              afterFreeFallS: last.afterFreeFallS);
          continue;
        }
      }
      merged.add(p);
    }
    m.pulses = merged.where((p) => p.durationS <= maxImpactPulseS).toList();
    if (m.pulses.isEmpty) {
      if (m.freeFallS > 0.05) m.dvKinematic = g0 * m.freeFallS;
      return;
    }
    merged
      ..clear()
      ..addAll(m.pulses);
    var gross = 0.0;
    var dominant = merged.first;
    for (final p in merged) {
      gross += p.dv.norm;
      if (p.dv.norm > dominant.dv.norm) dominant = p;
    }
    m.dvImpulse = dominant.dv.norm;
    m.dominance = gross > 0 ? dominant.dv.norm / gross : 0;
    if (merged.length >= 2) {
      var opposite = 0;
      for (var k = 1; k < merged.length; k++) {
        if (merged[k].dv.dot(merged[k - 1].dv) < 0) opposite++;
      }
      m.alternation = opposite / (merged.length - 1);
    }
    // Bounces: later pulses preceded by a ballistic flight (free fall).
    final index = merged.indexOf(dominant);
    final flights = <double>[];
    for (var k = index + 1; k < merged.length; k++) {
      if (merged[k].afterFreeFallS >= 0.02) {
        m.bounces++;
        flights.add(merged[k].afterFreeFallS);
      }
    }
    if (flights.length >= 2) {
      // Geometric decay: successive flight ratios below 1 and similar.
      var decreasing = 0;
      for (var k = 1; k < flights.length; k++) {
        if (flights[k] < flights[k - 1]) decreasing++;
      }
      m.bounceRegularity = decreasing / (flights.length - 1);
    } else if (flights.length == 1) {
      m.bounceRegularity = 0.5;
    }
    // Kinematic impact velocity: v = g·T_ff for a free fall ending at the pulse.
    if (dominant.afterFreeFallS > 0) {
      m.dvKinematic = g0 * dominant.afterFreeFallS;
    } else if (m.freeFallS > 0.05) {
      m.dvKinematic = g0 * m.freeFallS;
    }
    // Partial fall: low specific force before the main pulse (person falling).
    final window = [
      ...pre.where((f) => f.tS >= dominant.startS - 1.5),
      ...event.where((f) => f.tS < dominant.startS),
    ];
    var low = 0.0;
    for (var k = 1; k < window.length; k++) {
      if (window[k].fNorm < lowForceRatio * g0) low += window[k].tS - window[k - 1].tS;
    }
    m.lowForceS = low;
  }

  void _orientation(MovementFeatures m, List<Frame> pre, List<Frame> event, List<Frame> post) {
    Vec3 mean(Iterable<Frame> frames, Vec3 fallback) {
      Vec3 s = Vec3.zero;
      var n = 0;
      for (final f in frames) {
        s = s + f.up;
        n++;
      }
      return n == 0 ? fallback : s.normalized(fallback);
    }

    final upPre = mean(pre.where((f) => f.tS >= m.startS - 1.0), event.first.up);
    final settled = post.length > 10 ? post.sublist(post.length ~/ 2) : post;
    final upPost = mean(settled, event.last.up);
    m.postureChangeDeg = upPre.angleTo(upPost) * 180 / math.pi;
    m.rotationNetDeg = event.first.up.angleTo(event.last.up) * 180 / math.pi;
    m.finalFlat = upPost.z.abs() > 0.95;
  }

  void _oscillation(MovementFeatures m, List<Frame> event) {
    if (event.length < 12 || m.durationS < 0.15) return;
    // Principal axis of a_W (power iteration on the 3x3 covariance).
    Vec3 mean = Vec3.zero;
    for (final f in event) {
      mean = mean + f.aW;
    }
    mean = mean / event.length.toDouble();
    final c = List<double>.filled(9, 0);
    for (final f in event) {
      final d = f.aW - mean;
      final v = [d.x, d.y, d.z];
      for (var r = 0; r < 3; r++) {
        for (var s = 0; s < 3; s++) {
          c[r * 3 + s] += v[r] * v[s];
        }
      }
    }
    var axis = const Vec3(1, 1, 1).normalized();
    for (var it = 0; it < 20; it++) {
      axis = Vec3(
        c[0] * axis.x + c[1] * axis.y + c[2] * axis.z,
        c[3] * axis.x + c[4] * axis.y + c[5] * axis.z,
        c[6] * axis.x + c[7] * axis.y + c[8] * axis.z,
      ).normalized(axis);
    }
    final x = [for (final f in event) (f.aW - mean).dot(axis)];
    final times = [for (final f in event) f.tS];
    var crossings = 0;
    for (var k = 1; k < x.length; k++) {
      if ((x[k] >= 0) != (x[k - 1] >= 0)) crossings++;
    }
    m.zeroCrossingRate = crossings / math.max(m.durationS, 1e-3);
    // Normalized autocorrelation for periods between 1/14 s and 1/1.2 s.
    final dt = (times.last - times.first) / (times.length - 1);
    if (dt <= 0) return;
    var energy = 0.0;
    for (final v in x) {
      energy += v * v;
    }
    if (energy <= 0) return;
    final minLag = math.max(1, (1 / 14 / dt).round());
    final maxLag = math.min(x.length ~/ 2, (1 / 1.2 / dt).round());
    var bestLag = 0;
    var best = 0.0;
    // Period = highest autocorrelation peak after the first minimum (the
    // zero-lag lobe of a smooth signal is not a period).
    var previous = double.infinity;
    var pastMinimum = false;
    for (var lag = 1; lag <= maxLag; lag++) {
      var s = 0.0;
      for (var k = 0; k + lag < x.length; k++) {
        s += x[k] * x[k + lag];
      }
      final r = s / energy * x.length / (x.length - lag);
      if (!pastMinimum) {
        if (r > previous) pastMinimum = true;
        previous = r;
        if (!pastMinimum) continue;
      }
      if (lag >= minLag && r > best) {
        best = r;
        bestLag = lag;
      }
    }
    if (bestLag > 0) {
      m.periodicity = best.clamp(0, 1).toDouble();
      m.dominantFrequencyHz = 1 / (bestLag * dt);
    }
  }

  void _sustained(MovementFeatures m, List<Frame> event) {
    var best = 0.0, bestMean = 0.0;
    double? start;
    var sum = 0.0;
    var n = 0;
    for (final f in event) {
      // Low-pass band (2 Hz): vibrations do not break a sustained deceleration.
      final ok = f.aLowHorizontal > sustainedLevel && !f.freeFall;
      if (ok) {
        start ??= f.tS;
        sum += f.aLowHorizontal;
        n++;
        final length = f.tS - start;
        if (length > best) {
          best = length;
          bestMean = sum / n;
        }
      } else {
        start = null;
        sum = 0;
        n = 0;
      }
    }
    m.sustainedS = best;
    m.sustainedMeanG = bestMean / g0;
  }

  void _context(MovementFeatures m, List<Frame> pre, List<Frame> post) {
    double rms(Iterable<Frame> frames) {
      var s = 0.0;
      var n = 0;
      for (final f in frames) {
        s += f.aNorm * f.aNorm + 0.15 * f.omegaNorm * f.omegaNorm;
        n++;
      }
      return n == 0 ? 0 : math.sqrt(s / n);
    }

    final preWindow = pre.where((f) => f.tS >= m.startS - 3 && f.tS < m.startS - 0.1).toList();
    m.preActivity = rms(preWindow);
    final recent = pre.where((f) => f.tS >= m.startS - 1).toList();
    m.preStillFraction =
        recent.isEmpty ? 0 : recent.where((f) => f.still).length / recent.length;
    if (post.isNotEmpty) {
      m.postWindowS = post.last.tS - post.first.tS;
      final late = post.where((f) => f.tS >= post.last.tS - 4).toList();
      m.postActivity = rms(late);
      var run = 0.0, best = 0.0;
      for (var k = 1; k < post.length; k++) {
        if (post[k].still) {
          run += post[k].tS - post[k - 1].tS;
          best = math.max(best, run);
        } else {
          run = 0;
        }
      }
      m.postStillS = best;
    }
  }

  void _kinematics(MovementFeatures m, List<Frame> pre, List<Frame> event, List<Frame> post) {
    final startStill = pre.isNotEmpty && pre.last.still;
    final endStill = post.isNotEmpty && post.first.still;
    if (startStill) m.velocityStart = 0;
    if (m.postStillS > 0.5) m.velocityEnd = 0;
    final t = m.durationS;
    final zupt = startStill && endStill;
    if (t <= 0 || t > (zupt ? 2.0 : 1.0)) return;
    // Double trapezoidal integration with linear de-trending of v (ZUPT).
    final vs = <Vec3>[Vec3.zero];
    for (var k = 1; k < event.length; k++) {
      final dt = event[k].tS - event[k - 1].tS;
      vs.add(vs.last + (event[k].aW + event[k - 1].aW) * (dt / 2));
    }
    final vEnd = vs.last;
    Vec3 x = Vec3.zero;
    for (var k = 1; k < event.length; k++) {
      final dt = event[k].tS - event[k - 1].tS;
      var v0 = vs[k - 1], v1 = vs[k];
      if (zupt) {
        final f0 = (event[k - 1].tS - m.startS) / t;
        final f1 = (event[k].tS - m.startS) / t;
        v0 = v0 - vEnd * f0;
        v1 = v1 - vEnd * f1;
      }
      x = x + (v0 + v1) * (dt / 2);
    }
    m.displacement = x.norm;
    // σ from a 1° attitude error (gravity leak) over the window, report §27.4.
    const leak = g0 * 0.01745;
    m.displacementSigma = 0.5 * leak * t * t * (zupt ? 0.5 : 1);
  }

  void _gps(MovementFeatures m, List<GpsFix> gps) {
    GpsFix? before, after;
    for (final g in gps) {
      if (g.accuracy.isFinite && g.accuracy > 2.0) continue;
      if (g.tS <= m.startS - 0.2 && g.tS >= m.startS - 3) before = g;
      if (g.tS >= m.endS + 0.5 && g.tS <= m.endS + 4 && after == null) after = g;
    }
    if (before != null && after != null) m.gpsSpeedDrop = before.speed - after.speed;
  }
}
