import 'dart:async';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../alert/alert_manager.dart';
import '../../../monitoring/monitoring_service.dart';
import '../../../sensing/detection_engine.dart';
import '../../../sensing/motion_sample.dart';
import '../../../sensing/simulation/physics_simulator.dart';
import '../../../sensing/simulation/scenarios.dart';
import '../../../sensing/simulation/sim_runner.dart';
import '../../detection_ui.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/live_trace.dart';

/// Technical diagnostics of the detection (specification §14).
class DetectionScreen extends StatefulWidget {
  const DetectionScreen({super.key});

  @override
  State<DetectionScreen> createState() => _DetectionScreenState();
}

class _DetectionScreenState extends State<DetectionScreen> {
  static const int _points = 200; // 10 s at 20 Hz
  final _a = TraceBuffer(_points);
  final _g = TraceBuffer(_points);
  final _j = TraceBuffer(_points);
  final _w = TraceBuffer(_points);
  final _f = TraceBuffer(_points);
  final _alpha = TraceBuffer(_points);
  Timer? _timer;
  int _revision = 0;
  int _lastFrames = -1;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) => _sample());
  }

  void _sample() {
    final m = context.read<MonitoringService>();
    final fr = m.engine.latest;
    if (!m.running || fr == null || m.engine.framesProcessed == _lastFrames) return;
    _lastFrames = m.engine.framesProcessed;
    _a.add(fr.aNorm);
    _g.add(fr.aNorm / g0);
    _j.add(fr.jNorm);
    _w.add(fr.omegaNorm);
    _f.add(fr.fNorm);
    _alpha.add(fr.alpha.norm);
    setState(() => _revision++);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = context.watch<MonitoringService>();
    final fr = m.engine.latest;
    final q = m.engine.quality();
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final last = m.lastEvent;
    final o = m.engine.orientation;
    String v3(dynamic v) => v == null ? '—' : '${v.x.toStringAsFixed(2)}  ${v.y.toStringAsFixed(2)}  ${v.z.toStringAsFixed(2)}';
    return Scaffold(
      appBar: AppBar(title: const Text('Diagnostica rilevamento')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          if (!m.running)
            const Card(
              child: ListTile(
                leading: Icon(Icons.info_outline_rounded),
                title: Text('Monitoraggio fermo'),
                subtitle: Text('Avvialo dalla dashboard per vedere i segnali in tempo reale.'),
              ),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Rischio attuale', style: TextStyle(color: muted)),
                      const Spacer(),
                      LevelBadge(m.currentLevel.value, large: true),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    last == null
                        ? 'Nessun evento analizzato'
                        : '${last.category.label}${last.provisional ? ' (provvisorio)' : ''} · '
                            'confidenza ${(last.classification.confidence * 100).round()}/100',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (last != null && last.classification.reasons.isNotEmpty)
                    Text(last.classification.reasons.join(' · '), style: TextStyle(color: muted, fontSize: 12.5)),
                  const SizedBox(height: 4),
                  Text('La confidenza è un indice euristico, non una probabilità calibrata.',
                      style: TextStyle(color: muted, fontSize: 11.5)),
                ],
              ),
            ),
          ),
          const SectionTitle('Segnali (ultimi 10 s)'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  LiveTrace(buffer: _f, color: Palette.axes[3], label: '|f| forza specifica', unit: 'm/s²',
                      minRange: 12, reference: g0, referenceLabel: 'g', revision: _revision),
                  const SizedBox(height: 12),
                  LiveTrace(buffer: _a, color: Palette.axes[0], label: '|a| accelerazione dinamica', unit: 'm/s²',
                      minRange: 3, revision: _revision),
                  const SizedBox(height: 12),
                  LiveTrace(buffer: _g, color: Palette.cyan, label: 'G dinamico', unit: 'g',
                      minRange: 0.5, revision: _revision),
                  const SizedBox(height: 12),
                  LiveTrace(buffer: _j, color: Palette.axes[1], label: '|j| jerk (derivata filtrata)', unit: 'm/s³',
                      minRange: 20, revision: _revision),
                  const SizedBox(height: 12),
                  LiveTrace(buffer: _w, color: Palette.axes[2], label: '|ω| velocità angolare', unit: 'rad/s',
                      minRange: 1, reference: const EngineConfig().triggerOmega, referenceLabel: 'soglia provvisoria',
                      revision: _revision),
                  const SizedBox(height: 12),
                  LiveTrace(buffer: _alpha, color: Palette.warning, label: '|α| accelerazione angolare', unit: 'rad/s²',
                      minRange: 10, revision: _revision),
                ],
              ),
            ),
          ),
          const SectionTitle('Valori istantanei'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  _Row('Accelerometro f (x y z)', fr == null ? '—' : '${v3(fr.f)} m/s²'),
                  _Row('Accelerazione dinamica a_W (x y z)', fr == null ? '—' : '${v3(fr.aW)} m/s²'),
                  _Row('Verticale / orizzontale',
                      fr == null ? '—' : '${fr.aVertical.toStringAsFixed(2)} / ${fr.aHorizontal.toStringAsFixed(2)} m/s²'),
                  _Row('G dinamico', fr == null ? '—' : (fr.aNorm / g0).toStringAsFixed(3)),
                  _Row('Giroscopio ω (x y z)', fr == null ? '—' : '${v3(fr.omega)} rad/s'),
                  _Row('Caduta libera', fr == null ? '—' : (fr.freeFall ? 'sì' : 'no')),
                  _Row('Fermo', fr == null ? '—' : (fr.still ? 'sì' : 'no')),
                ],
              ),
            ),
          ),
          const SectionTitle('Sorgente e qualità'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  _Row('Sorgente', m.engine.profile.name + (m.engine.profile.verified ? '' : ' (caratteristiche non verificate)')),
                  _Row('Frequenza misurata', '${q.rateHz.toStringAsFixed(1)} Hz'),
                  _Row('Campioni acc / giro', '${m.samplesAcc} / ${m.samplesGyro}'),
                  _Row('Giroscopio', o.hasGyro ? (o.biasEstimated ? 'presente, bias stimato' : 'presente, bias in stima') : 'assente'),
                  _Row('Bias giroscopio', v3(o.bias)),
                  _Row('g calibrata', '${o.gCal.toStringAsFixed(3)} m/s²'),
                  _Row('Incertezza orientamento', '${(o.sigmaTheta * 57.3).toStringAsFixed(1)}°'),
                  _Row('Linea di base |a|', 'mediana ${m.engine.baselineMedian.toStringAsFixed(2)}, MAD ${m.engine.baselineMad.toStringAsFixed(2)}'),
                  _Row('GPS', 'non attivo in questa versione'),
                  const Divider(),
                  _Row('Qualità complessiva Q', '${(q.value * 100).round()}/100'),
                  _Row('· frequenza · buchi · saturazione',
                      '${q.rate.toStringAsFixed(2)} · ${q.gaps.toStringAsFixed(2)} · ${q.saturation.toStringAsFixed(2)}'),
                  _Row('· orientamento · giroscopio · tempi',
                      '${q.orientation.toStringAsFixed(2)} · ${q.gyro.toStringAsFixed(2)} · ${q.timing.toStringAsFixed(2)}'),
                ],
              ),
            ),
          ),
          const SectionTitle('Simulazione'),
          const _SimulationPanel(),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
                flex: 5,
                child: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13))),
            const SizedBox(width: 8),
            Expanded(
              flex: 6,
              child: Text(value,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, fontFeatures: [FontFeature.tabularFigures()])),
            ),
          ],
        ),
      );
}

