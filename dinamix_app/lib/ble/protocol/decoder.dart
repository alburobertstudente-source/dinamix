import 'dart:math' as math;
import 'dart:typed_data';

import '../../domain/sensor_kind.dart';
import 'bluest_uuid.dart';

class DecodeException implements Exception {
  const DecodeException(this.message);
  final String message;

  @override
  String toString() => 'DecodeException: $message';
}

class DecodeResult {
  const DecodeResult(this.ticks, this.readings, {this.undecodedMask = 0});

  final int ticks;
  final List<SensorReading> readings;

  /// Basic feature with unknown length: decoding stops there, because the
  /// position of the data that follows cannot be computed.
  final int undecodedMask;
}

/// Decodes BlueST notifications: 2 byte little-endian timestamp followed by the
/// data of each feature, most significant mask bit first.
/// Layouts, scales and units from the feature classes of ST BlueSTSDK_Android.
class BlueStDecoder {
  BlueStDecoder._();

  static const int headerLength = 2;

  /// ST SDK: QUATERNION_DELAY_MS in MemsSensorFusionCompat.
  static const int quaternionPacketMs = 30;

  static DecodeResult decode({
    required BlueStUuid uuid,
    required Uint8List data,
    required int receivedAtMs,
    required DataSource source,
  }) {
    if (data.length < headerLength) {
      throw DecodeException('Pacchetto di ${data.length} byte senza timestamp');
    }
    final cursor = _Cursor(data, receivedAtMs, source);
    final out = <SensorReading>[];
    switch (uuid.type) {
      case BlueStCharType.basic:
        for (final mask in uuid.basicMasks) {
          if (!_decodeBasic(mask, cursor, out)) {
            return DecodeResult(cursor.ticks, out, undecodedMask: mask);
          }
        }
      case BlueStCharType.extended:
        _decodeExtended(uuid.id, cursor, out);
      default:
        break;
    }
    return DecodeResult(cursor.ticks, out);
  }

  static bool _decodeBasic(int mask, _Cursor c, List<SensorReading> out) {
    switch (mask) {
      case 0x00800000:
        c.require(6, 'Accelerometer');
        out.add(c.reading(SensorKind.accelerometer,
            [c.int16(), c.int16(), c.int16()].map((v) => v.toDouble()).toList()));
      case 0x00400000:
        c.require(6, 'Gyroscope');
        out.add(c.reading(SensorKind.gyroscope,
            [c.int16() / 10.0, c.int16() / 10.0, c.int16() / 10.0]));
      case 0x00200000:
        c.require(6, 'Magnetometer');
        out.add(c.reading(SensorKind.magnetometer,
            [c.int16().toDouble(), c.int16().toDouble(), c.int16().toDouble()]));
      case 0x00100000:
        c.require(4, 'Pressure');
        out.add(c.reading(SensorKind.pressure, [c.int32() / 100.0]));
      case 0x00080000:
        c.require(2, 'Humidity');
        out.add(c.reading(SensorKind.humidity, [c.uint16() / 10.0]));
      case 0x00040000:
        c.require(2, 'Temperature');
        out.add(c.reading(SensorKind.temperature2, [c.int16() / 10.0]));
      case 0x00010000:
        c.require(2, 'Temperature');
        out.add(c.reading(SensorKind.temperature, [c.int16() / 10.0]));
      case 0x00020000:
        out.add(_battery(c));
      case 0x00000100:
        _fusionCompact(c, out);
      case 0x00000080:
        out.add(_fusion(c));
      case 0x00000040:
        c.require(2, 'Compass');
        out.add(c.reading(SensorKind.compass, [c.uint16() / 100.0]));
      case 0x00000010:
        out.add(_activity(c));
      case 0x00000001:
        c.require(6, 'Pedometer');
        out.add(c.reading(
            SensorKind.pedometer, [c.uint32().toDouble(), c.uint16().toDouble()]));
      case 0x04000000:
        out.add(_micLevel(c));
      case 0x20000000:
        c.require(1, 'Switch');
        out.add(c.reading(SensorKind.switchState, [c.uint8().toDouble()]));
      default:
        return false;
    }
    return true;
  }

  static void _decodeExtended(int id, _Cursor c, List<SensorReading> out) {
    switch (id) {
      case 0x0D:
        c.require(12, 'Euler Angle');
        out.add(c.reading(SensorKind.euler, [c.float32(), c.float32(), c.float32()]));
      case 0x16:
        out.add(_qvar(c));
      case 0x1D:
        c.require(4, 'Event Counter');
        out.add(c.reading(SensorKind.eventCounter, [c.uint32().toDouble()]));
      default:
        break;
    }
  }

