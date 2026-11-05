import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dinamix/ble/protocol/bluest_uuid.dart';
import 'package:dinamix/ble/protocol/decoder.dart';
import 'package:dinamix/domain/sensor_kind.dart';
import 'package:flutter_test/flutter_test.dart';

DecodeResult decode(String idHex, List<int> bytes, {String group = '0001'}) => BlueStDecoder.decode(
      uuid: BlueStUuid.parse('$idHex-$group-11e1-ac36-0002a5d5c51b'),
      data: Uint8List.fromList(bytes),
      receivedAtMs: 1000,
      source: DataSource.hardware,
    );

void main() {
  group('intestazione', () {
    test('timestamp a 16 bit little-endian', () {
      final r = decode('00010000', [0x34, 0x12, 0x00, 0x00]);
      expect(r.ticks, 0x1234);
    });

    test('pacchetto senza timestamp: errore', () {
      expect(() => decode('00800000', [0x01]), throwsA(isA<DecodeException>()));
    });
  });

  group('sensori inerziali', () {
    test('accelerometro in mg, con segno', () {
      final r = decode('00800000', [0, 0, 0x64, 0x00, 0x9C, 0xFF, 0xE8, 0x03]);
      expect(r.readings.single.kind, SensorKind.accelerometer);
      expect(r.readings.single.values, [100, -100, 1000]);
    });

    test('giroscopio diviso per 10, in dps', () {
      final r = decode('00400000', [0, 0, 0x7B, 0x00, 0xFB, 0xFF, 0x00, 0x00]);
      expect(r.readings.single.values, [12.3, -0.5, 0]);
    });

    test('magnetometro in mGa', () {
      final r = decode('00200000', [0, 0, 0xE6, 0x00, 0x66, 0xFE, 0x00, 0x00]);
      expect(r.readings.single.values, [230, -410, 0]);
    });

    test('caratteristica condivisa: ordine dal bit più alto', () {
      final r = decode('00e00000', [
        0, 0, //
        1, 0, 2, 0, 3, 0, // acc
        10, 0, 20, 0, 30, 0, // gyro
        7, 0, 8, 0, 9, 0, // mag
      ]);
      expect(r.readings.map((e) => e.kind), [
        SensorKind.accelerometer,
        SensorKind.gyroscope,
        SensorKind.magnetometer,
      ]);
      expect(r.readings[0].values, [1, 2, 3]);
      expect(r.readings[1].values, [1, 2, 3]);
      expect(r.readings[2].values, [7, 8, 9]);
    });

    test('dati troncati: errore che nomina la funzione', () {
      expect(
        () => decode('00800000', [0, 0, 1, 0, 2]),
        throwsA(isA<DecodeException>().having((e) => e.message, 'message', contains('Accelerometer'))),
      );
    });
  });

  group('ambientali', () {
    test('pressione: int32 / 100', () {
      final r = decode('00100000', [0, 0, 0xCD, 0x8B, 0x01, 0x00]);
      expect(r.readings.single.values.single, closeTo(1013.25, 1e-9));
    });

    test('umidità: uint16 / 10', () {
      final r = decode('00080000', [0, 0, 0xE0, 0x01]);
      expect(r.readings.single.values.single, closeTo(48.0, 1e-9));
    });

    test('temperatura negativa: int16 / 10', () {
      final r = decode('00010000', [0, 0, 0xC9, 0xFF]);
      expect(r.readings.single.kind, SensorKind.temperature);
      expect(r.readings.single.values.single, closeTo(-5.5, 1e-9));
    });
  });

  group('batteria', () {
    test('livello, tensione, corrente, stato', () {
      final r = decode('00020000', [0, 0, 0x6B, 0x03, 0x46, 0x0F, 0xDD, 0xFF, 0x01]);
      final v = r.readings.single.values;
      expect(v[0], closeTo(87.5, 1e-9));
      expect(v[1], closeTo(3.91, 1e-9));
      expect(v[2], closeTo(-35, 1e-9));
      expect(v[3], 1);
    });

    test('bit 0x80: corrente ad alta risoluzione, stato mascherato', () {
      final r = decode('00020000', [0, 0, 0x6B, 0x03, 0x46, 0x0F, 0xDD, 0xFF, 0x83]);
      expect(r.readings.single.values[2], closeTo(-3.5, 1e-9));
      expect(r.readings.single.values[3], 3);
    });

    test('corrente sconosciuta: NaN', () {
      final r = decode('00020000', [0, 0, 0x6B, 0x03, 0x46, 0x0F, 0x00, 0x80, 0x01]);
      expect(r.readings.single.values[2].isNaN, isTrue);
    });
  });

  group('sensor fusion', () {
    test('compatta: più quaternioni, qs calcolato, tempi distribuiti', () {
      final r = decode('00000100', [
        0, 0, //
        0xE8, 0x03, 0x30, 0xF8, 0x00, 0x00, // 0.1, -0.2, 0
        0xE8, 0x03, 0x30, 0xF8, 0x00, 0x00,
      ]);
      expect(r.readings, hasLength(2));
      expect(r.readings[0].values[0], closeTo(0.1, 1e-9));
      expect(r.readings[0].values[1], closeTo(-0.2, 1e-9));
      expect(r.readings[0].values[3], closeTo(math.sqrt(0.95), 1e-9));
      expect(r.readings[0].receivedAtMs, 1000);
      expect(r.readings[1].receivedAtMs, 1015);
    });

    test('compatta senza dati: errore', () {
      expect(() => decode('00000100', [0, 0, 1, 2]), throwsA(isA<DecodeException>()));
    });

    test('completa: float32, qs opzionale', () {
      final data = ByteData(14)
        ..setFloat32(2, 0.5, Endian.little)
        ..setFloat32(6, 0.5, Endian.little)
        ..setFloat32(10, 0.5, Endian.little);
      final r = decode('00000080', data.buffer.asUint8List());
      expect(r.readings.single.values[3], closeTo(0.5, 1e-6));
    });
  });

  group('altre funzioni', () {
    test('bussola: uint16 / 100', () {
      final r = decode('00000040', [0, 0, 0x50, 0x46]);
      expect(r.readings.single.values.single, closeTo(180.0, 1e-9));
    });

    test('contapassi', () {
      final r = decode('00000001', [0, 0, 0xE8, 0x03, 0, 0, 0x64, 0x00]);
      expect(r.readings.single.values, [1000, 100]);
    });

    test('attività con e senza byte di algoritmo', () {
      expect(decode('00000010', [0, 0, 0x02]).readings.single.values, [2]);
      expect(decode('00000010', [0, 0, 0x05, 0x07]).readings.single.values, [5]);
    });

    test('microfono', () {
      expect(decode('04000000', [0, 0, 0x28]).readings.single.values, [40]);
    });

    test('switch', () {
      expect(decode('20000000', [0, 0, 0x01]).readings.single.values, [1]);
    });
  });

  group('funzioni estese', () {
    test('QVAR: solo valore, campi assenti NaN', () {
      final r = decode('00000016', [0, 0, 0xFE, 0xFF, 0xFF, 0xFF], group: '0002');
      final v = r.readings.single.values;
      expect(v[0], -2);
      expect(v[1].isNaN && v[2].isNaN && v[3].isNaN, isTrue);
    });

    test('QVAR: tutti i campi', () {
      final r = decode(
        '00000016',
        [0, 0, 1, 0, 0, 0, 9, 2, 0, 0, 0, 3, 0, 0, 0],
        group: '0002',
      );
      expect(r.readings.single.values, [1, 9, 2, 3]);
    });

    test('contatore eventi: uint32', () {
      final r = decode('0000001d', [0, 0, 5, 0, 0, 0], group: '0002');
      expect(r.readings.single.kind, SensorKind.eventCounter);
      expect(r.readings.single.values, [5]);
    });

    test('angoli di Eulero: float32', () {
      final data = ByteData(14)
        ..setFloat32(2, 90, Endian.little)
        ..setFloat32(6, -45, Endian.little)
        ..setFloat32(10, 10, Endian.little);
      final r = decode('0000000d', data.buffer.asUint8List(), group: '0002');
      expect(r.readings.single.values, [90, -45, 10]);
    });

    test('estesa non supportata: nessun dato, nessun errore', () {
      expect(decode('0000001b', [0, 0, 1, 2], group: '0002').readings, isEmpty);
    });
  });

  test('funzione base sconosciuta: si ferma e la segnala', () {
    final r = decode('00800200', [0, 0, 1, 0, 2, 0, 3, 0, 0xFF]);
    expect(r.readings.single.kind, SensorKind.accelerometer);
    expect(r.undecodedMask, 0x00000200);
  });

  test('la provenienza è riportata sui dati', () {
    final r = BlueStDecoder.decode(
      uuid: BlueStUuid.parse('00010000-0001-11e1-ac36-0002a5d5c51b'),
      data: Uint8List.fromList([0, 0, 1, 0]),
      receivedAtMs: 0,
      source: DataSource.simulated,
    );
    expect(r.readings.single.source, DataSource.simulated);
  });
}