/// Runs a simulated scenario through the same engine, in a background isolate,
/// and an alarm test that never sends an SMS.
class _SimulationPanel extends StatefulWidget {
  const _SimulationPanel();

  @override
  State<_SimulationPanel> createState() => _SimulationPanelState();
}

class _SimulationPanelState extends State<_SimulationPanel> {
  final List<(String, String)> _scenarios = [for (final s in buildScenarios(1)) (s.id, s.title)];
  String _selected = 'caduta_persona';
  bool _running = false;
  Map<String, Object?>? _result;
  int _seed = 1;

  static Map<String, Object?> _run((String, int) args) {
    final (id, seed) = args;
    final scenario = buildScenarios(seed).firstWhere((s) => s.id == id);
    final watch = Stopwatch()..start();
    final r = runScenario(scenario, SensorModel.phone200, SourceProfile.phone, seed: seed);
    final e = r.strongest;
    return {
      'title': scenario.title,
      'category': e?.category.label ?? 'nessun evento',
      'level': e?.level.value ?? 0,
      'confidence': e?.classification.confidence ?? 0,
      'alarm': r.alarm,
      'expected': scenario.expectation.alarm,
      'passed': r.passed,
      'peak_a': e?.features.peakA ?? 0,
      'peak_g': e?.features.peakG ?? 0,
      'peak_jerk': e?.features.peakJerk ?? 0,
      'duration': e?.features.durationS ?? 0,
      'peak_omega': e?.features.peakOmega ?? 0,
      'dv': e?.features.dvImpact ?? 0,
      'free_fall': e?.features.freeFallS ?? 0,
      'latency': r.latencyS,
      'ms': watch.elapsedMilliseconds,
    };
  }

