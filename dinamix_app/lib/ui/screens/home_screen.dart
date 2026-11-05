import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/dinamix_app.dart';
import '../../app/services.dart';
import '../../ble/connection_manager.dart';
import '../../ble/device_scanner.dart';
import '../../ble/transport/ble_transport.dart';
import '../../data/session_recorder.dart';
import '../../domain/sensor_kind.dart';
import '../../settings/app_settings.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/effects.dart';
import 'activity_screen.dart';
import 'diagnostics_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final connection = context.watch<ConnectionManager>();
    final scanner = context.watch<DeviceScanner>();
    final settings = context.watch<AppSettings>();
    final recorder = context.watch<SessionRecorder>();
    final nav = context.read<NavController>();
    final services = context.read<AppServices>();

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 18,
        title: const Row(
          children: [
            DinamixLogo(size: 34),
            SizedBox(width: 11),
            Text('DinamiX'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Diagnostica',
            icon: const Icon(Icons.troubleshoot_rounded),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => const DiagnosticsScreen())),
          ),
          IconButton(
            tooltip: 'Impostazioni',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
        children: [
          FadeSlideIn(child: _Hero(connection: connection, settings: settings, services: services)),
          const SizedBox(height: 16),
          FadeSlideIn(
            index: 1,
            child: Row(
              children: [
                Expanded(child: _BluetoothTile(status: scanner.adapterStatus, scanner: scanner)),
                const SizedBox(width: 12),
                const Expanded(child: _BatteryTile()),
              ],
            ),
          ),
          if (recorder.isActive) ...[
            const SizedBox(height: 12),
            FadeSlideIn(
              child: Card(
                child: ListTile(
                  leading: const Icon(Icons.fiber_manual_record, color: Palette.danger),
                  title: Text(recorder.sessionName),
                  subtitle: Text(recorder.state == RecorderState.paused
                      ? 'In pausa'
                      : 'Registrazione in corso'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => nav.go(NavController.logger),
                ),
              ),
            ),
          ],
          const SectionTitle('Sensori attivi'),
          FadeSlideIn(index: 2, child: _ActiveSensors(connection: connection, services: services)),
          const SectionTitle('Accesso rapido'),
          FadeSlideIn(
            index: 3,
            child: Row(
              children: [
                Expanded(
                  child: _QuickAction(
                    icon: Icons.show_chart_rounded,
                    label: 'Live',
                    onTap: () => nav.go(NavController.live),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _QuickAction(
                    icon: Icons.radio_button_checked_rounded,
                    label: 'Registra',
                    onTap: () => nav.go(NavController.logger),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _QuickAction(
                    icon: Icons.analytics_rounded,
                    label: 'Analisi',
                    onTap: () => nav.go(NavController.analysis),
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

class _Hero extends StatelessWidget {
  const _Hero({required this.connection, required this.settings, required this.services});

  final ConnectionManager connection;
  final AppSettings settings;
  final AppServices services;

  Future<void> _startDemo(BuildContext context) async {
    final navigator = Navigator.of(context);
    if (await services.enterPhoneDemo()) {
      navigator.push(MaterialPageRoute<void>(builder: (_) => const ActivityScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final nav = context.read<NavController>();
    final phase = connection.phase;
    final known = settings.knownDevices.isEmpty ? null : settings.knownDevices.first;
    final shown = phase == ConnectionPhase.idle ? null : connection.device;
    final isPhone = connection.dataSource == DataSource.phone;

    final (IconData icon, Color color, String title) = switch (phase) {
      ConnectionPhase.ready => isPhone
          ? (Icons.smartphone_rounded, Palette.cyan, 'Sensori del telefono attivi')
          : (Icons.verified_user_rounded, Palette.ok, 'Sensore connesso'),
      ConnectionPhase.connecting => (Icons.bluetooth_searching_rounded, Palette.cyan, 'Connessione…'),
      ConnectionPhase.discovering => (Icons.manage_search_rounded, Palette.cyan, 'Lettura servizi…'),
      ConnectionPhase.subscribing => (Icons.sensors_rounded, Palette.cyan, 'Attivazione sensori…'),
      ConnectionPhase.reconnecting => (
          Icons.sync_rounded,
          Palette.warning,
          'Riconnessione, tentativo ${connection.reconnectAttempt}…'
        ),
      ConnectionPhase.failed => (Icons.error_outline_rounded, Palette.danger, 'Connessione non riuscita'),
      ConnectionPhase.idle => (Icons.bluetooth_disabled_rounded, muted, 'Sensore non connesso'),
    };

    final String subtitle;
    if (shown != null && !isPhone) {
      subtitle = shown.advertising?.firmwareLabel ?? shown.name;
    } else if (isPhone && phase == ConnectionPhase.ready) {
      subtitle = 'Muovi il telefono: i dati sono reali, ma non vengono dalla SensorTile';
    } else if (known != null) {
      subtitle = 'Ultima connessione: ${known.name}, ${formatRelative(known.lastConnectedMs)}';
    } else {
      subtitle = 'Collega la tua SensorTile.box PRO';
    }

    return Column(
      children: [
        const SizedBox(height: 4),
        StatusOrb(
          icon: icon,
          color: color,
          active: connection.isReady,
          spinning: connection.isBusy,
        ),
        const SizedBox(height: 4),
        KeyedSwitcher(
          value: title,
          duration: const Duration(milliseconds: 300),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.4),
          ),
        ),
        const SizedBox(height: 6),
        Text(subtitle, textAlign: TextAlign.center, style: TextStyle(color: muted)),
        const SizedBox(height: 20),
        if (connection.isReady) ...[
          GradientButton(
            label: 'Inizia sessione',
            icon: Icons.play_arrow_rounded,
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => const ActivityScreen())),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.link_off_rounded),
              label: Text(isPhone ? 'Esci dalla demo' : 'Disconnetti'),
              onPressed: isPhone ? services.exitPhoneDemo : connection.disconnect,
            ),
          ),
        ] else if (connection.isBusy)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: isPhone ? services.exitPhoneDemo : connection.disconnect,
              child: const Text('Annulla'),
            ),
          )
        else ...[
          GradientButton(
            label: 'Connetti sensore',
            icon: Icons.bluetooth_rounded,
            onPressed: () async {
              final scanner = context.read<DeviceScanner>();
              // A failed demo must not leave the phone as the data source.
              if (settings.phoneDemo) await services.exitPhoneDemo();
              nav.go(NavController.devices);
              scanner.start();
            },
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.smartphone_rounded),
              label: const Text('Modalità demo'),
              onPressed: () => _startDemo(context),
            ),
          ),
          if (known != null && !connection.isDemo) ...[
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => services.connectTo(DeviceRef(known.id, known.name)),
              child: Text('Ricollega ${known.name}', overflow: TextOverflow.ellipsis),
            ),
          ],
        ],
      ],
    );
  }
}

class _BluetoothTile extends StatelessWidget {
  const _BluetoothTile({required this.status, required this.scanner});

  final AdapterStatus status;
  final DeviceScanner scanner;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      AdapterStatus.on => ('Attivo', Palette.ok),
      AdapterStatus.off => ('Spento', Palette.danger),
      AdapterStatus.turningOn => ('In attivazione', Palette.warning),
      AdapterStatus.turningOff => ('In spegnimento', Palette.warning),
      AdapterStatus.unauthorized => ('Non autorizzato', Palette.danger),
      AdapterStatus.unsupported => ('Non supportato', Palette.danger),
      AdapterStatus.unknown => ('Sconosciuto', Palette.warning),
    };
    return _InfoTile(
      icon: Icons.bluetooth_rounded,
      title: 'Bluetooth',
      value: label,
      valueColor: color,
      onTap: status == AdapterStatus.off || status == AdapterStatus.unauthorized
          ? scanner.turnOnBluetooth
          : null,
    );
  }
}

