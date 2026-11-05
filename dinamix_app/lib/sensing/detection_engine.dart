import 'dart:collection';
import 'dart:math' as math;

import 'classify/classifier.dart';
import 'estimation/derivative.dart';
import 'estimation/orientation.dart';
import 'estimation/statistics.dart';
import 'events/features.dart';
import 'frame.dart';
import 'math/vec3.dart';
import 'motion_sample.dart';

/// Engine parameters. All PROVVISORIO, documented in docs/SOGLIE.md.
class EngineConfig {
  const EngineConfig({
    this.zOn = 7,
    this.zOff = 3,
    this.triggerMinA = 0.4 * g0,
    this.activeMinA = 0.25 * g0,
    this.triggerOmega = 5,
    this.freeFallBase = 0.35 * g0,
    this.freeFallTriggerS = 0.06,
    this.stillStd = 0.12,
    this.stillOmega = 0.08,
    this.endQuietS = 0.7,
    this.postWindowS = 8,
    this.maxActiveS = 6,
    this.preWindowS = 6,
    this.vibrationCutoffHz = 10,
  });

  final double zOn;
  final double zOff;
  final double triggerMinA;
  final double activeMinA;
  final double triggerOmega;
  final double freeFallBase;
  final double freeFallTriggerS;
  final double stillStd;
  final double stillOmega;
  final double endQuietS;
  final double postWindowS;
  final double maxActiveS;
  final double preWindowS;
  final double vibrationCutoffHz;

  Map<String, Object> toJson() => {
        'z_on': zOn,
        'z_off': zOff,
        'trigger_min_a': triggerMinA,
        'active_min_a': activeMinA,
        'trigger_omega': triggerOmega,
        'free_fall_base': freeFallBase,
        'free_fall_trigger_s': freeFallTriggerS,
        'still_std': stillStd,
        'still_omega': stillOmega,
        'end_quiet_s': endQuietS,
        'post_window_s': postWindowS,
        'max_active_s': maxActiveS,
      };
}

const String algorithmVersion = 'dynamix-1.0.0';

/// A raw sample kept with an event, for later analysis.
class RawSample {
  const RawSample(this.tS, this.f, this.omega);
  final double tS;
  final Vec3 f;
  final Vec3 omega;
}

class DetectionEvent {
  DetectionEvent({
    required this.id,
    required this.provisional,
    required this.features,
    required this.classification,
    required this.raw,
    required this.source,
  });

  final int id;
  final bool provisional;
  final MovementFeatures features;
  final Classification classification;
  final List<RawSample> raw;
  final SourceProfile source;

  DangerLevel get level => classification.level;
  MovementCategory get category => classification.category;
}

/// Signal quality factors (report §11.6), each in [0, 1].
class QualityReport {
  const QualityReport({
    required this.rateHz,
    required this.rate,
    required this.gaps,
    required this.saturation,
    required this.orientation,
    required this.gyro,
    required this.timing,
  });

  final double rateHz;
  final double rate;
  final double gaps;
  final double saturation;
  final double orientation;
  final double gyro;
  final double timing;

  double get value => (rate * gaps * saturation * orientation * gyro * timing).clamp(0.0, 1.0);
}

enum _State { idle, active, post }

/// The shared detection engine: same code for phone, SensorTile, simulator
/// and replay (report §25.4). Feed it with [ingest] in time order.
class DetectionEngine {
  DetectionEngine({
    this.profile = SourceProfile.phone,
    this.config = const EngineConfig(),
    this.classifier = const MovementClassifier(),
    this.extractor = const FeatureExtractor(),
  }) : _baseline = RobustBaseline(initialMedian: 0.02 * g0, minMad: 0.01 * g0);

  SourceProfile profile;
  final EngineConfig config;
  final MovementClassifier classifier;
  final FeatureExtractor extractor;

  final OrientationEstimator orientation = OrientationEstimator();
  final LsDerivative _jerk = LsDerivative();
  final LsDerivative _alpha = LsDerivative();
  final RobustBaseline _baseline;
  final WindowStats _stillF = WindowStats(0.6);
  final WindowStats _stillW = WindowStats(0.6);
  final ListQueue<Frame> _pre = ListQueue<Frame>();
  final List<Frame> _event = [];
  final List<Frame> _post = [];
  final List<GpsFix> _gps = [];
  final List<void Function(DetectionEvent)> _listeners = [];

