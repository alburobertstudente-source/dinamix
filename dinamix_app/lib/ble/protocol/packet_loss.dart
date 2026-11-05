/// Estimates lost packets from the 16-bit BlueST timestamp.
///
/// The tick unit depends on the firmware, so the expected interval is learned
/// as the median of recent deltas. The result is an estimate, not a count.
class PacketLossEstimator {
  static const int _window = 32;
  static const int _minimumDeltas = 8;
  static const double _gapFactor = 1.5;

  final List<int> _deltas = [];
  int? _last;

  int received = 0;
  int estimatedLost = 0;

  void add(int ticks) {
    received++;
    final last = _last;
    _last = ticks;
    if (last == null) return;
    final delta = (ticks - last) & 0xFFFF;
    // Zero: same timestamp. Above half range: out of order or counter reset.
    if (delta == 0 || delta > 0x7FFF) return;
    if (_deltas.length >= _minimumDeltas) {
      final expected = _median();
      if (expected > 0 && delta > expected * _gapFactor) {
        estimatedLost += (delta / expected).round() - 1;
        return;
      }
    }
    _deltas.add(delta);
    if (_deltas.length > _window) _deltas.removeAt(0);
  }

  double get lossRatio {
    final total = received + estimatedLost;
    return total == 0 ? 0 : estimatedLost / total;
  }

  double _median() {
    final sorted = List<int>.of(_deltas)..sort();
    return sorted[sorted.length ~/ 2].toDouble();
  }

  void reset() {
    _deltas.clear();
    _last = null;
    received = 0;
    estimatedLost = 0;
  }
}
