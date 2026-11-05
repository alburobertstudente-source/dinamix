import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/dinamix_app.dart';
import '../../../app/services.dart';
import '../../../ble/connection_manager.dart';
import '../../../monitoring/monitoring_service.dart';
import '../../../profile/profile.dart';
import '../../../settings/app_settings.dart';
import '../../brand/logo.dart';
import '../../detection_ui.dart';
import '../../format.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/effects.dart';
import '../../widgets/mountain_scene.dart';
import '../activity_screen.dart';
import '../settings_screen.dart';
import 'contact_screen.dart';
import 'detection_screen.dart';
import 'events_screen.dart';

/// Main dashboard (specification §13): state of DYNAMIX and of the monitoring,
/// current risk, sensors, last event, emergency contact. No technical values.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  void _push(BuildContext context, Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final monitoring = context.watch<MonitoringService>();
    final settings = context.watch<AppSettings>();
    final profiles = context.watch<ProfileService>();
    final connection = context.watch<ConnectionManager>();
    final nav = context.read<NavController>();
    final level = monitoring.currentLevel.value;
    final last = monitoring.recent.isEmpty ? null : monitoring.recent.first;
    final name = profiles.profile?.firstName;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 18,
        title: const DynamixLockup(height: 30),
        actions: [
          IconButton(
            tooltip: 'Storico eventi',
            icon: const Icon(Icons.history_rounded),
            onPressed: () => _push(context, const EventsScreen()),
          ),
          IconButton(
            tooltip: 'Impostazioni',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => _push(context, const SettingsScreen()),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 28),
        children: [
          Stack(
            children: [
              MountainScene(
                level: settings.animationLevel,
                paused: level >= 3,
                height: 250,
              ),
              // Contrast veil: texts over the scene stay readable (WCAG AA).
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.15),
                        Theme.of(context).scaffoldBackgroundColor,
                      ],
                      stops: const [0, 0.55, 1],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 18,
                right: 18,
                bottom: 4,
                child: Text(
                  name == null ? 'Ciao' : 'Ciao, $name',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FadeSlideIn(child: _StatusCard(monitoring: monitoring, settings: settings, connection: connection)),
                const SizedBox(height: 14),
                FadeSlideIn(
                  index: 1,
                  child: Row(
                    children: [
                      Expanded(
                        child: _Tile(
                          icon: settings.detectionMode == DetectionMode.sensorTile
                              ? Icons.sensors_rounded
                              : Icons.smartphone_rounded,
                          title: 'Modalità',
                          value: settings.detectionMode == DetectionMode.sensorTile ? 'SensorTile' : 'Telefono',
                          onTap: () => _push(context, const SettingsScreen()),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Tile(
                          icon: Icons.contact_phone_outlined,
                          title: 'Contatto',
                          value: profiles.contactReady ? profiles.contact!.name : 'Non configurato',
                          valueColor: profiles.contactReady ? null : Palette.warning,
                          onTap: () => _push(context, const ContactScreen()),
                        ),
                      ),
                    ],
                  ),
                ),
                const SectionTitle('Ultimo evento'),
                FadeSlideIn(
                  index: 2,
                  child: Card(
                    child: last == null
                        ? const ListTile(
                            leading: Icon(Icons.check_circle_outline_rounded, color: Palette.ok),
                            title: Text('Nessun evento registrato'),
                            subtitle: Text('Gli eventi anomali compaiono qui e nello storico.'),
                          )
                        : ListTile(
                            leading: Icon(categoryIcon(last.category), color: levelColor(last.level)),
                            title: Text(categoryLabel(last.category)),
                            subtitle: Text('${formatRelative(last.atMs)} · confidenza ${(last.confidence * 100).round()}/100'),
                            trailing: LevelBadge(last.level),
                            onTap: () => _push(context, EventDetailScreen(id: last.id!)),
                          ),
                  ),
                ),
                const SectionTitle('Accesso rapido'),
                FadeSlideIn(
                  index: 3,
                  child: GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.15,
                    children: [
                      _Quick(Icons.monitor_heart_outlined, 'Diagnostica', () => _push(context, const DetectionScreen())),
                      _Quick(Icons.history_rounded, 'Storico', () => _push(context, const EventsScreen())),
                      _Quick(Icons.downhill_skiing_rounded, 'Attività', () => _push(context, const ActivityScreen())),
                      _Quick(Icons.show_chart_rounded, 'Live', () => nav.go(NavController.live)),
                      _Quick(Icons.radio_button_checked_rounded, 'Registra', () => nav.go(NavController.logger)),
                      _Quick(Icons.tune_rounded, 'Impostazioni', () => _push(context, const SettingsScreen())),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatefulWidget {
  const _StatusCard({required this.monitoring, required this.settings, required this.connection});

  final MonitoringService monitoring;
  final AppSettings settings;
  final ConnectionManager connection;

  @override
  State<_StatusCard> createState() => _StatusCardState();
}

class _StatusCardState extends State<_StatusCard> {
  bool _busy = false;

  Future<void> _toggle() async {
    final services = context.read<AppServices>();
    final messenger = ScaffoldMessenger.of(context);
    final nav = context.read<NavController>();
    setState(() => _busy = true);
    try {
      if (widget.monitoring.running) {
        await services.stopMonitoring();
      } else {
        final error = await services.startMonitoring();
        if (error != null) {
          messenger.showSnackBar(SnackBar(
            content: Text(error),
            action: widget.settings.detectionMode == DetectionMode.sensorTile
                ? SnackBarAction(label: 'Sensori', onPressed: () => nav.go(NavController.devices))
                : null,
          ));
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.monitoring;
    final level = m.currentLevel;
    final color = m.running ? levelColor(level.value) : Theme.of(context).colorScheme.onSurfaceVariant;
    final q = m.running && m.hasData ? m.quality : null;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final simulated = m.sourceIsSimulated && m.running;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                StatusDot(m.running ? color : muted, size: 10),
                const SizedBox(width: 8),
                Text(m.running ? 'Monitoraggio attivo' : 'Monitoraggio fermo',
                    style: TextStyle(color: muted, fontWeight: FontWeight.w600)),
                const Spacer(),
                if (m.running) LevelBadge(level.value),
              ],
            ),
            const SizedBox(height: 10),
            KeyedSwitcher(
              value: m.running ? level.value : -1,
              duration: const Duration(milliseconds: 260),
              child: Text(
                m.running ? level.label : 'Avvia il monitoraggio per analizzare i movimenti',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: m.running ? color : null),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              m.running
                  ? (m.hasData
                      ? '${m.engine.profile.name}${simulated ? ' (simulazione)' : ''} · '
                          '${q!.rateHz.toStringAsFixed(0)} Hz · qualità ${(q.value * 100).round()}/100'
                      : 'In attesa dei dati dei sensori…')
                  : widget.settings.detectionMode == DetectionMode.sensorTile
                      ? (widget.connection.isReady && !widget.connection.isDemo
                          ? 'SensorTile collegata'
                          : 'Collega la SensorTile dalla scheda Sensori')
                      : 'Sensori del telefono',
              style: TextStyle(color: muted),
            ),
            const SizedBox(height: 16),
            GradientButton(
              key: const Key('monitoring_toggle'),
              label: m.running ? 'Ferma monitoraggio' : 'Avvia monitoraggio',
              icon: m.running ? Icons.stop_rounded : Icons.play_arrow_rounded,
              colors: m.running ? const [Color(0xFFFF6B7A), Color(0xFFE5364B)] : Palette.brandGradient,
              onPressed: _busy ? null : _toggle,
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.title, required this.value, this.valueColor, this.onTap});

  final IconData icon;
  final String title;
  final String value;
  final Color? valueColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: onTap != null,
      label: '$title: $value',
      child: PressScale(
        onTap: onTap,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 20, color: theme.colorScheme.primary),
                  const SizedBox(height: 12),
                  Text(title, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 2),
                  Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: valueColor)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Quick extends StatelessWidget {
  const _Quick(this.icon, this.label, this.onTap);

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: PressScale(
          onTap: onTap,
          child: Card(
            margin: EdgeInsets.zero,
            child: ExcludeSemantics(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 8),
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                ],
              ),
            ),
          ),
        ),
      );
}
