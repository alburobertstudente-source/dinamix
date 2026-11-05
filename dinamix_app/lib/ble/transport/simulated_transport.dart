import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../domain/sensor_kind.dart';
import '../protocol/advertising.dart';
import 'ble_transport.dart';

/// Development-only stand-in for the radio, enabled from the settings. It encodes
/// real BlueST packets, so decoder and recorder run the same path as with the
/// hardware. All its readings are tagged [DataSource.simulated] by the manager.
class SimulatedTransport implements BleTransport {
  SimulatedTransport({math.Random? random}) : _random = random ?? math.Random(42);

  static const String deviceId = 'SIMULATORE';
  static const String _service = '00000000-0001-11e1-9ab4-0002a5d5c51b';
  static const String _suffix = '-0001-11e1-ac36-0002a5d5c51b';
  static const String _extendedSuffix = '-0002-11e1-ac36-0002a5d5c51b';

  final math.Random _random;
  final StreamController<LinkState> _link = StreamController<LinkState>.broadcast();
  final StreamController<List<BleScanResult>> _scan =
      StreamController<List<BleScanResult>>.broadcast();
  final StreamController<bool> _scanning = StreamController<bool>.broadcast();
  final Map<String, StreamController<Uint8List>> _notifiers = {};
  final List<Timer> _timers = [];

  bool _connected = false;
  int _elapsedMs = 0;

