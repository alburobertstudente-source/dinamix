import 'dart:convert';

import 'package:dinamix/ble/connection_manager.dart';
import 'package:dinamix/data/session_recorder.dart';
import 'package:dinamix/domain/sensor_kind.dart';
import 'package:dinamix/domain/session.dart';
import 'package:dinamix/export/session_exporter.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  late MemorySessionStore store;
  late SessionRecorder recorder;
  late int now;

  Future<void> start({DataSource source = DataSource.hardware, String name = 'Prova'}) =>
      recorder.start(
        name: name,
        deviceName: 'Scheda',
        deviceId: 'AA',
        firmware: 'FW 1.0',
        source: source,
        config: {'mtu': 247},
      );

  setUp(() {
    now = 1000;
    store = MemorySessionStore();
    recorder = SessionRecorder(
      store,
      flushInterval: const Duration(hours: 1),
      clock: () => now,
    );
  });

  tearDown(() => recorder.dispose());

  group('registrazione', () {
    test('ciclo completo: tutti i dati salvati nell\'ordine di arrivo', () async {
      await start();
      for (var i = 0; i < 100; i++) {
        recorder.ingest(reading(SensorKind.accelerometer, i, [1, 2, 3]));
      }
      now = 3000;
      final id = await recorder.stop();
      expect(recorder.state, RecorderState.idle);
      final session = store.sessions[id]!;
      expect(session.status, SessionStatus.completed);
      expect(session.endedAtMs, 3000);
      expect(session.sampleCount, 100);
      expect(store.samples[id]!.map((s) => s.receivedAtMs), List.generate(100, (i) => i));
      expect(session.config['mean_rate_hz']['acc'], 50.0);
    });

    test('in pausa i dati sono scartati e il tempo non avanza', () async {
      await start();
      recorder.ingest(reading(SensorKind.temperature, 1, [20]));
      now = 2000;
      await recorder.pause();
      recorder.ingest(reading(SensorKind.temperature, 2, [21]));
      now = 12000;
      expect(recorder.elapsed, const Duration(seconds: 1));
      await recorder.resume();
      recorder.ingest(reading(SensorKind.temperature, 3, [22]));
      now = 13000;
      expect(recorder.elapsed, const Duration(seconds: 2));
      final id = await recorder.stop();
      expect(store.samples[id]!.map((s) => s.values.single), [20, 22]);
      expect(store.eventLog[id]!.map((e) => e.type), ['start', 'pause', 'resume', 'stop']);
    });

    test('dati simulati mai mescolati a una sessione reale', () async {
      await start();
      recorder.ingest(reading(SensorKind.temperature, 1, [20], source: DataSource.simulated));
      recorder.ingest(reading(SensorKind.temperature, 2, [21]));
      final id = await recorder.stop();
      expect(store.samples[id]!.single.values.single, 21);
    });

    test('nome vuoto: nome predefinito', () async {
      await start(name: '   ');
      expect(recorder.sessionName, startsWith('Sessione '));
      await recorder.stop();
    });

    test('errore di scrittura: nessuna perdita, nuovo tentativo', () async {
      await start();
      recorder.ingest(reading(SensorKind.temperature, 1, [20]));
      store.failInserts = 1;
      await recorder.flush();
      expect(recorder.pendingSamples, 1);
      expect(recorder.writtenSamples, 0);
      recorder.ingest(reading(SensorKind.temperature, 2, [21]));
      await recorder.flush();
      expect(recorder.pendingSamples, 0);
      final id = recorder.sessionId!;
      expect(store.samples[id]!.map((s) => s.values.single), [20, 21]);
      await recorder.stop();
    });

    test('disco guasto a lungo: memoria limitata e perdita conteggiata', () async {
      recorder = SessionRecorder(store,
          flushInterval: const Duration(hours: 1), clock: () => now, maxPending: 10);
      await start();
      for (var i = 0; i < 25; i++) {
        recorder.ingest(reading(SensorKind.temperature, i, [i.toDouble()]));
      }
      store.failInserts = 1;
      await recorder.flush();
      expect(recorder.pendingSamples, 10);
      expect(recorder.droppedSamples, 15);
      final id = await recorder.stop();
      expect(store.sessions[id]!.config['dropped_samples'], 15);
      expect(store.samples[id]!.first.values.single, 15);
    });

    test('interruzioni del collegamento annotate nella sessione', () async {
      await start();
      await recorder.onLinkEvent(LinkEvent.lost);
      await recorder.onLinkEvent(LinkEvent.restored);
      final id = await recorder.stop();
      expect(store.eventLog[id]!.map((e) => e.type),
          ['start', 'link_lost', 'link_restored', 'stop']);
    });

    test('sessione rimasta aperta dopo un crash: recuperata come interrotta', () async {
      await start();
      recorder.ingest(reading(SensorKind.temperature, 1, [20]));
      await recorder.flush();
      expect(await store.recoverInterrupted(), 1);
      expect(store.sessions[recorder.sessionId]!.status, SessionStatus.interrupted);
    });
  });

  group('esportazione', () {
    Future<SessionInfo> recorded({DataSource source = DataSource.hardware}) async {
      await start(source: source);
      recorder.ingest(reading(SensorKind.accelerometer, 5000, [1, -2, 3], ticks: 77, source: source));
      recorder.ingest(reading(SensorKind.battery, 5001,
          [87.5, 3.91, double.nan, 1], ticks: 78, source: source));
      now = 9000;
      final id = await recorder.stop();
      return store.sessions[id]!;
    }

    test('CSV: metadati, una riga per canale, unità, valore assente vuoto', () async {
      final session = await recorded();
      final out = StringBuffer();
      await SessionExporter(store).writeCsv(session, out);
      final lines = const LineSplitter().convert(out.toString());
      expect(lines, contains('# nome: Prova'));
      expect(lines, contains('# origine_dati: hardware'));
      expect(lines, contains('timestamp_iso,timestamp_ms,device_ticks,sensor,channel,value,unit,source'));
      expect(lines, contains('1970-01-01T00:00:05.000Z,5000,77,acc,y,-2.0,mg,hardware'));
      expect(lines, contains('1970-01-01T00:00:05.001Z,5001,78,batt,current,,mA,hardware'));
      expect(lines.where((l) => !l.startsWith('#')), hasLength(1 + 3 + 4));
    });

    test('CSV: sessione simulata dichiarata nei metadati e in ogni riga', () async {
      final session = await recorded(source: DataSource.simulated);
      final out = StringBuffer();
      await SessionExporter(store).writeCsv(session, out);
      expect(out.toString(), contains('SIMULATO'));
      final rows = const LineSplitter()
          .convert(out.toString())
          .where((l) => l.startsWith('1970'));
      expect(rows.every((r) => r.endsWith(',simulated')), isTrue);
    });

    test('JSON valido, con sensori, unità, eventi e null per i valori assenti', () async {
      final session = await recorded();
      final out = StringBuffer();
      await SessionExporter(store).writeJson(session, out);
      final json = jsonDecode(out.toString()) as Map<String, dynamic>;
      expect(json['format'], 'dinamix-session-1');
      expect(json['session']['data_source'], 'hardware');
      expect(json['session']['firmware'], 'FW 1.0');
      expect(json['sensors']['acc']['channels'][0]['unit'], 'mg');
      expect((json['events'] as List).map((e) => e['type']), ['start', 'stop']);
      final samples = json['samples'] as List;
      expect(samples, hasLength(2));
      expect(samples[0]['sensor'], 'acc');
      expect(samples[0]['ticks'], 77);
      expect(samples[1]['values'][2], isNull);
    });

    test('JSON valido anche senza campioni', () async {
      await start();
      final id = await recorder.stop();
      final out = StringBuffer();
      await SessionExporter(store).writeJson(store.sessions[id]!, out);
      expect((jsonDecode(out.toString()) as Map)['samples'], isEmpty);
    });

    test('quoting CSV', () {
      expect(csvField('semplice'), 'semplice');
      expect(csvField('a,b'), '"a,b"');
      expect(csvField('di "x"'), '"di ""x"""');
    });
  });
}
