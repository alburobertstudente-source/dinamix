import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:sensors_plus/sensors_plus.dart';

import '../../core/app_logger.dart';
import '../../domain/sensor_kind.dart';
import '../../domain/units.dart';
import '../protocol/advertising.dart';
import 'ble_transport.dart';

class Vector3Sample {
  const Vector3Sample(this.x, this.y, this.z, {this.tUs});
  final double x;
  final double y;
  final double z;

  /// Hardware timestamp of the SensorEvent in µs (sensors_plus), when known.
  final int? tUs;
}

/// Raw motion sample in Android units with its hardware timestamp, for the
/// detection engine (m/s² or rad/s).
typedef PhoneMotionListener = void Function(bool gyro, int tNs, double x, double y, double z);

/// Motion sensors of the phone, in Android units: m/s², rad/s, µT, hPa.
abstract class PhoneSensorSource {
  Stream<Vector3Sample> accelerometer();
  Stream<Vector3Sample> gyroscope();
  Stream<Vector3Sample> magnetometer();
  Stream<double> barometer();
}

class DevicePhoneSensors implements PhoneSensorSource {
  DevicePhoneSensors({this.motionRateHz = 200});

  /// Requested rate: a hint for Android, the real one is measured (§2.2).
  int motionRateHz;
  static const Duration _slow = Duration(milliseconds: 100);
  static const Duration _ambient = Duration(milliseconds: 500);

  Duration get _fast => Duration(microseconds: (1e6 / motionRateHz).round());

  @override
  Stream<Vector3Sample> accelerometer() => accelerometerEventStream(samplingPeriod: _fast)
      .map((e) => Vector3Sample(e.x, e.y, e.z, tUs: e.timestamp.microsecondsSinceEpoch));

  @override
  Stream<Vector3Sample> gyroscope() => gyroscopeEventStream(samplingPeriod: _fast)
      .map((e) => Vector3Sample(e.x, e.y, e.z, tUs: e.timestamp.microsecondsSinceEpoch));

  @override
  Stream<Vector3Sample> magnetometer() =>
      magnetometerEventStream(samplingPeriod: _slow).map((e) => Vector3Sample(e.x, e.y, e.z));

  @override
  Stream<double> barometer() =>
      barometerEventStream(samplingPeriod: _ambient).map((e) => e.pressure);
}

/// Demo mode: real measurements from the phone, packed as BlueST packets so that
/// decoder, charts, recorder and export run the same code used with the SensorTile.
/// Everything is tagged [DataSource.phone].
class PhoneTransport implements BleTransport {
  PhoneTransport({PhoneSensorSource? sensors}) : _sensors = sensors ?? DevicePhoneSensors();

  static const String deviceId = 'TELEFONO';
  static const String deviceName = 'Questo telefono';
  static const String _service = '00000000-0001-11e1-9ab4-0002a5d5c51b';
  static const String _suffix = '-0001-11e1-ac36-0002a5d5c51b';
  static const int _maskAcc = 0x00800000;
  static const int _maskGyro = 0x00400000;
  static const int _maskMag = 0x00200000;
  static const int _maskPressure = 0x00100000;

  final PhoneSensorSource _sensors;

  /// Receives every motion sample at full rate (detection engine).
  PhoneMotionListener? motionListener;

  /// Rate of the BlueST packets for charts and recordings (decimated).
  static const double _forwardHz = 50;
  int _lastAccForwardUs = 0;
  int _lastGyroForwardUs = 0;
  final Stopwatch _fallbackClock = Stopwatch()..start();

  PhoneSensorSource get sensors => _sensors;

  int _timeUs(Vector3Sample s) => s.tUs ?? _fallbackClock.elapsedMicroseconds;

  bool _forward(int tUs, bool gyro) {
    final last = gyro ? _lastGyroForwardUs : _lastAccForwardUs;
    if (tUs - last < 1e6 / _forwardHz * 0.9 && tUs >= last) return false;
    if (gyro) {
      _lastGyroForwardUs = tUs;
    } else {
      _lastAccForwardUs = tUs;
    }
    return true;
  }
  final StreamController<LinkState> _link = StreamController<LinkState>.broadcast();
  final StreamController<List<BleScanResult>> _scan =
      StreamController<List<BleScanResult>>.broadcast();
  final StreamController<bool> _scanning = StreamController<bool>.broadcast();
  final Map<String, StreamController<Uint8List>> _notifiers = {};
  final List<StreamSubscription<Object?>> _subs = [];
  final Stopwatch _clock = Stopwatch();

  bool _connected = false;

  @override
  DataSource get dataSource => DataSource.phone;
  @override
  AdapterStatus get adapterStatusNow => AdapterStatus.on;
  @override
  Stream<AdapterStatus> get adapterStatus => Stream.value(AdapterStatus.on);
  @override
  Stream<List<BleScanResult>> get scanResults => _scan.stream;
  @override
  Stream<bool> get isScanning => _scanning.stream;
  @override
  Future<void> ensurePermissions() async {}
  @override
  Future<void> turnOnAdapter() async {}