  static SensorReading _battery(_Cursor c) {
    c.require(7, 'Battery');
    final level = (c.int16() / 10.0).clamp(0.0, 100.0);
    final voltage = c.int16() / 1000.0;
    final rawCurrent = c.int16();
    final status = c.uint8();
    final highResolution = status & 0x80 != 0;
    final current = rawCurrent == -32768
        ? double.nan
        : (highResolution ? rawCurrent * 0.1 : rawCurrent.toDouble());
    return c.reading(SensorKind.battery,
        [level.toDouble(), voltage, current, (status & 0x7F).toDouble()]);
  }

  static void _fusionCompact(_Cursor c, List<SensorReading> out) {
    final count = c.remaining ~/ 6;
    if (count == 0) {
      throw const DecodeException('MEMS Sensor Fusion Compact: dati insufficienti');
    }
    final stepMs = quaternionPacketMs ~/ count;
    for (var i = 0; i < count; i++) {
      final qi = c.int16() / 10000.0;
      final qj = c.int16() / 10000.0;
      final qk = c.int16() / 10000.0;
      out.add(c.reading(SensorKind.quaternion, [qi, qj, qk, _scalarPart(qi, qj, qk)],
          offsetMs: i * stepMs));
    }
  }

  static SensorReading _fusion(_Cursor c) {
    c.require(12, 'MEMS Sensor Fusion');
    final qi = c.float32();
    final qj = c.float32();
    final qk = c.float32();
    final qs = c.remaining >= 4 ? c.float32() : _scalarPart(qi, qj, qk);
    return c.reading(SensorKind.quaternion, [qi, qj, qk, qs]);
  }

  static double _scalarPart(double qi, double qj, double qk) {
    final t = 1 - (qi * qi + qj * qj + qk * qk);
    return t > 0 ? math.sqrt(t) : 0.0;
  }

  static SensorReading _activity(_Cursor c) {
    c.require(1, 'Activity');
    final code = c.uint8() & 0x0F;
    if (c.remaining >= 1) c.uint8(); // Optional algorithm byte.
    return c.reading(SensorKind.activity, [code.toDouble()]);
  }

  static SensorReading _micLevel(_Cursor c) {
    c.require(1, 'Mic Level');
    final level = c.uint8().toDouble();
    // The board has one microphone: further levels, if any, are skipped.
    c.skip(c.remaining);
    return c.reading(SensorKind.micLevel, [level]);
  }

  static SensorReading _qvar(_Cursor c) {
    c.require(4, 'QVAR');
    final qvar = c.int32().toDouble();
    final flag = c.remaining >= 1 ? c.uint8().toDouble() : double.nan;
    final dqvar = c.remaining >= 4 ? c.int32().toDouble() : double.nan;
    final param = c.remaining == 4 ? c.int32().toDouble() : double.nan;
    return c.reading(SensorKind.qvar, [qvar, flag, dqvar, param]);
  }
}

class _Cursor {
  _Cursor(Uint8List data, this.receivedAtMs, this.source)
      : _bytes = ByteData.sublistView(data),
        _length = data.length,
        ticks = ByteData.sublistView(data).getUint16(0, Endian.little);

  final ByteData _bytes;
  final int _length;
  final int receivedAtMs;
  final DataSource source;
  final int ticks;
  int _offset = BlueStDecoder.headerLength;

  int get remaining => _length - _offset;

  void require(int count, String feature) {
    if (remaining < count) {
      throw DecodeException(
          '$feature: servono $count byte, disponibili $remaining');
    }
  }

  void skip(int count) => _offset += count;

  int uint8() => _bytes.getUint8(_offset++);

  int int16() {
    final v = _bytes.getInt16(_offset, Endian.little);
    _offset += 2;
    return v;
  }

  int uint16() {
    final v = _bytes.getUint16(_offset, Endian.little);
    _offset += 2;
    return v;
  }

  int int32() {
    final v = _bytes.getInt32(_offset, Endian.little);
    _offset += 4;
    return v;
  }

  int uint32() {
    final v = _bytes.getUint32(_offset, Endian.little);
    _offset += 4;
    return v;
  }

  double float32() {
    final v = _bytes.getFloat32(_offset, Endian.little);
    _offset += 4;
    return v;
  }

  SensorReading reading(SensorKind kind, List<double> values, {int offsetMs = 0}) =>
      SensorReading(
        kind: kind,
        deviceTicks: ticks,
        receivedAtMs: receivedAtMs + offsetMs,
        values: values,
        source: source,
      );
}