  List<Biquad> _highPass = const [];
  List<Biquad> _lowPass = const [];
  double _filterRate = 0;
  _State _state = _State.idle;
  double? _lastAccS;
  double _dtMean = 0;
  double _stillSince = double.nan;
  Vec3 _restOmega = Vec3.zero;
  double _freeFallSince = double.nan;
  double _lastActiveS = 0;
  double _activeSinceS = 0;
  double _lastSaturationS = -1e9;
  final ListQueue<double> _gapTimes = ListQueue<double>();
  int _nextId = 1;
  int _currentId = 0;
  DetectionEvent? _provisional;

  Frame? latest;
  DetectionEvent? lastEvent;
  int framesProcessed = 0;
  int eventsDetected = 0;

  void addListener(void Function(DetectionEvent) listener) => _listeners.add(listener);
  void removeListener(void Function(DetectionEvent) listener) => _listeners.remove(listener);

  double get measuredRateHz => _dtMean > 0 ? 1 / _dtMean : 0;
  bool get inEvent => _state != _State.idle;
  double get baselineMedian => _baseline.median;
  double get baselineMad => _baseline.mad;

  QualityReport quality() {
    final now = _lastAccS ?? 0;
    while (_gapTimes.isNotEmpty && now - _gapTimes.first > 10) {
      _gapTimes.removeFirst();
    }
    final rateHz = measuredRateHz;
    final timing = switch (profile.timestampQuality) {
      TimestampQuality.hardware => 1.0,
      TimestampQuality.reconstructed => 0.9,
      TimestampQuality.received => 0.7,
    };
    return QualityReport(
      rateHz: rateHz,
      // 50 Hz is the lowest rate for which short impacts keep a usable Δv (§8.4).
      rate: math.min(1.0, rateHz / 50),
      gaps: (1 - _gapTimes.length * 0.1).clamp(0.2, 1.0),
      saturation: now - _lastSaturationS < 10 ? 0.6 : 1.0,
      orientation: math.exp(-math.pow(orientation.sigmaTheta / 0.35, 2)).toDouble().clamp(0.3, 1.0),
      gyro: orientation.hasGyro ? (orientation.biasEstimated ? 1.0 : 0.9) : 0.6,
      timing: timing,
    );
  }

  /// Current level: the last event for 30 s after it, then normal.
  DangerLevel get currentLevel {
    final e = lastEvent;
    final now = _lastAccS;
    if (e == null || now == null) return DangerLevel.normal;
    return now - e.features.endS < 30 ? e.level : DangerLevel.normal;
  }

  void ingest(MotionSample s) {
    switch (s.kind) {
      case SampleKind.gyro:
        orientation.onGyro(s.tNs, s.v);
        _alpha.add(s.tS, s.v - orientation.bias);
        if (profile.gyroRange != null &&
            math.max(s.v.x.abs(), math.max(s.v.y.abs(), s.v.z.abs())) >= 0.98 * profile.gyroRange!) {
          _lastSaturationS = s.tS;
        }
      case SampleKind.gps:
        _gps.add(GpsFix(s.tS, s.v.x, s.v.y));
        while (_gps.isNotEmpty && s.tS - _gps.first.tS > 60) {
          _gps.removeAt(0);
        }
      case SampleKind.acc:
        _onAcceleration(s);
    }
  }

