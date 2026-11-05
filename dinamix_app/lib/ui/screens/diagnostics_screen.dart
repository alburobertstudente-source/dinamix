import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/services.dart';
import '../../ble/connection_manager.dart';
import '../../ble/transport/ble_transport.dart';
import '../../core/app_error.dart';
import '../../core/app_logger.dart';
import '../../domain/sensor_kind.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Shows what the firmware exposes and how the link behaves: the first place to
/// look when a real board behaves differently from what is expected.
class DiagnosticsScreen extends StatelessWidget {
  const DiagnosticsScreen({super.key});

  String _report(ConnectionManager c, String adapter) {
    final out = StringBuffer()
      ..writeln('DinamiX $appVersion, diagnostica ${DateTime.now().toIso8601String()}')
      ..writeln('Adattatore: $adapter, fase: ${c.phase.name}, simulazione: ${c.isSimulated}')
      ..writeln('Dispositivo: ${c.device?.name} (${c.device?.id})')
      ..writeln('Scheda: ${c.device?.advertising?.boardName}')
      ..writeln('Firmware: ${c.device?.advertising?.firmwareLabel}')
      ..writeln('MTU: ${c.mtu}, RSSI: ${c.rssi}, perdite collegamento: ${c.linkLossCount}');
    for (final s in c.characteristics) {
      out.writeln(
          '${s.info.uuid} [${s.info.propertiesLabel}] ${s.parsed.displayName} sub=${s.subscribed} '
          'pkt=${s.loss.received} bytes=${s.bytes} err=${s.decodeErrors} persi~=${s.loss.estimatedLost} '
          'ultimo=${s.lastHex}');
    }
    for (final e in logger.entries.reversed.take(100).toList().reversed) {
      out.writeln(e);
    }
    return out.toString();
  }

  @override
  Widget build(BuildContext context) {
    final connection = context.watch<ConnectionManager>();
    final services = context.read<AppServices>();
    final adapter = services.scanner.adapterStatus.name;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostica'),
        actions: [
          IconButton(
            tooltip: 'Copia rapporto',
            icon: const Icon(Icons.copy_all),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await Clipboard.setData(ClipboardData(text: _report(connection, adapter)));
              messenger.showSnackBar(const SnackBar(content: Text('Rapporto copiato')));
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          const SectionTitle('Stato'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  _Row('Adattatore', adapter),
                  _Row(
                    'Trasporto',
                    switch (connection.dataSource) {
                      DataSource.hardware => 'Hardware BLE',
                      DataSource.phone => 'SENSORI DEL TELEFONO',
                      DataSource.simulated => 'SIMULATO',
                    },
                  ),
                  _Row('Fase', connection.phase.name),
                  _Row('Dispositivo', connection.device?.name ?? '—'),
                  _Row('Scheda', connection.device?.advertising?.boardName ?? '—'),
                  _Row('Firmware', connection.device?.advertising?.firmwareLabel ?? '—'),
                  _Row('MTU', connection.mtu?.toString() ?? '—'),
                  _Row('RSSI', connection.rssi == null ? '—' : '${connection.rssi} dBm'),
                  _Row('Perdite collegamento', '${connection.linkLossCount}'),
                  _Row('Pacchetti persi (stima)', '${connection.estimatedLostPackets}'),
                  if (connection.lastError != null)
                    _Row('Ultimo errore', connection.lastError!.message),
                ],
              ),
            ),
          ),
          if (connection.isSimulated) ...[
            const SectionTitle('Test simulatore'),
            OutlinedButton.icon(
              icon: const Icon(Icons.link_off),
              label: const Text('Simula perdita di collegamento'),
              onPressed: connection.isReady ? services.simulator.simulateLinkLoss : null,
            ),
          ],
          const SectionTitle('Servizi e caratteristiche'),
          if (connection.services.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Text('Nessun servizio: collega un dispositivo.'),
              ),
            )
          else
            for (final service in connection.services)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _ServiceCard(service: service, connection: connection, services: services),
              ),
          const SectionTitle('Console di debug'),
          _Console(connection: connection),
          const SectionTitle('Log'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: ValueListenableBuilder<int>(
                valueListenable: logger.revision,
                builder: (context, _, __) {
                  final entries = logger.entries.reversed.take(80).toList();
                  if (entries.isEmpty) return const Text('Nessun messaggio.');
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final e in entries)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Text(
                            '${formatTime(e.time.millisecondsSinceEpoch)} [${e.tag}] ${e.message}',
                            style: TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: switch (e.level) {
                                AppLogLevel.error => Palette.danger,
                                AppLogLevel.warning => Palette.warning,
                                _ => Theme.of(context).colorScheme.onSurfaceVariant,
                              },
                            ),
                          ),
                        ),
                    ],
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

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
            const SizedBox(width: 12),
            Flexible(child: Text(value, textAlign: TextAlign.right)),
          ],
        ),
      );
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.service, required this.connection, required this.services});

  final BleServiceInfo service;
  final ConnectionManager connection;
  final AppServices services;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Servizio ${service.uuid}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, fontFamily: 'monospace')),
            const SizedBox(height: 6),
            ListenableBuilder(
              listenable: services.hub.frame,
              builder: (context, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final status in connection.characteristics
                      .where((c) => c.info.serviceUuid == service.uuid))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(status.parsed.displayName,
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                              if (status.subscribed)
                                const TagChip('NOTIFICHE', color: Palette.ok),
                              if (status.decodable)
                                const TagChip('DECODIFICATA')
                              else
                                TagChip('NON DECODIFICATA', color: theme.colorScheme.onSurfaceVariant),
                            ],
                          ),
                          Text(status.info.uuid,
                              style: muted?.copyWith(fontFamily: 'monospace', fontSize: 10)),
                          Text(
                            '${status.info.propertiesLabel} · ${status.loss.received} pacchetti · '
                            '${status.bytes} byte · errori ${status.decodeErrors} · '
                            'persi ~${status.loss.estimatedLost}',
                            style: muted,
                          ),
                          if (status.lastHex.isNotEmpty)
                            Text(status.lastHex,
                                style: muted?.copyWith(fontFamily: 'monospace', fontSize: 10)),
                          if (status.lastError != null)
                            Text(status.lastError!,
                                style: const TextStyle(color: Palette.danger, fontSize: 11)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Console extends StatefulWidget {
  const _Console({required this.connection});

  final ConnectionManager connection;

  @override
  State<_Console> createState() => _ConsoleState();
}

class _ConsoleState extends State<_Console> {
  final TextEditingController _controller = TextEditingController();
  final StringBuffer _output = StringBuffer();
  late final StreamSubscription<String> _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.connection.consoleOutput.listen((text) {
      if (mounted) setState(() => _output.write(text));
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final command = _controller.text.trim();
    if (command.isEmpty) return;
    setState(() => _output.writeln('> $command'));
    _controller.clear();
    try {
      await widget.connection.sendConsoleCommand(command);
    } catch (e) {
      ErrorCenter.instance.reportAny(e, tag: 'Console', message: 'Comando non inviato');
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasConsole = widget.connection.characteristics.any((c) => c.parsed.isDebugConsole);
    if (!hasConsole) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Text('Non disponibile: il firmware collegato non espone la console BlueST.'),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_output.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SelectableText(_output.toString(),
                    style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
              ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                      hintText: 'Comando testuale',
                      isDense: true,
                    ),
                  ),
                ),
                IconButton(icon: const Icon(Icons.send), onPressed: _send, tooltip: 'Invia'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
