// Generates docs/VALIDAZIONE_SIMULAZIONE.md.
// Run from dinamix_app/: dart run tool/simulation_report.dart
// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math' as math;

import 'package:dinamix/sensing/classify/classifier.dart';
import 'package:dinamix/sensing/detection_engine.dart';
import 'package:dinamix/sensing/motion_sample.dart';
import 'package:dinamix/sensing/simulation/physics_simulator.dart';
import 'package:dinamix/sensing/simulation/scenarios.dart';
import 'package:dinamix/sensing/simulation/sim_runner.dart';

/// Seeds 1–8 were used while developing the rules; the report uses only unseen seeds.
const List<int> testSeeds = [9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20];

double median(List<double> v) {
  if (v.isEmpty) return double.nan;
  final s = [...v]..sort();
  return s.length.isOdd ? s[s.length ~/ 2] : (s[s.length ~/ 2 - 1] + s[s.length ~/ 2]) / 2;
}

String f(double v, [int d = 2]) => v.isNaN ? '—' : v.toStringAsFixed(d);
String pct(int k, int n) {
  final (lo, hi) = wilson(k, n);
  return n == 0 ? '—' : '${(100 * k / n).toStringAsFixed(1)}% [${(100 * lo).toStringAsFixed(1)}–${(100 * hi).toStringAsFixed(1)}]';
}

