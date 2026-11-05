import 'dart:math' as math;

import '../data/session_store.dart';
import '../domain/sensor_kind.dart';

/// Streaming statistics (Welford). NaN values are skipped.
class SeriesStats {
  int count = 0;
  double min = double.nan;
  double max = double.nan;
  double _mean = 0;
  double _m2 = 0;
  double _sumSquares = 0;
  double _previous = double.nan;
  double _sumAbsDelta = 0;
  double maxAbsDelta = double.nan;

  void add(double value) {
    if (value.isNaN) return;
    if (!_previous.isNaN) {
      final delta = (value - _previous).abs();
      _sumAbsDelta += delta;
      if (maxAbsDelta.isNaN || delta > maxAbsDelta) maxAbsDelta = delta;
    }
    _previous = value;
    count++;
    if (min.isNaN || value < min) min = value;
    if (max.isNaN || value > max) max = value;
    final diff = value - _mean;
    _mean += diff / count;
    _m2 += diff * (value - _mean);
    _sumSquares += value * value;
  }

  double get mean => count == 0 ? double.nan : _mean;

  /// Sample standard deviation.
  double get stdDev => count < 2 ? double.nan : math.sqrt(_m2 / (count - 1));
  double get rms => count == 0 ? double.nan : math.sqrt(_sumSquares / count);
  double get peakToPeak => count == 0 ? double.nan : max - min;

  /// Mean change between consecutive samples.
  double get meanAbsDelta => count < 2 ? double.nan : _sumAbsDelta / (count - 1);
}

/// Min/max reduction to [binCount] columns: spikes stay visible at any zoom level.
class MinMaxBins {
  MinMaxBins(this.startMs, this.endMs, this.binCount)
      : mins = List<double>.filled(binCount, double.nan),
        maxs = List<double>.filled(binCount, double.nan);

  final int startMs;
  final int endMs;
  final int binCount;
  final List<double> mins;
  final List<double> maxs;

  void add(int timeMs, double value) {
    if (value.isNaN) return;
    final span = math.max(1, endMs - startMs);
    final bin = (((timeMs - startMs) / span) * binCount).floor().clamp(0, binCount - 1);
    if (mins[bin].isNaN || value < mins[bin]) mins[bin] = value;
    if (maxs[bin].isNaN || value > maxs[bin]) maxs[bin] = value;
  }
}

/// Counts peaks of a signal above a threshold, with a refractory time to avoid
/// counting one shock many times. Exploratory: not a certified fall detection.
class PeakDetector {
  PeakDetector({required this.threshold, this.refractoryMs = 200});

  final double threshold;
  final int refractoryMs;
  final List<({int atMs, double value})> peaks = [];

  void add(int timeMs, double value) {
    if (value.isNaN || value < threshold) return;
    if (peaks.isNotEmpty && timeMs - peaks.last.atMs < refractoryMs) {
      if (value > peaks.last.value) {
        peaks[peaks.length - 1] = (atMs: peaks.last.atMs, value: value);
      }
      return;
    }
    peaks.add((atMs: timeMs, value: value));
  }
}

class ChannelAnalysis {
  ChannelAnalysis(this.kind, this.channel, this.label, this.unit, this.bins);

  final SensorKind kind;

  /// Null for the derived acceleration magnitude.
  final int? channel;
  final String label;
  final String unit;
  final SeriesStats stats = SeriesStats();
  final MinMaxBins bins;
}

class KindAnalysis {
  KindAnalysis(this.kind, this.channels, this.peaks);

  final SensorKind kind;
  final List<ChannelAnalysis> channels;

  /// Accelerometer only.
  final PeakDetector? peaks;
  int samples = 0;
}

/// Magnitude of a three-axis reading.
double vectorMagnitude(List<double> v) => math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);

/// Reads a whole kind from the database in pages, without loading it in memory.
Future<KindAnalysis> analyzeKind({
  required SessionStore store,
  required int sessionId,
  required SensorKind kind,
  required int startMs,
  required int endMs,
  int binCount = 400,
  double impactThresholdMg = 4000,
}) async {
  final isAcc = kind == SensorKind.accelerometer;
  final channels = <ChannelAnalysis>[
    for (var i = 0; i < kind.channels.length; i++)
      ChannelAnalysis(kind, i, kind.channels[i].label, kind.channels[i].unit,
          MinMaxBins(startMs, endMs, binCount)),
    if (isAcc)
      ChannelAnalysis(kind, null, 'Modulo', 'mg', MinMaxBins(startMs, endMs, binCount)),
  ];
  final result = KindAnalysis(
      kind, channels, isAcc ? PeakDetector(threshold: impactThresholdMg) : null);

  var after = 0;
  while (true) {
    final page = await store.pageSamples(sessionId, kind: kind, afterRowId: after);
    if (page.isEmpty) break;
    for (final s in page) {
      result.samples++;
      for (var i = 0; i < kind.channels.length && i < s.values.length; i++) {
        channels[i].stats.add(s.values[i]);
        channels[i].bins.add(s.receivedAtMs, s.values[i]);
      }
      if (isAcc) {
        final magnitude = vectorMagnitude(s.values);
        channels.last.stats.add(magnitude);
        channels.last.bins.add(s.receivedAtMs, magnitude);
        result.peaks!.add(s.receivedAtMs, magnitude);
      }
    }
    after = page.last.rowId;
  }
  return result;
}
