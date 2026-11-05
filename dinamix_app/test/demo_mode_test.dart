import 'dart:async';
import 'dart:math' as math;

import 'package:dinamix/ble/connection_manager.dart';
import 'package:dinamix/ble/transport/phone_transport.dart';
import 'package:dinamix/data/session_recorder.dart';
import 'package:dinamix/domain/sensor_kind.dart';
import 'package:dinamix/domain/session.dart';
import 'package:dinamix/domain/units.dart';
import 'package:dinamix/session/live_session.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

class FakePhoneSensors implements PhoneSensorSource {
  final acc = StreamController<Vector3Sample>.broadcast();
  final gyro = StreamController<Vector3Sample>.broadcast();
  final mag = StreamController<Vector3Sample>.broadcast();
  final baro = StreamController<double>.broadcast();

  @override
  Stream<Vector3Sample> accelerometer() => acc.stream;
  @override
  Stream<Vector3Sample> gyroscope() => gyro.stream;
  @override
  Stream<Vector3Sample> magnetometer() => mag.stream;
  @override
  Stream<double> barometer() => baro.stream;
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  group('sensori del telefono', () {
    late FakePhoneSensors sensors;
    late ConnectionManager manager;
    late CollectingSink sink;

    setUp(() async {
      sensors = FakePhoneSensors();
      sink = CollectingSink();
      manager = ConnectionManager(PhoneTransport(sensors: sensors))..addSink(sink);
      await manager.connect(const DeviceRef(PhoneTransport.deviceId, PhoneTransport.deviceName));
    });

    tearDown(() => manager.disconnect());

    test('la connessione espone i sensori e marca la provenienza', () {
      expect(manager.isReady, isTrue);
      expect(manager.isDemo, isTrue);
      expect(manager.isSimulated, isFalse);
      expect(manager.activeKinds, {
        SensorKind.accelerometer,
        SensorKind.gyroscope,
        SensorKind.magnetometer,
        SensorKind.pressure,
      });
    });

    test('accelerometro: da m/s² a mg', () async {
      sensors.acc.add(const Vector3Sample(0, 0, standardGravity));
      await settle();
      final r = sink.readings.single;
      expect(r.kind, SensorKind.accelerometer);
      expect(r.source, DataSource.phone);
      expect(r.values, [0, 0, 1000]);
    });

    test('giroscopio: da rad/s a dps', () async {
      sensors.gyro.add(const Vector3Sample(math.pi, -math.pi / 2, 0));
      await settle();
      expect(sink.readings.single.values, [180, -90, 0]);
    });

    test('magnetometro: da µT a mGa', () async {
      sensors.mag.add(const Vector3Sample(23, -41.5, 0));
      await settle();
      expect(sink.readings.single.values, [230, -415, 0]);
    });

    test('barometro in hPa', () async {
      sensors.baro.add(1013.25);
      await settle();
      expect(sink.readings.single.values.single, closeTo(1013.25, 1e-9));
    });

    test('valori fuori scala saturati, senza errori di decodifica', () async {
      sensors.acc.add(const Vector3Sample(1000, -1000, 0));
      await settle();
      expect(sink.readings.single.values, [32767, -32768, 0]);
      expect(manager.characteristics.first.decodeErrors, 0);
    });

    test('sensore mancante: gli altri continuano', () async {
      sensors.baro.addError(StateError('assente'));
      sensors.acc.add(const Vector3Sample(0, 0, standardGravity));
      await settle();
      expect(sink.readings, hasLength(1));
      expect(manager.isReady, isTrue);
    });

    test('dopo la disconnessione nessun dato', () async {
      await manager.disconnect();
      sensors.acc.add(const Vector3Sample(0, 0, standardGravity));
      await settle();
      expect(sink.readings, isEmpty);
    });
  });

  test('sessione del telefono: etichetta e separazione dai dati reali', () async {
    final store = MemorySessionStore();
    final recorder = SessionRecorder(store, flushInterval: const Duration(hours: 1));
    await recorder.start(
      name: 'Demo',
      deviceName: PhoneTransport.deviceName,
      deviceId: PhoneTransport.deviceId,
      firmware: 'n/d',
      source: DataSource.phone,
      config: const {},
    );
    recorder.ingest(reading(SensorKind.temperature, 1, [20]));
    recorder.ingest(reading(SensorKind.accelerometer, 2, [0, 0, 1000], source: DataSource.phone));
    final id = await recorder.stop();
    recorder.dispose();
    final SessionInfo session = store.sessions[id]!;
    expect(store.samples[id]!.single.kind, SensorKind.accelerometer);
    expect(session.sourceTag, 'TELEFONO');
  });

  group('sessione attiva', () {
    late int now;
    late LiveSessionController session;
    late List<double> impacts;

    void acc(double x, double y, double z, {int stepMs = 20}) {
      now += stepMs;
      session.ingest(reading(SensorKind.accelerometer, now, [x, y, z]));
    }

    setUp(() {
      now = 1000;
      impacts = [];
      session = LiveSessionController(
        impactThresholdG: 4,
        refractoryMs: 1000,
        clock: () => now,
      )..onImpact = impacts.add;
    });

    test('in attesa finché non arrivano dati', () {
      expect(session.level, MotionLevel.waiting);
    });

    test('fermo: 1 g, livello calmo', () {
      for (var i = 0; i < 50; i++) {
        acc(0, 0, 1000);
      }
      expect(session.currentG, closeTo(1, 1e-9));
      expect(session.level, MotionLevel.calm);
      expect(impacts, isEmpty);
    });

    test('movimento forte: livello alto', () {
      for (var i = 0; i < 80; i++) {
        acc(0, 0, i.isEven ? 3000 : 0);
      }
      expect(session.level, MotionLevel.intense);
    });

    test('picco oltre soglia segnalato una sola volta nel tempo refrattario', () {
      acc(3000, 4000, 0);
      acc(3000, 4000, 0, stepMs: 100);
      expect(impacts, [5]);
      acc(3000, 4000, 0, stepMs: 1200);
      expect(impacts, [5, 5]);
      expect(session.impacts, 2);
      expect(session.peakG, closeTo(5, 1e-9));
    });

    test('inclinazione dalla gravità', () {
      acc(0, 1000, 0);
      expect(session.pitch, closeTo(math.pi / 2, 1e-6));
      for (var i = 0; i < 200; i++) {
        acc(0, 0, 1000);
      }
      expect(session.pitch, closeTo(0, 1e-3));
    });

    test('rotazione: modulo e massimo', () {
      session.ingest(reading(SensorKind.gyroscope, now, [30, 40, 0]));
      session.ingest(reading(SensorKind.gyroscope, now, [3, 4, 0]));
      expect(session.rotationDps, closeTo(5, 1e-9));
      expect(session.peakRotationDps, closeTo(50, 1e-9));
    });

    test('storico limitato', () {
      for (var i = 0; i < 500; i++) {
        acc(0, 0, 1000, stepMs: 50);
      }
      expect(session.history, hasLength(LiveSessionController.historyLength));
    });
  });
}
