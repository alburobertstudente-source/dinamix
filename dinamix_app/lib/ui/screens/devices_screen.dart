import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/services.dart';
import '../../ble/connection_manager.dart';
import '../../ble/device_scanner.dart';
import '../../ble/transport/ble_transport.dart';
import '../../settings/app_settings.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/effects.dart';

class DevicesScreen extends StatelessWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scanner = context.watch<DeviceScanner>();
    final connection = context.watch<ConnectionManager>();
    final settings = context.watch<AppSettings>();
    final services = context.read<AppServices>();
    final results = scanner.visibleResults;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dispositivi'),
        bottom: scanner.isScanning
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: Icon(scanner.isScanning ? Icons.stop : Icons.radar),
        label: Text(scanner.isScanning ? 'Ferma' : 'Cerca'),
        onPressed: scanner.isScanning ? scanner.stop : scanner.start,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
        children: [
          if (scanner.adapterStatus == AdapterStatus.off)
            Card(
              child: ListTile(
                leading: const Icon(Icons.bluetooth_disabled, color: Palette.danger),
                title: const Text('Bluetooth spento'),
                trailing: TextButton(
                  onPressed: scanner.turnOnBluetooth,
                  child: const Text('Attiva'),
                ),
              ),
            ),
          if (connection.phase != ConnectionPhase.idle && connection.device != null)
            _CurrentDevice(connection: connection),
          SectionTitle(
            'Dispositivi trovati',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Solo BlueST', style: TextStyle(fontSize: 12)),
                Switch(
                  value: scanner.onlyBlueSt,
                  onChanged: scanner.setOnlyBlueSt,
                ),
              ],
            ),
          ),
          if (results.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  scanner.isScanning
                      ? 'Ricerca in corso…'
                      : 'Nessun dispositivo. Accendi la scheda, tienila vicina e premi Cerca.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            )
          else
            for (final (i, r) in results.indexed)
              Padding(
                key: ValueKey(r.id),
                padding: const EdgeInsets.only(bottom: 8),
                child: FadeSlideIn(
                  index: i,
                  child: _ResultTile(
                    result: r,
                    isCurrent: connection.device?.id == r.id && connection.isReady,
                    onConnect: () => services.connectTo(
                        DeviceRef(r.id, r.name.isEmpty ? r.id : r.name, advertising: r.advertising)),
                  ),
                ),
              ),
          if (!settings.simulationMode && settings.knownDevices.isNotEmpty) ...[
            const SectionTitle('Usati in precedenza'),
            for (final d in settings.knownDevices)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: ListTile(
                    leading: const Icon(Icons.history),
                    title: Text(d.name),
                    subtitle: Text(
                      [
                        if (d.firmware.isNotEmpty) d.firmware,
                        formatRelative(d.lastConnectedMs),
                      ].join(' · '),
                    ),
                    onTap: () => services.connectTo(DeviceRef(d.id, d.name)),
                    trailing: IconButton(
                      tooltip: 'Rimuovi',
                      icon: const Icon(Icons.close),
                      onPressed: () => settings.forgetDevice(d.id),
                    ),
                  ),
                ),
              ),
          ],
          const SizedBox(height: 12),
          Text(
            'Se Android chiede un PIN, per il firmware di fabbrica ST indica 123456.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _CurrentDevice extends StatelessWidget {
  const _CurrentDevice({required this.connection});

  final ConnectionManager connection;

  @override
  Widget build(BuildContext context) {
    final device = connection.device!;
    final status = switch (connection.phase) {
      ConnectionPhase.ready => 'Connesso',
      ConnectionPhase.failed => connection.lastError?.message ?? 'Connessione non riuscita',
      ConnectionPhase.reconnecting => 'Riconnessione, tentativo ${connection.reconnectAttempt}',
      ConnectionPhase.idle => 'Non connesso',
      _ => 'Connessione in corso…',
    };
    final active = connection.isReady || connection.isBusy;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Card(
        child: ListTile(
          leading: StatusDot(connection.isReady
              ? Palette.ok
              : (connection.phase == ConnectionPhase.failed ? Palette.danger : Palette.warning)),
          title: Text(device.name),
          subtitle: Text(status),
          trailing: active
              ? TextButton(onPressed: connection.disconnect, child: const Text('Disconnetti'))
              : null,
        ),
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.result, required this.isCurrent, required this.onConnect});

  final BleScanResult result;
  final bool isCurrent;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final adv = result.advertising;
    final isTarget = adv?.isSensorTileBoxPro ?? false;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.name.isEmpty ? 'Senza nome' : result.name,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(result.id,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  if (adv != null) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        TagChip(adv.boardName, color: isTarget ? Palette.ok : null),
                        TagChip(adv.firmwareLabel,
                            color: theme.colorScheme.onSurfaceVariant),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SignalBars(result.rssi),
                    const SizedBox(width: 4),
                    Text('${result.rssi} dBm', style: const TextStyle(fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 8),
                if (isCurrent)
                  const Text('Connesso', style: TextStyle(color: Palette.ok, fontSize: 13))
                else
                  FilledButton.tonal(
                    onPressed: result.connectable ? onConnect : null,
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 38)),
                    child: const Text('Connetti'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
