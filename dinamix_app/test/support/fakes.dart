import 'dart:async';
import 'dart:typed_data';

import 'package:dinamix/ble/connection_manager.dart';
import 'package:dinamix/ble/transport/ble_transport.dart';
import 'package:dinamix/data/session_store.dart';
import 'package:dinamix/domain/sensor_kind.dart';
import 'package:dinamix/domain/session.dart';

const String accCharUuid = '00800000-0001-11e1-ac36-0002a5d5c51b';
const String serviceUuid = '00000000-0001-11e1-9ab4-0002a5d5c51b';

/// Scriptable radio for the connection tests.
class FakeTransport implements BleTransport {
  final StreamController<LinkState> link = StreamController<LinkState>.broadcast();
  final StreamController<Uint8List> notifications = StreamController<Uint8List>.broadcast();

  int connectCalls = 0;
  int disconnectCalls = 0;
  int bondCalls = 0;
  int subscribeCalls = 0;
  Object? connectError;
  Object? discoverError;
  int subscribeFailures = 0;
  bool hasNotifyCharacteristic = true;

  @override
  DataSource get dataSource => DataSource.hardware;
  @override
  AdapterStatus get adapterStatusNow => AdapterStatus.on;
  @override
  Stream<AdapterStatus> get adapterStatus => const Stream.empty();
  @override
  Stream<List<BleScanResult>> get scanResults => const Stream.empty();
  @override
  Stream<bool> get isScanning => const Stream.empty();
  @override
  Future<void> ensurePermissions() async {}
  @override
  Future<void> turnOnAdapter() async {}
  @override
  Future<void> startScan({Duration timeout = Duration.zero}) async {}
  @override
  Future<void> stopScan() async {}

  @override
  Future<void> connect(String deviceId, {required Duration timeout}) async {
    connectCalls++;
    final error = connectError;
    if (error != null) throw error;
  }

  @override
  Future<void> disconnect(String deviceId) async => disconnectCalls++;

  @override
  Stream<LinkState> linkState(String deviceId) => link.stream;

  @override
  Future<List<BleServiceInfo>> discover(String deviceId) async {
    final error = discoverError;
    if (error != null) throw error;
    return [
      BleServiceInfo(serviceUuid, [
        BleCharInfo(
            serviceUuid: serviceUuid, uuid: accCharUuid, canNotify: hasNotifyCharacteristic),
      ]),
    ];
  }

  @override
  Future<int> currentMtu(String deviceId) async => 247;
  @override
  Future<void> setHighThroughput(String deviceId, bool enabled) async {}
  @override
  Future<void> createBond(String deviceId) async => bondCalls++;
  @override
  Future<int> readRssi(String deviceId) async => -50;

  @override
  Future<Stream<Uint8List>> subscribe(String deviceId, BleCharInfo characteristic) async {
    subscribeCalls++;
    if (subscribeFailures > 0) {
      subscribeFailures--;
      throw StateError('auth required');
    }
    return notifications.stream;
  }

  @override
  Future<void> unsubscribe(String deviceId, BleCharInfo characteristic) async {}
  @override
  Future<void> write(String deviceId, BleCharInfo characteristic, List<int> value,
      {required bool withoutResponse}) async {}
}

class CollectingSink implements ReadingSink {
  final List<SensorReading> readings = [];

  @override
  void ingest(SensorReading reading) => readings.add(reading);
}

class MemorySessionStore implements SessionStore {
  final Map<int, SessionInfo> sessions = {};
  final Map<int, List<StoredSample>> samples = {};
  final Map<int, List<SessionEvent>> eventLog = {};
  int _nextId = 1;
  int _nextRow = 1;
  int failInserts = 0;

  @override
  Future<int> recoverInterrupted() async {
    var count = 0;
    for (final s in sessions.values.toList()) {
      if (s.status == SessionStatus.recording) {
        count++;
        _replace(s, status: SessionStatus.interrupted);
      }
    }
    return count;
  }

  void _replace(SessionInfo s, {SessionStatus? status, int? endedAtMs, String? name, String? config}) {
    sessions[s.id] = SessionInfo(
      id: s.id,
      name: name ?? s.name,
      startedAtMs: s.startedAtMs,
      endedAtMs: endedAtMs ?? s.endedAtMs,
      deviceName: s.deviceName,
      deviceId: s.deviceId,
      firmware: s.firmware,
      source: s.source,
      status: status ?? s.status,
      sampleCount: samples[s.id]?.length ?? 0,
      configJson: config ?? s.configJson,
    );
  }

  @override
  Future<int> createSession({
    required String name,
    required int startedAtMs,
    required String deviceName,
    required String deviceId,
    required String firmware,
    required DataSource source,
    required String configJson,
  }) async {
    final id = _nextId++;
    sessions[id] = SessionInfo(
      id: id,
      name: name,
      startedAtMs: startedAtMs,
      deviceName: deviceName,
      deviceId: deviceId,
      firmware: firmware,
      source: source,
      status: SessionStatus.recording,
      configJson: configJson,
    );
    samples[id] = [];
    eventLog[id] = [];
    return id;
  }

  @override
  Future<void> insertSamples(int sessionId, List<SensorReading> readings) async {
    if (failInserts > 0) {
      failInserts--;
      throw StateError('disk full');
    }
    for (final r in readings) {
      samples[sessionId]!.add(StoredSample(
        rowId: _nextRow++,
        kind: r.kind,
        receivedAtMs: r.receivedAtMs,
        deviceTicks: r.deviceTicks,
        values: r.values,
      ));
    }
  }

  @override
  Future<void> addEvent(int sessionId, SessionEvent event) async =>
      eventLog[sessionId]!.add(event);

  @override
  Future<void> finishSession(int sessionId,
      {required int endedAtMs, required SessionStatus status, required String configJson}) async {
    _replace(sessions[sessionId]!, status: status, endedAtMs: endedAtMs, config: configJson);
  }

  @override
  Future<List<SessionInfo>> listSessions() async => sessions.values.toList();
  @override
  Future<SessionInfo?> getSession(int sessionId) async => sessions[sessionId];
  @override
  Future<void> renameSession(int sessionId, String name) async =>
      _replace(sessions[sessionId]!, name: name);
  @override
  Future<void> deleteSession(int sessionId) async {
    sessions.remove(sessionId);
    samples.remove(sessionId);
    eventLog.remove(sessionId);
  }

  @override
  Future<void> deleteAll() async {
    sessions.clear();
    samples.clear();
    eventLog.clear();
  }

  @override
  Future<List<SessionEvent>> events(int sessionId) async => eventLog[sessionId] ?? const [];
  @override
  Future<List<SensorKind>> kindsIn(int sessionId) async =>
      (samples[sessionId] ?? const <StoredSample>[]).map((s) => s.kind).toSet().toList();

  @override
  Future<List<StoredSample>> pageSamples(int sessionId,
      {SensorKind? kind, int afterRowId = 0, int limit = 5000}) async {
    return (samples[sessionId] ?? const <StoredSample>[])
        .where((s) => s.rowId > afterRowId && (kind == null || s.kind == kind))
        .take(limit)
        .toList();
  }
}

SensorReading reading(SensorKind kind, int atMs, List<double> values,
        {DataSource source = DataSource.hardware, int ticks = 0}) =>
    SensorReading(
        kind: kind, deviceTicks: ticks, receivedAtMs: atMs, values: values, source: source);