class _BatteryTile extends StatelessWidget {
  const _BatteryTile();

  @override
  Widget build(BuildContext context) {
    final services = context.read<AppServices>();
    return ListenableBuilder(
      listenable: services.hub.frame,
      builder: (context, _) {
        final battery = services.hub.latest(SensorKind.battery);
        final fresh = services.hub.isReceiving(SensorKind.battery);
        if (battery == null || !fresh) {
          return const _InfoTile(
              icon: Icons.battery_unknown_rounded, title: 'Batteria', value: 'Non disponibile');
        }
        final level = battery.values[0];
        final status = battery.values[3].toInt();
        return _InfoTile(
          icon: status == 3 ? Icons.battery_charging_full_rounded : Icons.battery_full_rounded,
          title: 'Batteria',
          value: '${level.toStringAsFixed(0)} %',
          valueColor: level < 15 ? Palette.danger : null,
        );
      },
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.title,
    required this.value,
    this.valueColor,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final Color? valueColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PressScale(
      onTap: onTap,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: theme.colorScheme.primary),
              const SizedBox(height: 12),
              Text(title,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 2),
              KeyedSwitcher(
                value: value,
                duration: const Duration(milliseconds: 250),
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700, color: valueColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveSensors extends StatelessWidget {
  const _ActiveSensors({required this.connection, required this.services});

  final ConnectionManager connection;
  final AppServices services;

  @override
  Widget build(BuildContext context) {
    final kinds = connection.activeKinds.toList()..sort((a, b) => a.index.compareTo(b.index));
    final scheme = Theme.of(context).colorScheme;
    if (!connection.isReady || kinds.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Text(
            'Collega il dispositivo per vedere i sensori resi disponibili dal firmware.',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: ListenableBuilder(
          listenable: services.hub.frame,
          builder: (context, _) => Column(
            children: [
              for (final kind in kinds)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  child: Row(
                    children: [
                      StatusDot(
                        services.hub.isReceiving(kind) ? Palette.ok : scheme.outlineVariant,
                        size: 8,
                      ),
                      const SizedBox(width: 11),
                      Expanded(child: Text(kind.label)),
                      Text('${services.hub.rateHz(kind).toStringAsFixed(1)} Hz',
                          style: numericStyle.copyWith(
                              fontSize: 13, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PressScale(
        onTap: onTap,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: Column(
                children: [
                  Icon(icon, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 8),
                  Text(label, style: Theme.of(context).textTheme.labelMedium),
                ],
              ),
            ),
          ),
        ),
      );
}