void main() {
  final sources = [
    ('Telefono 200 Hz', SensorModel.phone200, SourceProfile.phone),
    ('Telefono 100 Hz', SensorModel.phone100, SourceProfile.phone),
    ('SensorTile 50 Hz', SensorModel.sensorTile50, SourceProfile.sensorTile),
  ];
  final watch = Stopwatch()..start();
  final results = <(String, ScenarioResult)>[];
  for (final (name, model, profile) in sources) {
    for (final seed in testSeeds) {
      for (final s in buildScenarios(seed)) {
        results.add((name, runScenario(s, model, profile, seed: seed)));
      }
    }
  }
  final spikeResults = <ScenarioResult>[];
  final random = math.Random(99);
  for (var i = 0; i < 300; i++) {
    final s = isolatedSpike(random, walkingBackground: i.isOdd);
    final (_, model, profile) = sources[i % 3];
    spikeResults.add(runScenario(s, model, profile, seed: 1000 + i));
  }
  final elapsed = watch.elapsed;

  final b = StringBuffer()
    ..writeln('# DYNAMIX — Validazione sul simulatore fisico')
    ..writeln()
    ..writeln('Generato da `tool/simulation_report.dart` (algoritmo `$algorithmVersion`).')
    ..writeln()
    ..writeln('> **Questi risultati verificano il codice e la matematica, NON il mondo reale.** Il simulatore usa '
        'modelli semplificati (in particolare la caduta di una persona è un pendolo inverso) e parametri dei '
        'sensori illustrativi. Nessuna percentuale qui sotto è un\'accuratezza del sistema su persone o '
        'dispositivi reali. Le soglie sono provvisorie (docs/SOGLIE.md).')
    ..writeln()
    ..writeln('## Protocollo')
    ..writeln()
    ..writeln('- ${buildScenarios(1).length} scenari × ${testSeeds.length} semi × ${sources.length} sorgenti = '
        '${results.length} simulazioni, più ${spikeResults.length} picchi isolati.')
    ..writeln('- Le regole sono state sviluppate guardando i semi 1–8. **Questo rapporto usa solo i semi '
        '${testSeeds.first}–${testSeeds.last}, mai usati durante lo sviluppo** (insieme di test separato).')
    ..writeln('- La sorgente "Telefono 100 Hz" non è mai stata usata durante lo sviluppo.')
    ..writeln('- Ogni seme cambia rumore, bias, errori di scala, assi di rotazione, ampiezze e fasi.')
    ..writeln('- Tempo di calcolo: ${elapsed.inSeconds} s per ${results.length + spikeResults.length} simulazioni '
        '(${(elapsed.inMilliseconds / (results.length + spikeResults.length)).toStringAsFixed(0)} ms ciascuna, '
        'circa 20 s di dati a 50–200 Hz).')
    ..writeln();

  // Alarm metrics.
  final metrics = Metrics();
  var acceptedEither = 0, alarmsInEither = 0;
  var normalSeconds = 0.0;
  for (final (_, r) in results) {
    final exp = r.scenario.expectation;
    if (exp.alarm == null) {
      acceptedEither++;
      if (r.alarm) alarmsInEither++;
      continue;
    }
    metrics.add(exp.dangerous, r.alarm);
    if (!exp.dangerous) normalSeconds += r.scenario.durationS;
  }
  for (final r in spikeResults) {
    metrics.add(false, r.alarm);
    normalSeconds += r.scenario.durationS;
  }
  final passed = results.where((e) => e.$2.passed).length;
  b
    ..writeln('## Riepilogo')
    ..writeln()
    ..writeln('| Misura | Valore [IC 95% Wilson] |')
    ..writeln('|---|---|')
    ..writeln('| Scenari con categoria e allarme attesi | ${pct(passed, results.length)} |')
    ..writeln('| Allarme: veri positivi (TP) | ${metrics.tp} |')
    ..writeln('| Allarme: falsi positivi (FP) | ${metrics.fp} |')
    ..writeln('| Allarme: falsi negativi (FN) | ${metrics.fn} |')
    ..writeln('| Allarme: veri negativi (TN) | ${metrics.tn} |')
    ..writeln('| Precisione TP/(TP+FP) | ${pct(metrics.tp, metrics.tp + metrics.fp)} |')
    ..writeln('| Recall TP/(TP+FN) | ${pct(metrics.tp, metrics.tp + metrics.fn)} |')
    ..writeln('| F1 | ${f(metrics.f1, 3)} |')
    ..writeln('| Falsi allarmi per ora di attività normale simulata | '
        '${f(metrics.fp / (normalSeconds / 3600), 2)} (su ${f(normalSeconds / 3600, 2)} h) |')
    ..writeln('| Picchi isolati con allarme | ${spikeResults.where((r) => r.alarm).length} su ${spikeResults.length} |')
    ..writeln('| Scenari "fisicamente ambigui" (allarme accettato in entrambi i casi) | '
        '$alarmsInEither allarmi su $acceptedEither |')
    ..writeln()
    ..writeln('Con 0 eventi su n prove, il limite superiore al 95% del tasso è circa 3/n (regola del tre).')
    ..writeln();

  // Latency.
  final latencies = [
    for (final (_, r) in results)
      if (r.latencyS != null) r.latencyS!,
  ];
  b
    ..writeln('## Tempo di rilevamento (eventi pericolosi)')
    ..writeln()
    ..writeln('Dal momento dell\'impatto all\'allarme. Include la fase di osservazione post-evento '
        '(T_post = ${const EngineConfig().postWindowS.toStringAsFixed(0)} s), necessaria per la regola anti-falsi '
        'allarmi (§28.4).')
    ..writeln()
    ..writeln('| Mediana | 95° percentile | Massimo | n |')
    ..writeln('|---|---|---|---|');
  if (latencies.isNotEmpty) {
    final s = [...latencies]..sort();
    b.writeln('| ${f(median(s))} s | ${f(s[(0.95 * (s.length - 1)).round()])} s | ${f(s.last)} s | ${s.length} |');
  }
  b.writeln();

  // Per-scenario table.
  b
    ..writeln('## Risultati per scenario')
    ..writeln()
    ..writeln('Valori mediani dell\'evento più severo, su tutte le sorgenti e i semi.')
    ..writeln()
    ..writeln('| Scenario | Superati | Categoria più frequente | Livello | Allarmi | a max (m/s²) | G max | '
        'Jerk max (m/s³) | Durata (s) | ω max (rad/s) | Δv urto (m/s) | Confidenza |')
    ..writeln('|---|---|---|---|---|---|---|---|---|---|---|---|');
  final ids = buildScenarios(1).map((s) => s.id).toList();
  for (final id in ids) {
    final rs = [for (final (_, r) in results) if (r.scenario.id == id) r];
    final events = [for (final r in rs) if (r.strongest != null) r.strongest!];
    final counts = <String, int>{};
    for (final r in rs) {
      final k = r.strongest?.category.label ?? 'nessun evento';
      counts[k] = (counts[k] ?? 0) + 1;
    }
    final top = counts.entries.reduce((a, c) => c.value > a.value ? c : a);
    double med(double Function(DetectionEvent) g) => median([for (final e in events) g(e)]);
    b.writeln('| ${rs.first.scenario.title} | ${rs.where((r) => r.passed).length}/${rs.length} | '
        '${top.key} (${top.value}) | ${f(med((e) => e.level.value.toDouble()), 0)} | '
        '${rs.where((r) => r.alarm).length} | ${f(med((e) => e.features.peakA), 1)} | '
        '${f(med((e) => e.features.peakG))} | ${f(med((e) => e.features.peakJerk), 0)} | '
        '${f(med((e) => e.features.durationS))} | ${f(med((e) => e.features.peakOmega), 1)} | '
        '${f(med((e) => e.features.dvImpact))} | ${f(med((e) => e.classification.confidence))} |');
  }
  b.writeln();

  // Per source.
  b
    ..writeln('## Per sorgente')
    ..writeln()
    ..writeln('| Sorgente | Scenari superati | FP | FN |')
    ..writeln('|---|---|---|---|');
  for (final (name, _, _) in sources) {
    final rs = [for (final (n, r) in results) if (n == name) r];
    final m = Metrics();
    for (final r in rs) {
      if (r.scenario.expectation.alarm != null) m.add(r.scenario.expectation.dangerous, r.alarm);
    }
    b.writeln('| $name | ${pct(rs.where((r) => r.passed).length, rs.length)} | ${m.fp} | ${m.fn} |');
  }
  b.writeln();

  // Free fall physics check.
  b
    ..writeln('## Verifica fisica della caduta libera')
    ..writeln()
    ..writeln('Telefono 200 Hz. Confronto con T = √(2h/g) e v = √(2gh).')
    ..writeln()
    ..writeln('| Altezza | T teorico (s) | T misurato, mediana (s) | v teorica (m/s) | g·T misurato (m/s) |')
    ..writeln('|---|---|---|---|---|');
  for (final h in [0.3, 0.5, 0.75, 1.0, 1.5]) {
    final rs = [
      for (final (n, r) in results)
        if (n == 'Telefono 200 Hz' && r.scenario.dropHeightM == h && r.scenario.id.startsWith('caduta_tavolo')) r,
    ];
    final t = median([for (final r in rs) r.strongest?.features.freeFallS ?? double.nan]);
    final v = median([for (final r in rs) r.strongest?.features.dvKinematic ?? double.nan]);
    b.writeln('| ${f(h)} m | ${f(math.sqrt(2 * h / g0), 3)} | ${f(t, 3)} | ${f(math.sqrt(2 * g0 * h))} | ${f(v)} |');
  }
  b.writeln();

  // Confusion.
  b
    ..writeln('## Matrice di confusione (scenario → categoria assegnata)')
    ..writeln()
    ..writeln('| Scenario | Categorie (conteggio) |')
    ..writeln('|---|---|');
  confusion([for (final (_, r) in results) r]).forEach((k, v) {
    final cells = v.entries.toList()..sort((a, c) => c.value.compareTo(a.value));
    b.writeln('| $k | ${cells.map((e) => '${e.key}: ${e.value}').join(', ')} |');
  });
  b.writeln();

  final failures = [for (final (n, r) in results) if (!r.passed) (n, r)];
  b
    ..writeln('## Casi non superati')
    ..writeln();
  if (failures.isEmpty) {
    b.writeln('Nessuno.');
  } else {
    b
      ..writeln('| Sorgente | Scenario | Categoria | Livello | Allarme | Motivi |')
      ..writeln('|---|---|---|---|---|---|');
    for (final (n, r) in failures) {
      final e = r.strongest;
      b.writeln('| $n | ${r.scenario.title} | ${e?.category.label ?? '—'} | ${e?.level.value ?? '—'} | '
          '${r.alarm ? 'sì' : 'no'} | ${e?.classification.reasons.join('; ') ?? ''} |');
    }
  }
  b
    ..writeln()
    ..writeln('## Limiti')
    ..writeln()
    ..writeln('- I modelli di moto sono semplificati e le categorie attese sono definite da chi ha scritto il '
        'simulatore: un modello che li supera può comunque sbagliare su dati reali.')
    ..writeln('- Il lancio del telefono su superficie morbida e la caduta da tasca possono risultare ambigui: '
        'con un solo sensore inerziale la caduta libera di un oggetto e quella di una persona da ~1 m '
        'non sono separabili con certezza (relazione §9.4).')
    ..writeln('- Le metriche reali vanno misurate con la procedura della relazione §14 e §29.')
    ..writeln();

  final file = File('docs/VALIDAZIONE_SIMULAZIONE.md');
  file.writeAsStringSync(b.toString());
  print('Scritto ${file.path}: $passed/${results.length} superati, FP=${metrics.fp}, FN=${metrics.fn}');
  // Keep the category enum referenced for the label lookup above.
  assert(MovementCategory.values.isNotEmpty);
}
