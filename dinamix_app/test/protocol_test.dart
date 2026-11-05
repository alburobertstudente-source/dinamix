import 'package:dinamix/ble/protocol/advertising.dart';
import 'package:dinamix/ble/protocol/bluest_uuid.dart';
import 'package:dinamix/ble/protocol/packet_loss.dart';
import 'package:dinamix/domain/sensor_kind.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UUID BlueST', () {
    test('caratteristica base con più funzioni', () {
      final u = BlueStUuid.parse('00E00000-0001-11E1-AC36-0002A5D5C51B');
      expect(u.type, BlueStCharType.basic);
      expect(u.decodableKinds, [
        SensorKind.accelerometer,
        SensorKind.gyroscope,
        SensorKind.magnetometer,
      ]);
    });

    test('caratteristica estesa', () {
      final u = BlueStUuid.parse('00000016-0002-11e1-ac36-0002a5d5c51b');
      expect(u.type, BlueStCharType.extended);
      expect(u.decodableKinds, [SensorKind.qvar]);
    });

    test('console di debug riconosciuta con entrambi i blocchi UUID', () {
      expect(BlueStUuid.parse('00000001-000e-11e1-ac36-0002a5d5c51b').isDebugConsole, isTrue);
      expect(BlueStUuid.parse('00000001-000E-11e1-9ab4-0002a5d5c51b').isDebugConsole, isTrue);
      expect(BlueStUuid.parse('00000002-000e-11e1-ac36-0002a5d5c51b').isDebugStderr, isTrue);
    });

    test('Free Fall riconosciuto ma non decodificato', () {
      final u = BlueStUuid.parse('00000200-0001-11e1-ac36-0002a5d5c51b');
      expect(u.displayName, 'Free Fall');
      expect(u.decodableKinds, isEmpty);
    });

    test('UUID non BlueST', () {
      final u = BlueStUuid.parse('00002a37-0000-1000-8000-00805f9b34fb');
      expect(u.type, BlueStCharType.other);
      expect(u.decodableKinds, isEmpty);
    });
  });

  group('advertising', () {
    test('v2 SensorTile.box PRO: scheda e firmware dal catalogo ST', () {
      final a = BlueStAdvertising.parse([
        [0x30, 0x00, 0x02, 0x0D, 0x2A, 1, 2, 3],
      ])!;
      expect(a.protocolVersion, 2);
      expect(a.isSensorTileBoxPro, isTrue);
      expect(a.boardName, 'SensorTile.box PRO');
      expect(a.firmwareLabel, 'STSW-MKBOXPRO Entry/Expert Mode 1.4.1');
      expect(a.optionBytes, [1, 2, 3]);
      expect(a.macAddress, isNull);
    });

    test('v2 con MAC', () {
      final a = BlueStAdvertising.parse([
        [0x30, 0x00, 0x02, 0x0D, 0x0E, 0, 0, 0, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0x01],
      ])!;
      expect(a.macAddress, 'AA:BB:CC:DD:EE:01');
      expect(a.firmwareLabel, 'FP-SNS-STBOX1 BLESensors 1.6.0');
    });

    test('v2 firmware sperimentale e non in catalogo', () {
      expect(
        BlueStAdvertising.parse([
          [0x30, 0x00, 0x02, 0x0D, 0xFF, 0, 0, 0],
        ])!.firmwareLabel,
        contains('sperimentale'),
      );
      expect(
        BlueStAdvertising.parse([
          [0x30, 0x00, 0x02, 0x0D, 0x7A, 0, 0, 0],
        ])!.firmwareLabel,
        contains('Non in catalogo'),
      );
    });

    test('v1: maschera big-endian', () {
      final a = BlueStAdvertising.parse([
        [0x01, 0x06, 0x00, 0xE0, 0x00, 0x00],
      ])!;
      expect(a.protocolVersion, 1);
      expect(a.deviceId, 0x06);
      expect(a.featureMask, 0x00E00000);
      expect(a.isSensorTileBoxPro, isFalse);
    });

    test('v1: bit di sleep', () {
      final a = BlueStAdvertising.parse([
        [0x01, 0x46, 0, 0, 0, 0],
      ])!;
      expect(a.isSleeping, isTrue);
      expect(a.deviceId, 0x06);
    });

    test('dati di altri produttori: ignorati', () {
      expect(
        BlueStAdvertising.parse([
          [0x4C, 0x00, 0x10, 0x05, 0x01, 0x18],
        ]),
        isNull,
      );
      expect(BlueStAdvertising.parse(const []), isNull);
    });
  });

  group('stima pacchetti persi', () {
    PacketLossEstimator feed(Iterable<int> ticks) {
      final e = PacketLossEstimator();
      ticks.forEach(e.add);
      return e;
    }

    test('flusso regolare: nessuna perdita', () {
      final e = feed(List.generate(50, (i) => i * 10));
      expect(e.received, 50);
      expect(e.estimatedLost, 0);
    });

    test('buco di 3 pacchetti', () {
      final ticks = [...List.generate(20, (i) => i * 10), 230, 240];
      final e = feed(ticks);
      expect(e.estimatedLost, 3);
    });

    test('il contatore che riparte da zero non conta come perdita', () {
      final ticks = List.generate(30, (i) => (65400 + i * 10) & 0xFFFF);
      expect(feed(ticks).estimatedLost, 0);
    });

    test('nessuna stima con pochi dati', () {
      expect(feed([0, 10, 500]).estimatedLost, 0);
    });

    test('rapporto', () {
      final e = feed([...List.generate(20, (i) => i * 10), 230]);
      expect(e.lossRatio, closeTo(3 / 24, 1e-9));
    });
  });
}