  void _onAcceleration(MotionSample s) {
    final t = s.tS;
    final last = _lastAccS;
    var gap = (s.flags & MotionSample.flagGapBefore) != 0;
    if (last != null) {
      final dt = t - last;
      if (dt <= 0) return; // Out of order: dropped.
      if (dt < 0.2) _dtMean = _dtMean == 0 ? dt : _dtMean + (dt - _dtMean) * 0.02;
      if (_dtMean > 0 && dt > math.max(3 * _dtMean, 0.03)) gap = true;
    }
    _lastAccS = t;
    if (gap) {
      _gapTimes.add(t);
      _jerk.reset();
    }
    final f = s.v;
    var saturated = (s.flags & MotionSample.flagSaturated) != 0;
    final range = profile.accRange;
    if (range != null && math.max(f.x.abs(), math.max(f.y.abs(), f.z.abs())) >= 0.98 * range) {
      saturated = true;
    }
    if (saturated) _lastSaturationS = t;

    orientation.onAccelerometer(s.tNs, f);
    if (!orientation.initialized) return;
    final aW = orientation.dynamicWorld(f);
    _jerk.add(t, aW);
    final omega = orientation.omega;
    final fNorm = f.norm;

    _stillF.add(t, fNorm);
    _stillW.add(t, omega.norm);
    final still = _stillF.count >= 8 &&
        _stillF.spanS >= 0.4 &&
        _stillF.std < config.stillStd &&
        _stillW.max < config.stillOmega + (orientation.biasEstimated ? 0 : 0.05);
    if (still) {
      if (_stillSince.isNaN) {
        _stillSince = t;
        _restOmega = orientation.hasGyro ? omega + orientation.bias : Vec3.zero;
      }
      _restOmega = _restOmega + ((omega + orientation.bias) - _restOmega) * 0.05;
      if (t - _stillSince >= 1.0) orientation.learnAtRest(_restOmega, _stillF.mean);
    } else {
      _stillSince = double.nan;
    }

    // Free fall: small |f| within the lever-arm allowance ω²·r_max, and small
    // vertical specific force (gravity absent), report §9.1.
    final leverAllowance = omega.norm2 * profile.leverArmMax;
    final fVertical = orientation.q.rotate(f).z;
    final freeFall = fNorm < config.freeFallBase + leverAllowance &&
        fVertical.abs() < config.freeFallBase + 0.5 * leverAllowance;
    if (freeFall) {
      if (_freeFallSince.isNaN) _freeFallSince = t;
    } else {
      _freeFallSince = double.nan;
    }

    final aNorm = aW.norm;
    final rate = measuredRateHz;
    if (rate > 2 * config.vibrationCutoffHz && (rate - _filterRate).abs() > 0.1 * rate) {
      _filterRate = rate;
      _highPass = [for (var i = 0; i < 3; i++) Biquad.highPass(config.vibrationCutoffHz, rate)];
      _lowPass = [for (var i = 0; i < 3; i++) Biquad.lowPass(2, rate)];
    }
    final hp = _highPass.isEmpty
        ? 0.0
        : Vec3(_highPass[0].process(aW.x), _highPass[1].process(aW.y), _highPass[2].process(aW.z)).norm;
    final aLow = _lowPass.isEmpty
        ? aW
        : Vec3(_lowPass[0].process(aW.x), _lowPass[1].process(aW.y), _lowPass[2].process(aW.z));
    final z = _baseline.z(aNorm);

    final frame = Frame(
      tS: t,
      f: f,
      aW: aW,
      jerk: _jerk.slope,
      snap: _jerk.second,
      omega: omega,
      alpha: _alpha.slope,
      up: orientation.upInBody,
      still: still,
      freeFall: freeFall,
      zA: z,
      highPass: hp,
      aLow: aLow,
      fVertical: fVertical,
      saturated: saturated,
      gapBefore: gap,
    );
    latest = frame;
    framesProcessed++;
    // Winsorized update (cap at z = 3): sustained activity is learned within the
    // window, isolated events barely move the baseline (report §8.2).
    final cap = _baseline.median + 3 * 1.4826 * _baseline.mad;
    _baseline.add(t, math.min(aNorm, cap));
    _segment(frame);
  }

  bool _triggered(Frame fr) {
    final freeFallLong = !_freeFallSince.isNaN && fr.tS - _freeFallSince >= config.freeFallTriggerS;
    return (fr.zA > config.zOn && fr.aNorm > config.triggerMinA) ||
        freeFallLong ||
        fr.omegaNorm > config.triggerOmega;
  }

  bool _stillActive(Frame fr) =>
      (fr.zA > config.zOff && fr.aNorm > config.activeMinA) ||
      fr.freeFall ||
      fr.omegaNorm > config.triggerOmega * 0.6;

