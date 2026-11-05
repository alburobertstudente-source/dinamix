import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../analysis/series_analysis.dart';
import '../../app/dinamix_app.dart';
import '../../app/services.dart';
import '../../core/app_error.dart';
import '../../data/session_recorder.dart';
import '../../domain/sensor_kind.dart';
import '../../domain/session.dart';
import '../../domain/units.dart';
import '../../settings/app_settings.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';

class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({super.key});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  List<SessionInfo> _sessions = const [];
  SessionInfo? _session;
  List<SensorKind> _kinds = const [];
  SensorKind? _kind;
  SensorKind? _compareKind;
  int _compareChannel = 0;
  KindAnalysis? _analysis;
  KindAnalysis? _comparison;
  bool _loading = true;
  int _requestToken = 0;
  double? _analyzedThresholdG;

  late final ValueNotifier<int> _revision;
  NavController? _nav;
  SessionRecorder? _recorder;
  RecorderState? _recorderState;

  AppServices get _services => context.read<AppServices>();

  @override
  void initState() {
    super.initState();
    _revision = context.read<AppServices>().sessionsRevision..addListener(_onRevision);
    _loadSessions();
  }

  void _onRevision() => _loadSessions();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nav = context.read<NavController>();
    if (_nav != nav) {
      _nav?.removeListener(_onNav);
      _nav = nav..addListener(_onNav);
    }
    final recorder = context.read<SessionRecorder>();
    if (_recorder != recorder) {
      _recorder?.removeListener(_onRecorder);
      _recorder = recorder..addListener(_onRecorder);
      _recorderState = recorder.state;
    }
  }

  void _onNav() {
    final nav = _nav;
    if (nav == null) return;
    if (nav.index == NavController.analysis) {
      final requested = nav.analysisSessionId;
      nav.analysisSessionId = null;
      _loadSessions(select: requested);
    }
  }

  /// A session that has just ended becomes available without reopening the app.
  void _onRecorder() {
    final recorder = _recorder;
    if (recorder == null || recorder.state == _recorderState) return;
    _recorderState = recorder.state;
    if (recorder.state == RecorderState.idle) _loadSessions();
  }

  @override
  void dispose() {
    _revision.removeListener(_onRevision);
    _nav?.removeListener(_onNav);
    _recorder?.removeListener(_onRecorder);
    super.dispose();
  }

  Future<void> _loadSessions({int? select}) async {
    final all = await _services.store.listSessions();
    if (!mounted) return;
    final activeId = _recorder?.sessionId;
    final sessions = all.where((s) => s.id != activeId && s.sampleCount > 0).toList();
    SessionInfo? chosen;
    final wanted = select ?? _session?.id;
    for (final s in sessions) {
      if (s.id == wanted) chosen = s;
    }
    chosen ??= sessions.isEmpty ? null : sessions.first;
    setState(() {
      _sessions = sessions;
      _loading = false;
    });
    if (chosen?.id != _session?.id || select != null) {
      await _selectSession(chosen);
    }
  }

  Future<void> _selectSession(SessionInfo? session) async {
    setState(() {
      _session = session;
      _kinds = const [];
      _kind = null;
      _compareKind = null;
      _analysis = null;
      _comparison = null;
    });
    if (session == null) return;
    final stored = await _services.store.kindsIn(session.id);
    if (!mounted || _session?.id != session.id) return;
    // Categories (activity, switch) have no meaningful statistics.
    final kinds = stored.where((k) => !k.isCategorical).toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    setState(() => _kinds = kinds);
    if (kinds.isNotEmpty) await _selectKind(kinds.first);
  }

  Future<void> _selectKind(SensorKind kind) async {
    setState(() {
      _kind = kind;
      _analysis = null;
    });
    await _run();
  }

  Future<void> _run() async {
    final session = _session;
    final kind = _kind;
    if (session == null || kind == null) return;
    final token = ++_requestToken;
    setState(() => _loading = true);
    final settings = context.read<AppSettings>();
    final end = session.endedAtMs ?? session.startedAtMs + 1;
    final store = _services.store;
    final thresholdG = settings.impactThresholdG;
    final KindAnalysis analysis;
    KindAnalysis? comparison;
    try {
      analysis = await analyzeKind(
        store: store,
        sessionId: session.id,
        kind: kind,
        startMs: session.startedAtMs,
        endMs: end,
        impactThresholdMg: thresholdG * 1000,
      );
      final compare = _compareKind;
      if (compare != null) {
        comparison = await analyzeKind(
          store: store,
          sessionId: session.id,
          kind: compare,
          startMs: session.startedAtMs,
          endMs: end,
        );
      }
    } catch (e) {
      ErrorCenter.instance.reportAny(e, tag: 'Analisi', message: 'Analisi non riuscita');
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (!mounted || token != _requestToken) return;
    setState(() {
      _analysis = analysis;
      _comparison = comparison;
      _analyzedThresholdG = thresholdG;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final units = settings.units;
    final analysis = _analysis;
    final session = _session;
    // The threshold may have been changed in the settings.
    if (analysis != null &&
        !_loading &&
        _analyzedThresholdG != null &&
        _analyzedThresholdG != settings.impactThresholdG) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _run();
      });
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Analisi')),
      body: _sessions.isEmpty && !_loading
          ? const EmptyState(
              icon: Icons.analytics_outlined,
              title: 'Nessuna sessione da analizzare',
              message: 'Le registrazioni concluse del Data Logger compaiono qui.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                DropdownButtonFormField<int>(
                  key: ValueKey('session-${session?.id}'),
                  isExpanded: true,
                  // ignore: deprecated_member_use, the selection changes from outside the field.
                  value: session?.id,
                  decoration: const InputDecoration(labelText: 'Sessione'),
                  items: [
                    for (final s in _sessions)
                      DropdownMenuItem(
                        value: s.id,
                        child: Text(
                          '${s.sourceTag == null ? '' : '[${s.sourceTag}] '}${s.name}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (id) {
                    if (id == null) return;
                    _selectSession(_sessions.firstWhere((s) => s.id == id));
                  },
                ),
                if (session != null) ...[
                  const SizedBox(height: 10),
                  _SessionSummary(session: session),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<SensorKind>(
                          key: ValueKey('kind-${session.id}-$_kind'),
                          isExpanded: true,
                          // ignore: deprecated_member_use, the selection changes from outside the field.
                          value: _kind,
                          decoration: const InputDecoration(labelText: 'Sensore'),
                          items: [
                            for (final k in _kinds)
                              DropdownMenuItem(value: k, child: Text(k.label)),
                          ],
                          onChanged: (k) {
                            if (k != null) _selectKind(k);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          key: ValueKey('cmp-${session.id}-$_compareKind-$_compareChannel'),
                          isExpanded: true,
                          // ignore: deprecated_member_use, the selection changes from outside the field.
                          value: _compareKind == null ? 'none' : '${_compareKind!.id}/$_compareChannel',
                          decoration: const InputDecoration(labelText: 'Confronta con'),
                          items: [
                            const DropdownMenuItem(value: 'none', child: Text('Nessuno')),
                            for (final k in _kinds)
                              for (var c = 0; c < k.channels.length; c++)
                                DropdownMenuItem(
                                  value: '${k.id}/$c',
                                  child: Text('${k.label} ${k.channels[c].label}',
                                      overflow: TextOverflow.ellipsis),
                                ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            if (value == 'none') {
                              setState(() => _compareKind = null);
                            } else {
                              final parts = value.split('/');
                              _compareKind = SensorKind.fromId(parts[0]);
                              _compareChannel = int.parse(parts[1]);
                            }
                            _run();
                          },
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                if (_loading) const LinearProgressIndicator(minHeight: 2),
                if (analysis != null) ...[
                  _ChartCard(
                    analysis: analysis,
                    comparison: _comparison,
                    compareChannel: _compareChannel,
                    units: units,
                  ),
                  const SectionTitle('Statistiche'),
                  _StatsTable(analysis: analysis, units: units),
                  if (analysis.peaks != null) ...[
                    const SectionTitle('Picchi di accelerazione'),
                    _PeaksCard(
                      analysis: analysis,
                      thresholdG: settings.impactThresholdG,
                    ),
                  ],
                ],
              ],
            ),
    );
  }
}

class _SessionSummary extends StatelessWidget {
  const _SessionSummary({required this.session});

  final SessionInfo session;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          '${formatDateTime(session.startedAtMs)} · ${formatDuration(session.duration)} · '
          '${formatCount(session.sampleCount)} campioni',
          style: TextStyle(color: color, fontSize: 12),
        ),
        if (session.sourceTag != null) TagChip(session.sourceTag!, color: Palette.simulation),
      ],
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.analysis,
    required this.comparison,
    required this.compareChannel,
    required this.units,
  });

  final KindAnalysis analysis;
  final KindAnalysis? comparison;
  final int compareChannel;
  final UnitPrefs units;

  @override
  Widget build(BuildContext context) {
    final kind = analysis.kind;
    final compare = comparison;
    final series = <SeriesChartData>[
      for (var i = 0; i < analysis.channels.length; i++)
        SeriesChartData(
          analysis.channels[i].label,
          analysis.channels[i].bins,
          Palette.axes[i % Palette.axes.length],
          convert: (v) => units.convert(kind, analysis.channels[i].channel ?? 0, v),
        ),
      if (compare != null)
        SeriesChartData(
          '${compare.kind.label} ${compare.channels[compareChannel].label}',
          compare.channels[compareChannel].bins,
          Theme.of(context).colorScheme.onSurface,
          convert: (v) => units.convert(compare.kind, compareChannel, v),
        ),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SessionChart(
              series: series,
              decimals: units.decimals(kind, 0),
              independentScales: compare != null,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                for (final s in series)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      StatusDot(s.color, size: 8),
                      const SizedBox(width: 5),
                      Text(s.label, style: const TextStyle(fontSize: 12)),
                    ],
                  ),
              ],
            ),
            if (compare != null) ...[
              const SizedBox(height: 6),
              Text(
                'Con il confronto ogni curva ha la propria scala: si confronta la forma, non l\'ampiezza.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatsTable extends StatelessWidget {
  const _StatsTable({required this.analysis, required this.units});

  final KindAnalysis analysis;
  final UnitPrefs units;

  @override
  Widget build(BuildContext context) {
    final kind = analysis.kind;

    String value(int channel, double v) => units.format(kind, channel, v);

    // Spreads and differences have no offset: °C to °F must scale only.
    String spread(int channel, double v) {
      if (v.isNaN) return '—';
      final scaled = units.convert(kind, channel, v) - units.convert(kind, channel, 0);
      return scaled.toStringAsFixed(units.decimals(kind, channel));
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 20,
          horizontalMargin: 14,
          headingRowHeight: 38,
          dataRowMinHeight: 34,
          dataRowMaxHeight: 38,
          columns: const [
            DataColumn(label: Text('Canale')),
            DataColumn(label: Text('Min'), numeric: true),
            DataColumn(label: Text('Max'), numeric: true),
            DataColumn(label: Text('Media'), numeric: true),
            DataColumn(label: Text('Dev. std'), numeric: true),
            DataColumn(label: Text('Var. media'), numeric: true),
            DataColumn(label: Text('Var. max'), numeric: true),
          ],
          rows: [
            for (final c in analysis.channels)
              if (c.stats.count > 0)
                DataRow(cells: [
                  DataCell(Text(
                      '${c.label} (${units.unit(kind, c.channel ?? 0)})'.replaceAll(' ()', ''))),
                  DataCell(Text(value(c.channel ?? 0, c.stats.min))),
                  DataCell(Text(value(c.channel ?? 0, c.stats.max))),
                  DataCell(Text(value(c.channel ?? 0, c.stats.mean))),
                  DataCell(Text(spread(c.channel ?? 0, c.stats.stdDev))),
                  DataCell(Text(spread(c.channel ?? 0, c.stats.meanAbsDelta))),
                  DataCell(Text(spread(c.channel ?? 0, c.stats.maxAbsDelta))),
                ]),
          ],
        ),
      ),
    );
  }
}

class _PeaksCard extends StatelessWidget {
  const _PeaksCard({required this.analysis, required this.thresholdG});

  final KindAnalysis analysis;
  final double thresholdG;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final peaks = analysis.peaks!.peaks;
    final top = [...peaks]..sort((a, b) => b.value.compareTo(a.value));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${peaks.length} picchi oltre ${thresholdG.toStringAsFixed(1)} g',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            for (final p in top.take(5))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '${formatTime(p.atMs)}   ${(p.value / 1000).toStringAsFixed(2)} g',
                  style: numericStyle.copyWith(fontWeight: FontWeight.w500),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'Analisi sperimentale, non un rilevamento di caduta certificato. La soglia si cambia '
              'nelle Impostazioni. Il flusso BLE è campionato dal firmware: picchi molto brevi possono '
              'risultare attenuati o assenti.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
