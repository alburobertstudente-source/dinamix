import 'dart:math' as math;

import 'package:dinamix/analysis/series_analysis.dart';
import 'package:dinamix/domain/sensor_kind.dart';
import 'package:dinamix/domain/units.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  group('conversione unità', () {
    test('accelerazione', () {
      const g = UnitPrefs(acc: AccUnit.g);
      const ms2 = UnitPrefs(acc: AccUnit.ms2);
      expect(g.convert(SensorKind.accelerometer, 0, 1000), closeTo(1, 1e-9));
      expect(ms2.convert(SensorKind.accelerometer, 0, 1000), closeTo(9.80665, 1e-9));
      expect(g.unit(SensorKind.accelerometer, 0), 'g');
    });

    test('velocità angolare', () {
      const p = UnitPrefs(gyro: GyroUnit.rads);
      expect(p.convert(SensorKind.gyroscope, 0, 180), closeTo(math.pi, 1e-9));
    });

    test('campo magnetico: 1000 mGa = 100 µT', () {
      const p = UnitPrefs(mag: MagUnit.uT);
      expect(p.convert(SensorKind.magnetometer, 0, 1000), closeTo(100, 1e-9));
    });

    test('temperatura', () {
      const p = UnitPrefs(temp: TempUnit.fahrenheit);
      expect(p.convert(SensorKind.temperature, 0, 100), closeTo(212, 1e-9));
    });

    test('pressione', () {
      const p = UnitPrefs(pressure: PressureUnit.kPa);
      expect(p.convert(SensorKind.pressure, 0, 1013.25), closeTo(101.325, 1e-9));
    });

    test('valore assente mostrato come trattino', () {
      expect(const UnitPrefs().format(SensorKind.battery, 2, double.nan), '—');
    });
  });

  group('statistiche', () {
    test('valori noti', () {
      final s = SeriesStats();
      <double>[2, 4, 4, 4, 5, 5, 7, 9].forEach(s.add);
      expect(s.count, 8);
      expect(s.min, 2);
      expect(s.max, 9);
      expect(s.mean, closeTo(5, 1e-9));
      expect(s.stdDev, closeTo(2.13809, 1e-5));
      expect(s.peakToPeak, 7);
      expect(s.rms, closeTo(math.sqrt(232 / 8), 1e-9));
    });

    test('variazioni tra campioni consecutivi', () {
      final s = SeriesStats();
      <double>[1, 3, 2].forEach(s.add);
      expect(s.meanAbsDelta, closeTo(1.5, 1e-9));
      expect(s.maxAbsDelta, 2);
    });

    test('NaN ignorati, serie vuota', () {
      final s = SeriesStats()..add(double.nan);
      expect(s.count, 0);
      expect(s.mean.isNaN, isTrue);
      s.add(1);
      expect(s.stdDev.isNaN, isTrue);
    });
  });

  group('riduzione per il grafico', () {
    test('i picchi restano visibili', () {
      final bins = MinMaxBins(0, 1000, 10);
      for (var t = 0; t < 1000; t++) {
        bins.add(t, t == 503 ? 9000 : 1);
      }
      expect(bins.maxs[5], 9000);
      expect(bins.mins[5], 1);
      expect(bins.maxs[4], 1);
    });

    test('tempi fuori intervallo finiscono ai bordi', () {
      final bins = MinMaxBins(100, 200, 4)..add(50, 1)..add(500, 2);
      expect(bins.maxs.first, 1);
      expect(bins.maxs.last, 2);
    });
  });

  group('picchi', () {
    test('tempo refrattario: uno shock conta una volta, col massimo', () {
      final d = PeakDetector(threshold: 4000, refractoryMs: 200)
        ..add(0, 100)
        ..add(100, 5000)
        ..add(120, 9000)
        ..add(150, 6000)
        ..add(1000, 4500);
      expect(d.peaks, hasLength(2));
      expect(d.peaks.first.value, 9000);
      expect(d.peaks.first.atMs, 100);
      expect(d.peaks.last.value, 4500);
    });
  });

  test('analisi completa dal database, a pagine, con modulo', () async {
    final store = MemorySessionStore();
    final id = await store.createSession(
      name: 'n',
      startedAtMs: 0,
      deviceName: 'd',
      deviceId: 'i',
      firmware: 'f',
      source: DataSource.hardware,
      configJson: '{}',
    );
    await store.insertSamples(id, [
      for (var i = 0; i < 12000; i++)
        reading(SensorKind.accelerometer, i, i == 6000 ? [3000, 4000, 0] : [0, 0, 1000]),
      reading(SensorKind.gyroscope, 5, [1, 1, 1]),
    ]);
    final result = await analyzeKind(
      store: store,
      sessionId: id,
      kind: SensorKind.accelerometer,
      startMs: 0,
      endMs: 12000,
      impactThresholdMg: 4000,
    );
    expect(result.samples, 12000);
    expect(result.channels, hasLength(4));
    expect(result.channels.last.label, 'Modulo');
    expect(result.channels.last.stats.max, closeTo(5000, 1e-9));
    expect(result.peaks!.peaks.single.atMs, 6000);
  });
}