  void _segment(Frame fr) {
    switch (_state) {
      case _State.idle:
        if (!_baseline.ready || !_triggered(fr)) {
          _pre.add(fr);
          while (_pre.isNotEmpty && fr.tS - _pre.first.tS > config.preWindowS) {
            _pre.removeFirst();
          }
          return;
        }
        _state = _State.active;
        _currentId = _nextId++;
        _activeSinceS = fr.tS;
        _lastActiveS = fr.tS;
        // Include the free-fall that led to the trigger.
        final lead = _freeFallSince.isNaN ? 0.05 : fr.tS - _freeFallSince + 0.05;
        while (_pre.isNotEmpty && _pre.last.tS >= fr.tS - lead) {
          _event.insert(0, _pre.removeLast());
        }
        _event.add(fr);
      case _State.active:
        _event.add(fr);
        if (_stillActive(fr)) _lastActiveS = fr.tS;
        if (fr.tS - _lastActiveS >= config.endQuietS || fr.tS - _activeSinceS > config.maxActiveS) {
          _closeActive();
        }
      case _State.post:
        if (_triggered(fr)) {
          if (fr.tS - _activeSinceS < config.maxActiveS) {
            // New activity soon after: same episode.
            _event
              ..addAll(_post)
              ..add(fr);
            _post.clear();
            _state = _State.active;
            _lastActiveS = fr.tS;
            return;
          }
          // A potentially dangerous episode keeps its whole post phase: what
          // happens after the impact is the evidence the alarm needs (§28.4).
          if ((_provisional?.level.value ?? 0) < 3) {
            // Long episode: close it with the post phase seen so far and analyse
            // the new activity as a separate event (never buried in a tail).
            _finish();
            _segment(fr);
            return;
          }
        }
        _post.add(fr);
        if (fr.tS - _post.first.tS >= config.postWindowS) _finish();
    }
  }

  void _closeActive() {
    // Trailing quiet frames belong to the post phase.
    final cut = _event.lastIndexWhere((f) => f.tS <= _lastActiveS);
    final tail = cut >= 0 && cut < _event.length - 1 ? _event.sublist(cut + 1) : <Frame>[];
    if (tail.isNotEmpty) _event.removeRange(cut + 1, _event.length);
    _post
      ..clear()
      ..addAll(tail);
    _state = _State.post;
    _provisional = _emit(provisional: true);
  }

  void _finish() {
    _emit(provisional: false);
    _provisional = null;
    // The recent frames are the context (pre phase) of the next episode.
    final recent = [..._event, ..._post];
    _pre.clear();
    if (recent.isNotEmpty) {
      _pre.addAll(recent.where((f) => recent.last.tS - f.tS <= config.preWindowS));
    }
    _event.clear();
    _post.clear();
    _state = _State.idle;
  }

  DetectionEvent _emit({required bool provisional}) {
    final pre = _pre.toList();
    final features = extractor.extract(
      pre: pre,
      event: _event,
      post: provisional ? const [] : _post,
      gps: _gps,
      quality: quality().value,
      leverArm: profile.leverArmMax,
    );
    final classification = classifier.classify(features, provisional: provisional);
    final raw = [
      for (final f in [...pre, ..._event, if (!provisional) ..._post]) RawSample(f.tS, f.f, f.omega),
    ];
    final event = DetectionEvent(
      id: _currentId,
      provisional: provisional,
      features: features,
      classification: classification,
      raw: raw,
      source: profile,
    );
    if (!provisional) {
      eventsDetected++;
      lastEvent = event;
    } else {
      lastEvent ??= event;
    }
    for (final l in List.of(_listeners)) {
      l(event);
    }
    return event;
  }

  /// The pending provisional event, if an episode is still in its post phase.
  DetectionEvent? get pendingProvisional => _provisional;

  /// Forces the end of an open episode (end of the stream, tests).
  void flush() {
    if (_state == _State.active) _closeActive();
    if (_state == _State.post) _finish();
  }

  void reset() {
    _pre.clear();
    _event.clear();
    _post.clear();
    _state = _State.idle;
    _lastAccS = null;
    _jerk.reset();
    _alpha.reset();
    _stillF.clear();
    _stillW.clear();
    latest = null;
  }
}