  Future<void> _start() async {
    setState(() {
      _running = true;
      _result = null;
    });
    final args = (_selected, _seed);
    try {
      final result = await Isolate.run(() => _run(args));
      if (mounted) setState(() => _result = result);
    } catch (e) {
      if (mounted) setState(() => _result = {'error': '$e'});
    } finally {
      _seed++;
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _alarmTest() async {
    final alerts = context.read<AlertManager>();
    await alerts.trigger(
      detectionId: -DateTime.now().millisecondsSinceEpoch,
      title: 'Prova dell\'allarme',
      detail: 'Nessun SMS verrà inviato',
      dryRun: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final r = _result;
    String n(Object? v, [int d = 2]) => v is num ? v.toStringAsFixed(d) : '—';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Lo scenario è generato dal simulatore fisico ed elaborato dallo stesso motore del rilevamento reale. '
                'Non è una validazione nel mondo reale.',
                style: TextStyle(color: muted, fontSize: 12.5)),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _selected,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Scenario'),
              items: [
                for (final (id, title) in _scenarios) DropdownMenuItem(value: id, child: Text(title, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: _running ? null : (v) => setState(() => _selected = v ?? _selected),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _running ? null : _start,
              icon: _running
                  ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.play_arrow_rounded),
              label: Text(_running ? 'Simulazione in corso…' : 'Esegui simulazione'),
            ),
            if (r != null) ...[
              const SizedBox(height: 12),
              if (r['error'] != null)
                Text('Errore: ${r['error']}', style: const TextStyle(color: Palette.danger))
              else ...[
                Row(
                  children: [
                    Expanded(child: Text('${r['category']}', style: const TextStyle(fontWeight: FontWeight.w800))),
                    LevelBadge(r['level'] as int),
                  ],
                ),
                const SizedBox(height: 6),
                _Row('Allarme', '${r['alarm'] == true ? 'sì' : 'no'}${r['expected'] == null ? '' : ' (atteso: ${r['expected'] == true ? 'sì' : 'no'})'}'),
                _Row('Esito rispetto all\'atteso', r['passed'] == true ? 'conforme' : 'NON conforme'),
                _Row('Confidenza', n(r['confidence'])),
                _Row('Accelerazione max', '${n(r['peak_a'], 1)} m/s² (${n(r['peak_g'])} g)'),
                _Row('Jerk max', '${n(r['peak_jerk'], 0)} m/s³'),
                _Row('Durata evento', '${n(r['duration'])} s'),
                _Row('ω max', '${n(r['peak_omega'], 1)} rad/s'),
                _Row('Δv urto', '${n(r['dv'])} m/s'),
                _Row('Caduta libera', '${n(r['free_fall'], 3)} s'),
                _Row('Tempo di rilevamento', r['latency'] == null ? '—' : '${n(r['latency'])} s'),
                _Row('Calcolo', '${r['ms']} ms'),
              ],
            ],
            const Divider(height: 28),
            OutlinedButton.icon(
              onPressed: _alarmTest,
              icon: const Icon(Icons.notifications_active_outlined),
              label: const Text('Prova l\'allarme (nessun SMS)'),
            ),
          ],
        ),
      ),
    );
  }
}