  @override
  Future<void> startScan({Duration timeout = const Duration(seconds: 15)}) async {
    _scan.add(const [
      BleScanResult(
        id: deviceId,
        name: deviceName,
        rssi: 0,
        connectable: true,
        advertising:
            BlueStAdvertising(protocolVersion: 2, deviceId: 0xFF, firmwareId: 0xFF, isSleeping: false),
      ),
    ]);
  }

  @override
  Future<void> stopScan() async {}

  @override
  Future<void> connect(String deviceId, {required Duration timeout}) async {
    if (_connected) return;
    _connected = true;
    _clock
      ..reset()
      ..start();
    _subs
      ..add(_listen<Vector3Sample>('Accelerometro', _sensors.accelerometer(), _onAccelerometer))
      ..add(_listen<Vector3Sample>('Giroscopio', _sensors.gyroscope(), _onGyroscope))
      ..add(_listen<Vector3Sample>('Magnetometro', _sensors.magnetometer(), _onMagnetometer))
      ..add(_listen<double>('Barometro', _sensors.barometer(), _onBarometer));
  }

  /// A sensor missing from the phone stops its own stream only: the others go on.
  StreamSubscription<T> _listen<T>(String name, Stream<T> stream, void Function(T) onData) =>
      stream.listen(
        onData,
        onError: (Object e) => logger.w('Telefono', '$name non disponibile: $e'),
        cancelOnError: true,
      );

  void _onAccelerometer(Vector3Sample s) {
    final tUs = _timeUs(s);
    motionListener?.call(false, tUs * 1000, s.x, s.y, s.z);
    if (s.tUs != null && !_forward(tUs, false)) return;
    final toMg = 1000.0 / standardGravity;
    _emitTriple(_maskAcc, s.x * toMg, s.y * toMg, s.z * toMg);
  }

  void _onGyroscope(Vector3Sample s) {
    final tUs = _timeUs(s);
    motionListener?.call(true, tUs * 1000, s.x, s.y, s.z);
    if (s.tUs != null && !_forward(tUs, true)) return;
    // Tenths of dps on the wire, as in BlueST.
    final toTenthDps = 1800.0 / math.pi;
    _emitTriple(_maskGyro, s.x * toTenthDps, s.y * toTenthDps, s.z * toTenthDps);
  }

  void _onMagnetometer(Vector3Sample s) {
    // 1 µT = 10 mGa.
    _emitTriple(_maskMag, s.x * 10, s.y * 10, s.z * 10);
  }

  void _onBarometer(double hPa) {
    final data = _packet(_maskPressure, 4);
    if (data == null) return;
    data.setInt32(2, (hPa * 100).round(), Endian.little);
    _send(_maskPressure, data);
  }

  void _emitTriple(int mask, double x, double y, double z) {
    final data = _packet(mask, 6);
    if (data == null) return;
    data
      ..setInt16(2, _int16(x), Endian.little)
      ..setInt16(4, _int16(y), Endian.little)
      ..setInt16(6, _int16(z), Endian.little);
    _send(mask, data);
  }

  static int _int16(double v) => v.round().clamp(-32768, 32767);

  ByteData? _packet(int mask, int payload) {
    final controller = _notifiers[_uuid(mask)];
    if (controller == null || !controller.hasListener) return null;
    final data = ByteData(2 + payload);
    data.setUint16(0, (_clock.elapsedMilliseconds ~/ 10) & 0xFFFF, Endian.little);
    return data;
  }

  void _send(int mask, ByteData data) =>
      _notifiers[_uuid(mask)]?.add(data.buffer.asUint8List());

  static String _uuid(int mask) => '${mask.toRadixString(16).padLeft(8, '0')}$_suffix';

  BleCharInfo _char(int mask) =>
      BleCharInfo(serviceUuid: _service, uuid: _uuid(mask), canNotify: true);

  @override
  Future<void> disconnect(String deviceId) async {
    await _shutdown();
    _link.add(LinkState.disconnected);
  }

  Future<void> _shutdown() async {
    _connected = false;
    _clock.stop();
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
  }

  @override
  Stream<LinkState> linkState(String deviceId) => _link.stream;

  @override
  Future<List<BleServiceInfo>> discover(String deviceId) async => [
        BleServiceInfo(_service, [
          _char(_maskAcc),
          _char(_maskGyro),
          _char(_maskMag),
          _char(_maskPressure),
        ]),
      ];

  @override
  Future<int> currentMtu(String deviceId) async => 0;
  @override
  Future<void> setHighThroughput(String deviceId, bool enabled) async {}
  @override
  Future<void> createBond(String deviceId) async {}
  @override
  Future<int> readRssi(String deviceId) async => 0;

  @override
  Future<Stream<Uint8List>> subscribe(String deviceId, BleCharInfo characteristic) async =>
      _notifiers
          .putIfAbsent(characteristic.uuid, () => StreamController<Uint8List>.broadcast())
          .stream;

  @override
  Future<void> unsubscribe(String deviceId, BleCharInfo characteristic) async {}

  @override
  Future<void> write(String deviceId, BleCharInfo characteristic, List<int> value,
      {required bool withoutResponse}) async {}
}
