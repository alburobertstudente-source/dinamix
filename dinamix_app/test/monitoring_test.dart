import 'dart:async';

import 'package:dinamix/app/services.dart';
import 'package:dinamix/alert/platform_alert.dart';
import 'package:dinamix/ble/transport/phone_transport.dart';
import 'package:dinamix/core/keep_alive.dart';
import 'package:dinamix/monitoring/event_store.dart';
import 'package:dinamix/sensing/motion_sample.dart';
import 'package:dinamix/sensing/simulation/physics_simulator.dart';
import 'package:dinamix/sensing/simulation/scenarios.dart';
import 'package:dinamix/settings/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

class ScriptedSensors implements PhoneSensorSource {
  final acc = StreamController<Vector3Sample>.broadcast();
  final gyro = StreamController<Vector3Sample>.broadcast();
  @override
  Stream<Vector3Sample> accelerometer() => acc.stream;
  @override
  Stream<Vector3Sample> gyroscope() => gyro.stream;
  @override
  Stream<Vector3Sample> magnetometer() => const Stream.empty();
  @override
  Stream<double> barometer() => const Stream.empty();
}

void main() {
  test('telefono → motore → evento salvato → allerta (prova, nessun SMS)', () async {
    SharedPreferences.setMockInitialValues({'detection_mode': 'phone', 'sms_dry_run': true, 'simulation': true});
    final prefs = await SharedPreferences.getInstance();
    final sensors = ScriptedSensors();
    final store = MemoryEventStore();
    final sms = FakeSmsSender();
    final services = await AppServices.create(
      settings: AppSettings(prefs),
      store: MemorySessionStore(),
      keepAlive: NoopKeepAlive(),
      phoneSensors: sensors,
      events: store,
      smsSender: sms,
    );
    expect(await services.startMonitoring(), isNull);
    expect(services.monitoring.running, isTrue);

    // Replays a simulated person fall as if it came from the phone sensors.
    final scenario = buildScenarios(3).firstWhere((s) => s.id == 'caduta_persona');
    final samples = PhysicsSimulator(SensorModel.phone200, seed: 3).run(scenario);
    const base = 1700000000000000; // µs, like SensorEvent timestamps
    for (final s in samples) {
      final v = Vector3Sample(s.v.x, s.v.y, s.v.z, tUs: base + s.tNs ~/ 1000);
      if (s.kind == SampleKind.acc) sensors.acc.add(v);
      if (s.kind == SampleKind.gyro) sensors.gyro.add(v);
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    services.monitoring.engine.flush();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(store.detections, isNotEmpty);
    expect(store.detections.any((d) => d.alarm), isTrue);
    expect(services.alerts.active, isTrue);
    expect(services.alerts.current?.dryRun, isTrue);
    await services.alerts.cancel();
    expect(sms.sent, isEmpty);
    await services.stopMonitoring();
  });
}
