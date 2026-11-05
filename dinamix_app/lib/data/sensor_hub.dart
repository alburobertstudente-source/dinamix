import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../analysis/series_analysis.dart';
import '../ble/connection_manager.dart';
import '../domain/sensor_kind.dart';

/// Fixed-size circular storage for one data kind.
class ChannelBuffer {
  ChannelBuffer(this.channelCount, this.capacity)
      : _times = Float64List(capacity),
        _values = List.generate(channelCount, (_) => Float64List(capacity));

  final int channelCount;
  final int capacity;
  final Float64List _times;
  final List<Float64List> _values;
  int _head = 0;
  int length = 0;

  void add(int timeMs, List<double> values) {
    _times[_head] = timeMs.toDouble();
    for (var c = 0; c < channelCount; c++) {
      _values[c][_head] = c < values.length ? values[c] : double.nan;
    }
    _head = (_head + 1) % capacity;
    if (length < capacity) length++;
  }

  int _physical(int index) => (_head - length + index + capacity) % capacity;

  /// 0 is the oldest sample.
  double timeAt(int index) => _times[_physical(index)];
  double valueAt(int channel, int index) => _values[channel][_physical(index)];

  void clear() {
    _head = 0;
    length = 0;
  }
}

/// Live state for the UI. Reception and refresh are decoupled: BLE packets update
/// the buffers, widgets redraw only on [frame], at the chosen frequency.
class SensorHub implements ReadingSink {
  SensorHub({int refreshHz = 15, this.bufferCapacity = 6000}) {
    setRefreshHz(refreshHz);
  }

  final int bufferCapacity;
  final ValueNotifier<int> frame = ValueNotifier<int>(0);

  final Map<SensorKind, ChannelBuffer> _buffers = {};
  final Map<SensorKind, SensorReading> _latest = {};
  final Map<SensorKind, _RateMeter> _rates = {};
  final Map<String, ({int atMs, SeriesStats stats})> _statsCache = {};

  Timer? _timer;
  int _refreshHz = 15;
  bool _foreground = true;

  SensorReading? latest(SensorKind kind) => _latest[kind];
  ChannelBuffer? buffer(SensorKind kind) => _buffers[kind];

  /// Measured on the phone clock; it does not depend on the device tick unit.
  double rateHz(SensorKind kind) {
    final meter = _rates[kind];
    return meter == null ? 0 : meter.current(DateTime.now().millisecondsSinceEpoch);
  }

  /// A sensor is stale when nothing arrived for 5 seconds.
  bool isReceiving(SensorKind kind) {
    final last = _latest[kind];
    if (last == null) return false;
    return DateTime.now().millisecondsSinceEpoch - last.receivedAtMs < 5000;
  }

  @override
  void ingest(SensorReading reading) {
    final buffer = _buffers.putIfAbsent(
        reading.kind, () => ChannelBuffer(reading.kind.channels.length, bufferCapacity));
    buffer.add(reading.receivedAtMs, reading.values);
    _latest[reading.kind] = reading;
    _rates.putIfAbsent(reading.kind, _RateMeter.new).add(reading.receivedAtMs);
  }

  void setRefreshHz(int hz) {
    _refreshHz = hz;
    _restartTimer();
  }

  /// In background redraws stop, while reception and recording continue.
  void setForeground(bool foreground) {
    _foreground = foreground;
    _restartTimer();
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = null;
    if (!_foreground) return;
    _timer = Timer.periodic(
      Duration(milliseconds: (1000 / _refreshHz).round()),
      (_) => frame.value++,
    );
  }

  /// Statistics of the visible window, recomputed at most twice per second.
  SeriesStats windowStats(SensorKind kind, int channel, int windowMs) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final key = '${kind.id}/$channel/$windowMs';
    final cached = _statsCache[key];
    if (cached != null && now - cached.atMs < 500) return cached.stats;
    final stats = SeriesStats();
    final buffer = _buffers[kind];
    if (buffer != null) {
      final from = now - windowMs;
      for (var i = buffer.length - 1; i >= 0; i--) {
        final t = buffer.timeAt(i);
        if (t < from) break;
        stats.add(buffer.valueAt(channel, i));
      }
    }
    _statsCache[key] = (atMs: now, stats: stats);
    return stats;
  }

  void clear() {
    for (final b in _buffers.values) {
      b.clear();
    }
    _latest.clear();
    _rates.clear();
    _statsCache.clear();
    frame.value++;
  }

  void dispose() {
    _timer?.cancel();
    frame.dispose();
  }
}

class _RateMeter {
  static const int _bucketMs = 500;
  static const int _buckets = 6;
  final List<int> _counts = List.filled(_buckets, 0);
  int _currentBucket = 0;

  void add(int timeMs) {
    _advance(timeMs ~/ _bucketMs);
    _counts[_currentBucket % _buckets]++;
  }

  void _advance(int bucket) {
    if (bucket <= _currentBucket) return;
    final steps = math.min(bucket - _currentBucket, _buckets);
    for (var i = 1; i <= steps; i++) {
      _counts[(bucket - steps + i) % _buckets] = 0;
    }
    _currentBucket = bucket;
  }

  double current(int nowMs) {
    _advance(nowMs ~/ _bucketMs);
    var total = 0;
    // The running bucket is partial: it is left out of the average.
    for (var i = 1; i < _buckets; i++) {
      total += _counts[(_currentBucket - i) % _buckets];
    }
    return total / ((_buckets - 1) * _bucketMs / 1000.0);
  }
}
