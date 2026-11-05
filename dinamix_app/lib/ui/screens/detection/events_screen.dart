import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../monitoring/event_store.dart';
import '../../../monitoring/monitoring_service.dart';
import '../../../sensing/classify/classifier.dart';
import '../../../sensing/motion_sample.dart';
import '../../detection_ui.dart';
import '../../format.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// History of the detected events (report §21, screen 7).
class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  List<StoredDetection>? _items;
  int _minLevel = 0;
  late final MonitoringService _monitoring;

  @override
  void initState() {
    super.initState();
    _monitoring = context.read<MonitoringService>();
    _monitoring.eventsRevision.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    _monitoring.eventsRevision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await _monitoring.store.listDetections(limit: 300);
      if (mounted) setState(() => _items = list);
    } catch (e) {
      if (mounted) setState(() => _items = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final shown = items?.where((d) => d.level >= _minLevel).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Storico eventi')),
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Row(
                    children: [
                      for (final l in [0, 1, 2, 3])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(l == 0 ? 'Tutti' : 'Livello ≥ $l'),
                            selected: _minLevel == l,
                            onSelected: (_) => setState(() => _minLevel = l),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: shown!.isEmpty
                      ? const EmptyState(
                          icon: Icons.history_toggle_off_rounded,
                          title: 'Nessun evento',
                          message: 'Gli eventi anomali rilevati durante il monitoraggio compaiono qui.',
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            itemCount: shown.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, i) {
                              final d = shown[i];
                              return Card(
                                margin: EdgeInsets.zero,
                                child: ListTile(
                                  leading: Icon(categoryIcon(d.category), color: levelColor(d.level)),
                                  title: Text(categoryLabel(d.category)),
                                  subtitle: Text([
                                    formatDateTime(d.atMs),
                                    'confidenza ${(d.confidence * 100).round()}/100',
                                    if (d.source == 'simulated') 'simulazione',
                                    if (d.label != null) 'etichetta: ${d.label}',
                                  ].join(' · ')),
                                  trailing: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      LevelBadge(d.level),
                                      if (d.alarm)
                                        const Padding(
                                          padding: EdgeInsets.only(top: 4),
                                          child: Icon(Icons.notifications_active, size: 16, color: Palette.danger),
                                        ),
                                    ],
                                  ),
                                  onTap: () async {
                                    await Navigator.of(context).push(
                                        MaterialPageRoute<void>(builder: (_) => EventDetailScreen(id: d.id!)));
                                    _load();
                                  },
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}

/// Every number of an event, its raw signal and the manual label for the dataset.
class EventDetailScreen extends StatefulWidget {
  const EventDetailScreen({super.key, required this.id});

  final int id;

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  StoredDetection? _d;
  bool _missing = false;

  static const List<String> labels = [
    'Corretto',
    'Falso allarme',
    'Evento reale non pericoloso',
    'Evento reale pericoloso',
    'Prova controllata',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await context.read<MonitoringService>().store.getDetection(widget.id);
    if (!mounted) return;
    setState(() {
      _d = d;
      _missing = d == null;
    });
  }

  Future<void> _setLabel(String? label) async {
    await context.read<MonitoringService>().store.setLabel(widget.id, label);
    await _load();
  }

  Future<void> _share() async {
    final d = _d!;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/dynamix_evento_${d.id}.json');
    await file.writeAsString(const JsonEncoder.withIndent(' ').convert({
      'format': 'dynamix-event-1',
      'id': d.id,
      'at_ms': d.atMs,
      'source': d.source,
      'algorithm': d.algoVersion,
      'level': d.level,
      'category': d.category,
      'confidence': d.confidence,
      'quality': d.quality,
      'alarm': d.alarm,
      'label': d.label,
      'features': d.features,
      'classification': d.classification,
      'raw_columns': ['t_s', 'fx', 'fy', 'fz', 'wx', 'wy', 'wz'],
      'raw': d.raw,
    }));
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], subject: 'DYNAMIX evento ${d.id}'));
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    if (_missing) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Evento non trovato')));
    }
    if (d == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    final f = d.features;
    final reasons = (d.classification['reasons'] as List?)?.cast<String>() ?? const [];
    final cues = (d.classification['cues'] as Map?)?.cast<String, Object?>() ?? const {};
    String n(String key, [int digits = 2, String unit = '']) {
      final v = f[key];
      if (v is num) return '${v.toStringAsFixed(digits)}$unit';
      if (v is bool) return v ? 'sì' : 'no';
      return '—';
    }

    final dv = (f['dv_impact'] as num?)?.toDouble() ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: Text('Evento ${d.id}'),
        actions: [IconButton(tooltip: 'Condividi i dati', icon: const Icon(Icons.ios_share_rounded), onPressed: _share)],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(categoryIcon(d.category), color: levelColor(d.level), size: 30),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(categoryLabel(d.category),
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                      ),
                      LevelBadge(d.level, large: true),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('${levelName(d.level)} · ${formatDateTime(d.atMs)}'),
                  Text('Confidenza ${(d.confidence * 100).round()}/100 · qualità dei dati ${(d.quality * 100).round()}/100',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  if (d.source == 'simulated') const Text('Dati simulati', style: TextStyle(color: Palette.warning)),
                  if (reasons.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(reasons.join(' · '), style: const TextStyle(fontSize: 12.5)),
                  ],
                ],
              ),
            ),
          ),
          if (d.raw.isNotEmpty) ...[
            const SectionTitle('Segnale |f| (grezzo)'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(height: 120, child: CustomPaint(painter: _RawPainter(d.raw), size: Size.infinite)),
              ),
            ),
          ],
          const SectionTitle('Grandezze del movimento'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  _KV('Durata', n('duration_s', 2, ' s')),
                  _KV('Accelerazione dinamica max', '${n('peak_a', 1, ' m/s²')} (${n('peak_g', 2, ' g')})'),
                  _KV('Δv dell\'urto', '${n('dv_impact', 2, ' m/s')} (altezza equivalente ${equivalentDropHeight(dv).toStringAsFixed(2)} m)'),
                  _KV('Δv impulsivo / cinematico', '${n('dv_impulse')} / ${n('dv_kinematic')} m/s'),
                  _KV('Energia cinetica specifica', n('specific_energy', 2, ' J/kg')),
                  _KV('Jerk max / medio', '${n('peak_jerk', 0)} / ${n('mean_jerk', 0)} m/s³'),
                  _KV('Variazione del jerk max', n('peak_snap', 0, ' m/s⁴')),
                  _KV('ω max', n('peak_omega', 2, ' rad/s')),
                  _KV('α max', n('peak_alpha', 1, ' rad/s²')),
                  _KV('Rotazione percorsa / netta', '${n('rotation_path_rad', 2, ' rad')} / ${n('rotation_net_deg', 0, '°')}'),
                  _KV('Cambio di postura', n('posture_change_deg', 0, '°')),
                  _KV('Caduta libera', '${n('free_fall_s', 3, ' s')} (|f| residuo ${n('free_fall_f_ratio', 2, ' g')})'),
                  _KV('Impulsi / rimbalzi', '${n('pulses', 0)} / ${n('bounces', 0)}'),
                  _KV('Alternanza / dominanza', '${n('alternation')} / ${n('dominance')}'),
                  _KV('Frequenza dominante', '${n('dominant_hz', 1, ' Hz')} (periodicità ${n('periodicity')})'),
                  _KV('Quota vibrazioni', n('hf_ratio')),
                  _KV('Accelerazione sostenuta', '${n('sustained_s', 2, ' s')} a ${n('sustained_mean_g', 2, ' g')}'),
                  _KV('Spostamento stimato', f['displacement'] == null ? 'non stimabile' : '${n('displacement', 3, ' m')} ± ${n('displacement_sigma', 3, ' m')}'),
                  _KV('Velocità iniziale / finale', '${f['v_start'] == null ? 'non stimabile' : n('v_start')} / ${f['v_end'] == null ? 'non stimabile' : n('v_end')}'),
                  _KV('Quiete dopo l\'evento', n('post_still_s', 1, ' s')),
                  _KV('Attività prima / dopo', '${n('pre_activity')} / ${n('post_activity')}'),
                ],
              ),
            ),
          ),
          if (cues.isNotEmpty) ...[
            const SectionTitle('Gruppi di indizi indipendenti'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    for (final e in cues.entries)
                      _KV(_cueName(e.key), (e.value as num).toStringAsFixed(2)),
                  ],
                ),
              ),
            ),
          ],
          const SectionTitle('Etichetta (per la validazione)'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final l in labels)
                ChoiceChip(label: Text(l), selected: d.label == l, onSelected: (s) => _setLabel(s ? l : null)),
            ],
          ),
          const SizedBox(height: 12),
          Text('Algoritmo ${d.algoVersion}. Le soglie sono provvisorie: vedi docs/SOGLIE.md.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
        ],
      ),
    );
  }

  static String _cueName(String k) => switch (k) {
        'impact' => 'Urto (Δv)',
        'fall' => 'Caduta (libera o parziale)',
        'posture' => 'Cambio di postura',
        'inactivity' => 'Inattività dopo l\'urto',
        'gps' => 'Calo di velocità GPS',
        _ => k,
      };
}

class _KV extends StatelessWidget {
  const _KV(this.k, this.v);
  final String k;
  final String v;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(k, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13))),
            const SizedBox(width: 10),
            Flexible(child: Text(v, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
          ],
        ),
      );
}

class _RawPainter extends CustomPainter {
  _RawPainter(this.raw);
  final List<List<double>> raw;

  @override
  void paint(Canvas canvas, Size size) {
    if (raw.length < 2) return;
    final t0 = raw.first[0], t1 = raw.last[0];
    final values = [for (final r in raw) math.sqrt(r[1] * r[1] + r[2] * r[2] + r[3] * r[3])];
    final top = math.max(2 * g0, values.reduce(math.max) * 1.1);
    final g = size.height - g0 / top * size.height;
    canvas.drawLine(Offset(0, g), Offset(size.width, g), Paint()..color = Colors.grey.withValues(alpha: 0.4));
    final path = Path();
    for (var i = 0; i < raw.length; i++) {
      final x = (raw[i][0] - t0) / (t1 - t0 + 1e-9) * size.width;
      final y = size.height - values[i] / top * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, Paint()
      ..color = Palette.cyan
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4);
  }

  @override
  bool shouldRepaint(covariant _RawPainter old) => old.raw != raw;
}