  @override
  DataSource get dataSource => DataSource.simulated;

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
    _scanning.add(true);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    _scan.add(const [
      BleScanResult(
        id: deviceId,
        name: 'Simulatore DinamiX',
        rssi: -48,
        connectable: true,
        // Device ID 0xFF: never recognized as a real SensorTile.box PRO.
        advertising: BlueStAdvertising(
            protocolVersion: 2, deviceId: 0xFF, firmwareId: 0xFF, isSleeping: false),
      ),
    ]);
    _scanning.add(false);
  }

  @override
  Future<void> stopScan() async => _scanning.add(false);

  @override
  Future<void> connect(String deviceId, {required Duration timeout}) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    _connected = true;
    _elapsedMs = 0;
    _startStreams();
  }

  @override
  Future<void> disconnect(String deviceId) async {
    _shutdown();
    _link.add(LinkState.disconnected);
  }

  /// Cuts the link as an out-of-range device would, to exercise reconnection.
  void simulateLinkLoss() {
    _shutdown();
    _link.add(LinkState.disconnected);
  }

  void _shutdown() {
    _connected = false;
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
  }

  @override
  Stream<LinkState> linkState(String deviceId) async* {
    yield _connected ? LinkState.connected : LinkState.disconnected;
    yield* _link.stream;
  }

  BleCharInfo _char(int id, {bool extended = false}) => BleCharInfo(
        serviceUuid: _service,
        uuid: '${id.toRadixString(16).padLeft(8, '0')}${extended ? _extendedSuffix : _suffix}',
        canNotify: true,
        canRead: true,
      );

  @override
  Future<List<BleServiceInfo>> discover(String deviceId) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    return [
      BleServiceInfo(_service, [
        _char(0x00E00000),
        _char(0x00100000),
        _char(0x00080000),
        _char(0x00010000),
        _char(0x00020000),
        _char(0x00000100),
        _char(0x00000010),
        _char(0x00000001),
        _char(0x16, extended: true),
      ]),
    ];
  }

  @override
  Future<int> currentMtu(String deviceId) async => 247;

  @override
  Future<void> setHighThroughput(String deviceId, bool enabled) async {}

  @override
  Future<void> createBond(String deviceId) async {}

  @override
  Future<int> readRssi(String deviceId) async => -48 - _random.nextInt(8);

  @override
  Future<Stream<Uint8List>> subscribe(String deviceId, BleCharInfo characteristic) async {
    final controller = _notifiers.putIfAbsent(
        characteristic.uuid, () => StreamController<Uint8List>.broadcast());
    return controller.stream;
  }

  @override
  Future<void> unsubscribe(String deviceId, BleCharInfo characteristic) async {}

  @override
  Future<void> write(String deviceId, BleCharInfo characteristic, List<int> value,
      {required bool withoutResponse}) async {}

  void _startStreams() {
    _timers
      ..add(Timer.periodic(const Duration(milliseconds: 20), (_) => _tickInertial()))
      ..add(Timer.periodic(const Duration(milliseconds: 30), (_) => _tickFusion()))
      ..add(Timer.periodic(const Duration(milliseconds: 500), (_) => _tickEnvironment()))
      ..add(Timer.periodic(const Duration(seconds: 2), (_) => _tickSlow()));
  }

  void _emit(int id, void Function(ByteData) fill, int payload, {bool extended = false}) {
    final uuid = '${id.toRadixString(16).padLeft(8, '0')}${extended ? _extendedSuffix : _suffix}';
    final controller = _notifiers[uuid];
    if (controller == null || !controller.hasListener) return;
    final data = ByteData(2 + payload);
    data.setUint16(0, (_elapsedMs ~/ 10) & 0xFFFF, Endian.little);
    fill(data);
    controller.add(data.buffer.asUint8List());
  }

  double _noise(double amplitude) => (_random.nextDouble() - 0.5) * 2 * amplitude;

  void _tickInertial() {
    _elapsedMs += 20;
    final t = _elapsedMs / 1000.0;
    // Synthetic ride with a short spike every 12 s, useful to test the charts.
    final spike = _elapsedMs % 12000 < 60 ? 9000.0 : 0.0;
    _emit(0x00E00000, (d) {
      void put(int offset, double v) =>
          d.setInt16(offset, v.round().clamp(-32768, 32767), Endian.little);
      put(2, 120 * math.sin(t * 2.1) + _noise(25) + spike);
      put(4, 90 * math.cos(t * 1.3) + _noise(25) - spike * 0.6);
      put(6, 1000 + 60 * math.sin(t * 0.9) + _noise(25) + spike * 0.4);
      put(8, (45 * math.sin(t * 1.7) + _noise(3)) * 10);
      put(10, (30 * math.cos(t * 1.1) + _noise(3)) * 10);
      put(12, (20 * math.sin(t * 0.5) + _noise(3)) * 10);
      put(14, 230 * math.cos(t * 0.2) + _noise(4));
      put(16, 230 * math.sin(t * 0.2) + _noise(4));
      put(18, -410 + _noise(4));
    }, 18);
  }

  void _tickFusion() {
    final t = _elapsedMs / 1000.0;
    _emit(0x00000100, (d) {
      for (var i = 0; i < 3; i++) {
        final phase = t + i * 0.01;
        d.setInt16(2 + i * 6, (math.sin(phase * 0.4) * 3000).round(), Endian.little);
        d.setInt16(4 + i * 6, (math.cos(phase * 0.3) * 2000).round(), Endian.little);
        d.setInt16(6 + i * 6, (math.sin(phase * 0.2) * 1000).round(), Endian.little);
      }
    }, 18);
  }

  void _tickEnvironment() {
    final t = _elapsedMs / 1000.0;
    _emit(0x00100000, (d) {
      d.setInt32(2, (101325 + 40 * math.sin(t * 0.05) + _noise(5)).round(), Endian.little);
    }, 4);
    _emit(0x00080000, (d) {
      d.setUint16(2, (480 + 15 * math.sin(t * 0.04) + _noise(1)).round(), Endian.little);
    }, 2);
    _emit(0x00010000, (d) {
      d.setInt16(2, (224 + 6 * math.sin(t * 0.03) + _noise(1)).round(), Endian.little);
    }, 2);
    _emit(0x16, (d) {
      d.setInt32(2, (200 * math.sin(t) + _noise(40)).round(), Endian.little);
    }, 4, extended: true);
  }

  void _tickSlow() {
    final minutes = _elapsedMs / 60000.0;
    _emit(0x00020000, (d) {
      d.setInt16(2, ((87 - minutes * 0.2).clamp(0, 100) * 10).round(), Endian.little);
      d.setInt16(4, 3910, Endian.little);
      d.setInt16(6, -35, Endian.little);
      d.setUint8(8, 0x01);
    }, 7);
    _emit(0x00000010, (d) {
      d.setUint8(2, 2 + ((_elapsedMs ~/ 20000) % 4));
    }, 1);
    _emit(0x00000001, (d) {
      d.setUint32(2, _elapsedMs ~/ 600, Endian.little);
      d.setUint16(6, 100, Endian.little);
    }, 6);
  }
}
