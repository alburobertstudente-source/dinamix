import 'dart:math' as math;
import 'dart:typed_data';

/// Robust running baseline: median and MAD over the last [windowS] seconds,
/// recomputed at most every [refreshS] (report §8.2). Values during events are
/// not added by the caller, so events do not drag the baseline.
class RobustBaseline {
  RobustBaseline({
    this.windowS = 20,
    this.refreshS = 0.5,
    this.capacity = 4096,
    required this.initialMedian,
    required this.minMad,
  })  : _t = Float64List(capacity),
        _v = Float64List(capacity),
        median = initialMedian,
        mad = minMad;

  final double windowS;
  final double refreshS;
  final int capacity;
  final double initialMedian;

  /// Floor of the MAD: the noise floor of the sensor, so that z stays finite at rest.
  final double minMad;
  final Float64List _t;
  final Float64List _v;
  int _head = 0;
  int _length = 0;
  double _lastRefresh = -1e9;
  int _decimate = 0;

  double median;
  double mad;

  /// Ready after a few seconds of data.
  bool get ready => _length >= 40;

  void add(double tS, double value) {
    if (!value.isFinite) return;
    // Keep about 100 values per second regardless of the rate.
    _decimate++;
    if (_length > 0 && tS - _t[(_head - 1 + capacity) % capacity] < 0.01 && _decimate % 2 == 0) {
      return;
    }
    _t[_head] = tS;
    _v[_head] = value;
    _head = (_head + 1) % capacity;
    if (_length < capacity) _length++;
    if (tS - _lastRefresh >= refreshS) {
      _lastRefresh = tS;
      _recompute(tS);
    }
  }

  void _recompute(double tS) {
    final values = <double>[];
    for (var k = 0; k < _length; k++) {
      final i = (_head - 1 - k + capacity) % capacity;
      if (tS - _t[i] > windowS) break;
      values.add(_v[i]);
    }
    if (values.length < 10) return;
    values.sort();
    final m = _medianOfSorted(values);
    final deviations = values.map((v) => (v - m).abs()).toList()..sort();
    median = m;
    mad = math.max(minMad, _medianOfSorted(deviations));
  }

  static double _medianOfSorted(List<double> sorted) {
    final n = sorted.length;
    return n.isOdd ? sorted[n ~/ 2] : (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
  }

  /// Robust z-score: 1.4826 makes the MAD consistent with σ for a Gaussian.
  double z(double value) => (value - median) / (1.4826 * mad + 1e-9);
}

/// Windowed mean / variance with a time horizon, O(1) per sample.
class WindowStats {
  WindowStats(this.windowS, {this.capacity = 512})
      : _t = Float64List(capacity),
        _v = Float64List(capacity);

  final double windowS;
  final int capacity;
  final Float64List _t;
  final Float64List _v;
  int _head = 0;
  int _length = 0;
  double _sum = 0;
  double _sum2 = 0;

  int get count => _length;

  void add(double tS, double value) {
    if (_length == capacity) _dropOldest();
    _t[_head] = tS;
    _v[_head] = value;
    _head = (_head + 1) % capacity;
    _length++;
    _sum += value;
    _sum2 += value * value;
    while (_length > 0 && tS - _t[(_head - _length + capacity) % capacity] > windowS) {
      _dropOldest();
    }
  }

  void _dropOldest() {
    final i = (_head - _length + capacity) % capacity;
    _sum -= _v[i];
    _sum2 -= _v[i] * _v[i];
    _length--;
  }

  double get mean => _length == 0 ? double.nan : _sum / _length;

  double get variance {
    if (_length < 2) return double.nan;
    final m = _sum / _length;
    return math.max(0, _sum2 / _length - m * m);
  }

  double get std => math.sqrt(variance);

  double get max {
    var m = double.negativeInfinity;
    for (var k = 0; k < _length; k++) {
      final v = _v[(_head - 1 - k + capacity) % capacity];
      if (v > m) m = v;
    }
    return m;
  }

  /// Time span covered by the samples in the window.
  double get spanS => _length < 2
      ? 0
      : _t[(_head - 1 + capacity) % capacity] - _t[(_head - _length + capacity) % capacity];

  void clear() {
    _head = 0;
    _length = 0;
    _sum = 0;
    _sum2 = 0;
  }
}

/// Second-order Butterworth section (bilinear transform with pre-warping).
class Biquad {
  Biquad._(this.b0, this.b1, this.b2, this.a1, this.a2);

  factory Biquad.lowPass(double cutoffHz, double sampleHz) {
    final k = math.tan(math.pi * math.min(cutoffHz, 0.45 * sampleHz) / sampleHz);
    final norm = 1 / (1 + math.sqrt2 * k + k * k);
    final b0 = k * k * norm;
    return Biquad._(b0, 2 * b0, b0, 2 * (k * k - 1) * norm, (1 - math.sqrt2 * k + k * k) * norm);
  }

  factory Biquad.highPass(double cutoffHz, double sampleHz) {
    final k = math.tan(math.pi * math.min(cutoffHz, 0.45 * sampleHz) / sampleHz);
    final norm = 1 / (1 + math.sqrt2 * k + k * k);
    return Biquad._(norm, -2 * norm, norm, 2 * (k * k - 1) * norm, (1 - math.sqrt2 * k + k * k) * norm);
  }

  final double b0, b1, b2, a1, a2;
  double _x1 = 0, _x2 = 0, _y1 = 0, _y2 = 0;

  double process(double x) {
    final y = b0 * x + b1 * _x1 + b2 * _x2 - a1 * _y1 - a2 * _y2;
    _x2 = _x1;
    _x1 = x;
    _y2 = _y1;
    _y1 = y;
    return y;
  }

  void reset() {
    _x1 = _x2 = _y1 = _y2 = 0;
  }
}
