import 'dart:math' as math;

import '../ble/connection_manager.dart';
import '../domain/sensor_kind.dart';
import '../sensing/estimation/tick_clock.dart';
import '../sensing/math/vec3.dart';
import '../sensing/motion_sample.dart';

/// Normalizes BlueST readings (SensorTile, BLE simulator) into [MotionSample]
/// (report §25.4): mg → m/s², dps → rad/s, sample times reconstructed from the
/// 16-bit device counter (§25.5).
class BlueStMotionAdapter implements ReadingSink {
  BlueStMotionAdapter(this.onSample, {this.accept = _hardwareOrSimulated});

  final void Function(MotionSample sample) onSample;
  final bool Function(DataSource source) accept;

  /// One clock per data kind: accelerometer and gyroscope may come on different
  /// characteristics with their own counters.
  final Map<SensorKind, TickClock> _clocks = {};
  int packets = 0;

  static bool _hardwareOrSimulated(DataSource s) => s != DataSource.phone;

  TickClock? clockFor(SensorKind kind) => _clocks[kind];

  @override
  void ingest(SensorReading reading) {
    if (!accept(reading.source)) return;
    final kind = reading.kind;
    if (kind != SensorKind.accelerometer && kind != SensorKind.gyroscope) return;
    final v = reading.values;
    if (v.length < 3 || v.any((x) => x.isNaN)) return;
    final clock = _clocks.putIfAbsent(kind, TickClock.new);
    final tS = clock.add(reading.deviceTicks & 0xFFFF, reading.receivedAtMs / 1000.0);
    final tNs = (tS * 1e9).round();
    packets++;
    if (kind == SensorKind.accelerometer) {
      const k = g0 / 1000;
      onSample(MotionSample(SampleKind.acc, tNs, Vec3(v[0] * k, v[1] * k, v[2] * k)));
    } else {
      const k = math.pi / 180;
      onSample(MotionSample(SampleKind.gyro, tNs, Vec3(v[0] * k, v[1] * k, v[2] * k)));
    }
  }

  void reset() {
    for (final c in _clocks.values) {
      c.reset();
    }
    _clocks.clear();
    packets = 0;
  }
}
