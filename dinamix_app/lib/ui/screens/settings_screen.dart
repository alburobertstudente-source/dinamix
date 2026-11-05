import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/services.dart';
import '../../ble/connection_manager.dart';
import '../../data/session_recorder.dart';
import '../../domain/units.dart';
import '../../settings/app_settings.dart';
import '../widgets/common.dart';
import 'diagnostics_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final connection = context.watch<ConnectionManager>();
    final recorder = context.watch<SessionRecorder>();
    final services = context.read<AppServices>();
    final units = settings.units;
    final device = connection.device;
    final available = connection.availableKinds.toList()
      ..sort((a, b) => a.index.compareTo(b.index));

    return Scaffold(
      appBar: AppBar(title: const Text('Impostazioni')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          const SectionTitle('Bluetooth'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Riconnessione automatica'),
                  subtitle: const Text('Ritenta dopo una perdita di collegamento'),
                  value: settings.autoReconnect,
                  onChanged: settings.setAutoReconnect,
                ),
                SwitchListTile(
                  title: const Text('Priorità alta del collegamento'),
                  subtitle: const Text(
                      'Più dati al secondo, consumo maggiore. Vale dalla prossima connessione.'),
                  value: settings.highThroughput,
                  onChanged: settings.setHighThroughput,
                ),
              ],
            ),
          ),
          const SectionTitle('Visualizzazione'),
          Card(
            child: Column(
              children: [
                _Choice<ThemeMode>(
                  title: 'Tema',
                  value: settings.themeMode,
                  options: const {
                    ThemeMode.dark: 'Scuro',
                    ThemeMode.light: 'Chiaro',
                    ThemeMode.system: 'Sistema',
                  },
                  onChanged: settings.setThemeMode,
                ),
                _Choice<int>(
                  title: 'Aggiornamento grafici',
                  value: settings.chartRefreshHz,
                  options: const {5: '5 Hz', 10: '10 Hz', 15: '15 Hz', 30: '30 Hz'},
                  onChanged: settings.setChartRefreshHz,
                ),
              ],
            ),
          ),
          const SectionTitle('Unità di misura'),
          Card(
            child: Column(
              children: [
                _Choice<AccUnit>(
                  title: 'Accelerazione',
                  value: units.acc,
                  options: const {AccUnit.mg: 'mg', AccUnit.g: 'g', AccUnit.ms2: 'm/s²'},
                  onChanged: (v) => settings.setUnits(_copy(units, acc: v)),
                ),
                _Choice<GyroUnit>(
                  title: 'Velocità angolare',
                  value: units.gyro,
                  options: const {GyroUnit.dps: 'dps', GyroUnit.rads: 'rad/s'},
                  onChanged: (v) => settings.setUnits(_copy(units, gyro: v)),
                ),
                _Choice<MagUnit>(
                  title: 'Campo magnetico',
                  value: units.mag,
                  options: const {MagUnit.mGa: 'mGa', MagUnit.uT: 'µT'},
                  onChanged: (v) => settings.setUnits(_copy(units, mag: v)),
                ),
                _Choice<TempUnit>(
                  title: 'Temperatura',
                  value: units.temp,
                  options: const {TempUnit.celsius: '°C', TempUnit.fahrenheit: '°F'},
                  onChanged: (v) => settings.setUnits(_copy(units, temp: v)),
                ),
                _Choice<PressureUnit>(
                  title: 'Pressione',
                  value: units.pressure,
                  options: const {PressureUnit.hPa: 'hPa', PressureUnit.kPa: 'kPa'},
                  onChanged: (v) => settings.setUnits(_copy(units, pressure: v)),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(
                    'Database ed esportazioni usano sempre le unità originali del protocollo.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SectionTitle('Sensori'),
          Card(
            child: available.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Collega il dispositivo per gestire i sensori disponibili.'),
                  )
                : Column(
                    children: [
                      for (final kind in available)
                        SwitchListTile(
                          title: Text(kind.label),
                          value: !settings.disabledKinds.contains(kind),
                          onChanged: (on) => settings.setKindEnabled(kind, on),
                        ),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Text(
                          'Le modifiche valgono dalla prossima connessione. La frequenza di '
                          'campionamento è fissata dal firmware: l\'app la misura ma non può cambiarla.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
          ),
          const SectionTitle('Analisi'),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Soglia picchi: ${settings.impactThresholdG.toStringAsFixed(1)} g'),
                  Slider(
                    min: 1,
                    max: 16,
                    divisions: 30,
                    value: settings.impactThresholdG.clamp(1.0, 16.0),
                    onChanged: settings.setImpactThresholdG,
                  ),
                ],
              ),
            ),
          ),
          const SectionTitle('Dati'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.delete_sweep_outlined),
              title: const Text('Elimina tutte le registrazioni'),
              enabled: !recorder.isActive,
              onTap: () => _confirmDeleteAll(context, services),
            ),
          ),
          const SectionTitle('Dispositivo'),
          Card(
            child: Column(
              children: [
                _Info('Scheda', device?.advertising?.boardName ?? 'Non connessa'),
                _Info('Firmware', device?.advertising?.firmwareLabel ?? 'Non disponibile'),
                _Info('Identificativo', device?.id ?? 'Non disponibile'),
                _Info('MTU', connection.mtu?.toString() ?? 'Non disponibile'),
              ],
            ),
          ),
          const SectionTitle('Sviluppo'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Modalità simulazione'),
                  subtitle: Text(recorder.isActive
                      ? 'Non modificabile durante una registrazione'
                      : 'Solo per provare l\'interfaccia senza la scheda. Disconnette il dispositivo.'),
                  value: settings.simulationMode,
                  onChanged: recorder.isActive ? null : services.setSimulationMode,
                ),
                ListTile(
                  leading: const Icon(Icons.troubleshoot),
                  title: const Text('Diagnostica'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute<void>(builder: (_) => const DiagnosticsScreen())),
                ),
              ],
            ),
          ),
          const SectionTitle('Applicazione'),
          const Card(child: _Info('Versione', appVersion)),
        ],
      ),
    );
  }

  static UnitPrefs _copy(
    UnitPrefs u, {
    AccUnit? acc,
    GyroUnit? gyro,
    MagUnit? mag,
    TempUnit? temp,
    PressureUnit? pressure,
  }) =>
      UnitPrefs(
        acc: acc ?? u.acc,
        gyro: gyro ?? u.gyro,
        mag: mag ?? u.mag,
        temp: temp ?? u.temp,
        pressure: pressure ?? u.pressure,
      );

  Future<void> _confirmDeleteAll(BuildContext context, AppServices services) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminare tutte le registrazioni?'),
        content: const Text('L\'operazione è definitiva.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Annulla')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Elimina')),
        ],
      ),
    );
    if (confirmed == true) {
      await services.store.deleteAll();
      services.sessionsRevision.value++;
    }
  }
}

class _Choice<T> extends StatelessWidget {
  const _Choice({
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String title;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => ListTile(
        title: Text(title),
        trailing: DropdownButton<T>(
          value: value,
          underline: const SizedBox.shrink(),
          items: [
            for (final e in options.entries)
              DropdownMenuItem<T>(value: e.key, child: Text(e.value)),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      );
}

class _Info extends StatelessWidget {
  const _Info(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        title: Text(label),
        trailing: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 200),
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      );
}