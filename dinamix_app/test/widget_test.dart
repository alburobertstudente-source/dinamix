import 'package:dinamix/ble/connection_manager.dart';
import 'package:dinamix/ble/transport/simulated_transport.dart';
import 'package:dinamix/data/sensor_hub.dart';
import 'package:dinamix/domain/sensor_kind.dart';
import 'package:dinamix/ui/theme.dart';
import 'package:dinamix/ui/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('il banner di simulazione è esplicito', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: const Scaffold(body: SimulationBanner()),
    ));
    expect(find.textContaining('SIMULAZIONE'), findsOneWidget);
  });

  test('buffer circolare: sovrascrive i campioni più vecchi', () {
    final b = ChannelBuffer(1, 3);
    for (var i = 0; i < 5; i++) {
      b.add(i, [i * 10.0]);
    }
    expect(b.length, 3);
    expect(b.timeAt(0), 2);
    expect(b.valueAt(0, 0), 20);
    expect(b.valueAt(0, 2), 40);
  });

  test('hub: la ricezione non dipende dal ridisegno', () {
    final hub = SensorHub(refreshHz: 1);
    final revision = hub.frame.value;
    for (var i = 0; i < 100; i++) {
      hub.ingest(reading(SensorKind.accelerometer, i, [1, 2, 3]));
    }
    expect(hub.buffer(SensorKind.accelerometer)!.length, 100);
    expect(hub.frame.value, revision);
    hub.dispose();
  });

  test('simulatore: il flusso resta marcato come simulato fino al salvataggio', () async {
    final transport = SimulatedTransport();
    final sink = CollectingSink();
    final manager = ConnectionManager(transport)..addSink(sink);
    await manager.connect(const DeviceRef(SimulatedTransport.deviceId, 'Sim'));
    expect(manager.isSimulated, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await manager.disconnect();
    expect(sink.readings, isNotEmpty);
    expect(sink.readings.every((r) => r.source == DataSource.simulated), isTrue);
  });
}
