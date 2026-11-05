import 'dart:typed_data';

import 'package:dinamix/ble/connection_manager.dart';
import 'package:dinamix/ble/transport/ble_transport.dart';
import 'package:dinamix/core/app_error.dart';
import 'package:dinamix/domain/sensor_kind.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

Future<void> settle([int ms = 40]) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  late FakeTransport transport;
  late ConnectionManager manager;
  late CollectingSink sink;
  const device = DeviceRef('AA', 'Scheda');

  setUp(() {
    transport = FakeTransport();
    sink = CollectingSink();
    manager = ConnectionManager(transport, backoff: (_) => const Duration(milliseconds: 5))
      ..addSink(sink);
  });

  tearDown(() async {
    await manager.disconnect();
  });

  test('connessione: scopre, attiva le notifiche, decodifica', () async {
    await manager.connect(device);
    expect(manager.phase, ConnectionPhase.ready);
    expect(manager.activeKinds, {SensorKind.accelerometer});
    expect(manager.mtu, 247);

    transport.notifications.add(Uint8List.fromList([1, 0, 100, 0, 0, 0, 0, 0]));
    await settle();
    expect(sink.readings.single.values, [100, 0, 0]);
    expect(sink.readings.single.source, DataSource.hardware);
    expect(manager.characteristics.single.loss.received, 1);
  });

  test('pacchetto malformato: conteggiato, il flusso continua', () async {
    await manager.connect(device);
    transport.notifications.add(Uint8List.fromList([1, 0, 100]));
    transport.notifications.add(Uint8List.fromList([2, 0, 1, 0, 2, 0, 3, 0]));
    await settle();
    expect(manager.characteristics.single.decodeErrors, 1);
    expect(sink.readings, hasLength(1));
  });

  test('errore di connessione alla prima prova: stato failed, nessun ritentativo', () async {
    transport.connectError = const AppError(AppErrorCode.connectTimeout, 'timeout');
    await manager.connect(device);
    expect(manager.phase, ConnectionPhase.failed);
    expect(manager.lastError?.code, AppErrorCode.connectTimeout);
    await settle();
    expect(transport.connectCalls, 1);
  });

  test('errore durante la scoperta dei servizi: failed e collegamento chiuso', () async {
    transport.discoverError = const AppError(AppErrorCode.discoveryFailed, 'x');
    await manager.connect(device);
    expect(manager.phase, ConnectionPhase.failed);
    expect(transport.disconnectCalls, 1);
  });

  test('firmware senza dati decodificabili: errore esplicito', () async {
    transport.hasNotifyCharacteristic = false;
    await manager.connect(device);
    expect(manager.phase, ConnectionPhase.failed);
    expect(manager.lastError?.code, AppErrorCode.noSupportedFeatures);
  });

  test('perdita del collegamento: riconnessione automatica e nuovi dati', () async {
    final events = <LinkEvent>[];
    manager.linkEvents.listen(events.add);
    await manager.connect(device);
    await settle(5);

    transport.link.add(LinkState.disconnected);
    await settle();

    expect(manager.phase, ConnectionPhase.ready);
    expect(transport.connectCalls, 2);
    expect(manager.linkLossCount, 1);
    expect(events, [LinkEvent.established, LinkEvent.lost, LinkEvent.restored]);

    transport.notifications.add(Uint8List.fromList([1, 0, 5, 0, 0, 0, 0, 0]));
    await settle();
    expect(sink.readings, hasLength(1), reason: 'una sola sottoscrizione dopo la riconnessione');
  });

  test('ritenta finché il dispositivo non torna', () async {
    await manager.connect(device);
    transport.connectError = StateError('fuori portata');
    transport.link.add(LinkState.disconnected);
    await settle();
    expect(manager.phase, ConnectionPhase.reconnecting);
    expect(manager.reconnectAttempt, greaterThan(1));

    transport.connectError = null;
    await settle();
    expect(manager.phase, ConnectionPhase.ready);
    expect(manager.reconnectAttempt, 0);
  });

  test('riconnessione automatica disattivata', () async {
    manager.autoReconnect = false;
    await manager.connect(device);
    transport.link.add(LinkState.disconnected);
    await settle();
    expect(manager.phase, ConnectionPhase.failed);
    expect(transport.connectCalls, 1);
  });

  test('disconnessione voluta: nessuna riconnessione', () async {
    await manager.connect(device);
    await manager.disconnect();
    expect(manager.phase, ConnectionPhase.idle);
    transport.link.add(LinkState.disconnected);
    await settle();
    expect(transport.connectCalls, 1);
    expect(manager.phase, ConnectionPhase.idle);
  });

  test('disconnessione durante l\'attesa di riconnessione la annulla', () async {
    final slow = ConnectionManager(transport, backoff: (_) => const Duration(milliseconds: 50));
    await slow.connect(device);
    transport.link.add(LinkState.disconnected);
    await settle(5);
    expect(slow.phase, ConnectionPhase.reconnecting);
    await slow.disconnect();
    await settle(80);
    expect(transport.connectCalls, 1);
    expect(slow.phase, ConnectionPhase.idle);
  });

  test('notifiche rifiutate: associazione e nuovo tentativo', () async {
    transport.subscribeFailures = 1;
    await manager.connect(device);
    expect(transport.bondCalls, 1);
    expect(transport.subscribeCalls, 2);
    expect(manager.phase, ConnectionPhase.ready);
  });

  test('sensore disattivato dall\'utente: disponibile ma non sottoscritto', () async {
    manager.disabledKinds = {SensorKind.accelerometer};
    await manager.connect(device);
    expect(manager.availableKinds, {SensorKind.accelerometer});
    expect(manager.activeKinds, isEmpty);
    expect(transport.subscribeCalls, 0);
    expect(manager.phase, ConnectionPhase.ready);
  });

  test('attesa crescente con tetto massimo', () {
    final m = ConnectionManager(transport);
    expect(m.backoffFor(0), const Duration(seconds: 1));
    expect(m.backoffFor(3), const Duration(seconds: 8));
    expect(m.backoffFor(20), const Duration(seconds: 30));
  });
}
