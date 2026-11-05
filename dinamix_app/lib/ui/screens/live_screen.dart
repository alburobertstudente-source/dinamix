import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/dinamix_app.dart';
import '../../app/services.dart';
import '../../ble/connection_manager.dart';
import '../../data/sensor_hub.dart';
import '../../domain/sensor_kind.dart';
import '../../domain/units.dart';
import '../../settings/app_settings.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/effects.dart';

class LiveScreen extends StatelessWidget {
  const LiveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final connection = context.watch<ConnectionManager>();
    final settings = context.watch<AppSettings>();
    final hub = context.read<AppServices>().hub;
    final available = connection.availableKinds.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    final missing = SensorKind.values.where((k) => !available.contains(k)).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: 5, label: Text('5s')),
                ButtonSegment(value: 10, label: Text('10s')),
                ButtonSegment(value: 30, label: Text('30s')),
                ButtonSegment(value: 60, label: Text('60s')),
              ],
              selected: {settings.chartWindowSeconds},
              onSelectionChanged: (s) => settings.setChartWindowSeconds(s.first),
            ),
          ),
        ],
      ),
      body: available.isEmpty
          ? EmptyState(
              icon: Icons.sensors_off,
              title: connection.isBusy ? 'Connessione in corso' : 'Nessun dispositivo connesso',
              message: 'I dati in tempo reale compaiono qui dopo la connessione.',
              action: connection.isBusy
                  ? null
                  : FilledButton(
                      onPressed: () => context.read<NavController>().go(NavController.devices),
                      child: const Text('Vai a Dispositivi'),
                    ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemCount: available.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                if (index == available.length) return _Unavailable(kinds: missing);
                final kind = available[index];
                return FadeSlideIn(
                  key: ValueKey(kind),
                  index: index,
                  child: _SensorCard(
                    kind: kind,
                    hub: hub,
                    units: settings.units,
                    windowMs: settings.chartWindowSeconds * 1000,
                    enabled: !settings.disabledKinds.contains(kind),
                    linkUp: connection.isReady,
                  ),
                );
              },
            ),
    );
  }
}

class _SensorCard extends StatelessWidget {
  const _SensorCard({
    required this.kind,
    required this.hub,
    required this.units,
    required this.windowMs,
    required this.enabled,
    required this.linkUp,
  });

  final SensorKind kind;
  final SensorHub hub;
  final UnitPrefs units;
  final int windowMs;
  final bool enabled;
  final bool linkUp;

  /// Single chart channels: the others are numbers only.
  List<int> get _chartChannels => switch (kind) {
        SensorKind.quaternion => const [0, 1, 2, 3],
        SensorKind.euler => const [0, 1, 2],
        _ => const [0],
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListenableBuilder(
              listenable: hub.frame,
              builder: (context, _) {
                final receiving = hub.isReceiving(kind);
                return Row(
                  children: [
                    StatusDot(!enabled
                        ? theme.colorScheme.outlineVariant
                        : (receiving ? Palette.ok : Palette.warning)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(kind.label,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                    ),
                    Text(
                      !enabled
                          ? 'Disattivato'
                          : (receiving
                              ? '${hub.rateHz(kind).toStringAsFixed(1)} Hz'
                              : (linkUp ? 'In attesa di dati' : 'Collegamento assente')),
                      style: numericStyle.copyWith(
                          fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                );
              },
            ),
            if (enabled) ...[
              const SizedBox(height: 12),
              if (kind.isTriaxial)
                for (var c = 0; c < 3; c++) ...[
                  _Value(hub: hub, kind: kind, channel: c, units: units, windowMs: windowMs),
                  const SizedBox(height: 4),
                  LiveChart(
                    hub: hub,
                    kind: kind,
                    channels: [c],
                    colors: [Palette.axes[c]],
                    windowMs: windowMs,
                    units: units,
                    height: 84,
                  ),
                  if (c < 2) const SizedBox(height: 10),
                ]
              else if (kind.isCategorical)
                _CategoricalValue(hub: hub, kind: kind)
              else ...[
                _Values(hub: hub, kind: kind, units: units, windowMs: windowMs),
                const SizedBox(height: 8),
                LiveChart(
                  hub: hub,
                  kind: kind,
                  channels: _chartChannels,
                  colors: Palette.axes,
                  windowMs: windowMs,
                  units: units,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _Value extends StatelessWidget {
  const _Value({
    required this.hub,
    required this.kind,
    required this.channel,
    required this.units,
    required this.windowMs,
  });

  final SensorHub hub;
  final SensorKind kind;
  final int channel;
  final UnitPrefs units;
  final int windowMs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: hub.frame,
      builder: (context, _) {
        final latest = hub.latest(kind);
        final value = latest == null ? double.nan : latest.values[channel];
        final stats = hub.windowStats(kind, channel, windowMs);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(kind.channels[channel].label,
                style: TextStyle(color: Palette.axes[channel % 4], fontWeight: FontWeight.w700)),
            const SizedBox(width: 10),
            Text(units.format(kind, channel, value), style: numericStyle.copyWith(fontSize: 18)),
            const SizedBox(width: 4),
            Text(units.unit(kind, channel),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const Spacer(),
            Text(
              'min ${units.format(kind, channel, stats.min)}  max ${units.format(kind, channel, stats.max)}',
              style: numericStyle.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Values extends StatelessWidget {
  const _Values({
    required this.hub,
    required this.kind,
    required this.units,
    required this.windowMs,
  });

  final SensorHub hub;
  final SensorKind kind;
  final UnitPrefs units;
  final int windowMs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: hub.frame,
      builder: (context, _) {
        final latest = hub.latest(kind);
        return Wrap(
          spacing: 18,
          runSpacing: 6,
          children: [
            for (var c = 0; c < kind.channels.length; c++)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(kind.channels[c].label,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  Text(
                    _text(latest, c),
                    style: numericStyle.copyWith(fontSize: 18),
                  ),
                ],
              ),
          ],
        );
      },
    );
  }

  String _text(SensorReading? latest, int c) {
    if (latest == null || c >= latest.values.length) return '—';
    final value = latest.values[c];
    if (kind == SensorKind.battery && c == 3) return batteryStatusLabel(value.toInt());
    final unit = units.unit(kind, c);
    final text = units.format(kind, c, value);
    return unit.isEmpty ? text : '$text $unit';
  }
}

class _CategoricalValue extends StatelessWidget {
  const _CategoricalValue({required this.hub, required this.kind});

  final SensorHub hub;
  final SensorKind kind;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: hub.frame,
        builder: (context, _) {
          final latest = hub.latest(kind);
          var text = '—';
          if (latest != null) {
            final code = latest.values[0].toInt();
            text = kind == SensorKind.activity
                ? activityLabel(code)
                : (code == 1 ? 'Acceso' : (code == 0 ? 'Spento' : 'Errore'));
          }
          return Text(text,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600));
        },
      );
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.kinds});

  final List<SensorKind> kinds;

  @override
  Widget build(BuildContext context) {
    if (kinds.isEmpty) return const SizedBox.shrink();
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Text(
        'Non disponibili con il firmware attuale: ${kinds.map((k) => k.label).join(', ')}.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
      ),
    );
  }
}
