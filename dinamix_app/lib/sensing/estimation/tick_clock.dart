import 'dart:math' as math;

/// Sample-time reconstruction for BLE packets (report §25.5).
///
/// Each packet carries a 16-bit device counter of unknown unit and is received
/// at r_i = a + b·k_i + L_i with latency L_i ≥ 0. The correct line is the lower
/// envelope of the points (k_i, r_i): it is found on the lower convex hull, on
/// the edge that contains the mean abscissa, which is the solution of
/// min Σ(r_i − a − b·k_i) subject to r_i ≥ a + b·k_i.
class TickClock {
  TickClock({this.window = 256, this.refitEvery = 8});

  final int window;
  final int refitEvery;

  final List<double> _k = [];
  final List<double> _r = [];
  int? _lastRaw;
  double? _lastReceivedS;
  double _unwrapped = 0;
  int _sinceFit = 0;

  /// Fitted parameters: time = a + b·k (seconds).
  double a = 0;
  double b = 0;
  bool fitted = false;

  /// Residual dispersion of the receive times above the fitted line (s).
  double sigmaS = double.nan;

  /// Estimated counter period (s per tick).
  double get tickPeriodS => b;

  /// Counter value of the last packet after unwrapping.
  double get lastTicks => _unwrapped;

  /// Returns the reconstructed sample time in seconds for a packet.
  double add(int raw16, double receivedS) {
    final lastRaw = _lastRaw;
    if (lastRaw == null) {
      _unwrapped = raw16.toDouble();
    } else {
      final delta = (raw16 - lastRaw) & 0xFFFF;
      var wraps = 0;
      final lastR = _lastReceivedS;
      if (fitted && b > 0 && lastR != null) {
        // Long pauses: count whole wraps from the elapsed receive time.
        wraps = (((receivedS - lastR) / b - delta) / 65536).round();
        if (wraps < 0) wraps = 0;
      }
      if (delta > 0x7FFF && wraps == 0 && (!fitted || (receivedS - (lastR ?? receivedS)) < 0.5)) {
        // Out of order or counter reset: re-anchor on receive time.
        return receivedS;
      }
      _unwrapped += delta + wraps * 65536;
    }
    _lastRaw = raw16;
    _lastReceivedS = receivedS;
    _k.add(_unwrapped);
    _r.add(receivedS);
    if (_k.length > window) {
      _k.removeAt(0);
      _r.removeAt(0);
    }
    if (++_sinceFit >= refitEvery || !fitted) {
      _sinceFit = 0;
      _fit();
    }
    return fitted ? a + b * _unwrapped : receivedS;
  }

  double _cross(int o, int p, int q) =>
      (_k[p] - _k[o]) * (_r[q] - _r[o]) - (_r[p] - _r[o]) * (_k[q] - _k[o]);

  void _fit() {
    final n = _k.length;
    if (n < 8 || _k.last - _k.first <= 0) return;
    // Lower hull (Andrew's monotone chain); k is already increasing.
    final hull = <int>[];
    for (var i = 0; i < n; i++) {
      while (hull.length >= 2 && _cross(hull[hull.length - 2], hull.last, i) <= 0) {
        hull.removeLast();
      }
      hull.add(i);
    }
    final kMean = _k.reduce((x, y) => x + y) / n;
    for (var h = 0; h + 1 < hull.length; h++) {
      final i = hull[h], j = hull[h + 1];
      if (_k[i] <= kMean && kMean <= _k[j] && _k[j] > _k[i]) {
        final slope = (_r[j] - _r[i]) / (_k[j] - _k[i]);
        if (slope <= 0) return;
        b = slope;
        a = _r[i] - slope * _k[i];
        fitted = true;
        var sum = 0.0;
        for (var m = 0; m < n; m++) {
          final res = _r[m] - (a + b * _k[m]);
          sum += res * res;
        }
        sigmaS = math.sqrt(sum / n);
        return;
      }
    }
  }

  void reset() {
    _k.clear();
    _r.clear();
    _lastRaw = null;
    _lastReceivedS = null;
    _unwrapped = 0;
    fitted = false;
  }
}
