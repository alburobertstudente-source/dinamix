import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/dinamix_app.dart';
import '../../app/services.dart';
import '../../ble/connection_manager.dart';
import '../../core/app_error.dart';
import '../../data/session_recorder.dart';
import '../../domain/session.dart';
import '../../export/session_exporter.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/effects.dart';

class LoggerScreen extends StatefulWidget {
  const LoggerScreen({super.key});

  @override
  State<LoggerScreen> createState() => _LoggerScreenState();
}

class _LoggerScreenState extends State<LoggerScreen> {
  late Future<List<SessionInfo>> _sessions;
  late final ValueNotifier<int> _revision;
  RecorderState? _lastState;

  AppServices get _services => context.read<AppServices>();

  @override
  void initState() {
    super.initState();
    _revision = context.read<AppServices>().sessionsRevision..addListener(_reload);
    _sessions = context.read<AppServices>().store.listSessions();
  }

  @override
  void dispose() {
    _revision.removeListener(_reload);
    super.dispose();
  }

  void _reload() => setState(() => _sessions = _services.store.listSessions());

  Future<void> _start() async {
    final controller = TextEditingController(
        text: defaultSessionName(DateTime.now().millisecondsSinceEpoch));
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nuova registrazione'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nome sessione'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext), child: const Text('Annulla')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text),
              child: const Text('Avvia')),
        ],
      ),
    );
    controller.dispose();
    if (name == null) return;
    try {
      await _services.startRecording(name);
      if (mounted) _reload();
    } catch (e) {
      ErrorCenter.instance.reportAny(e, tag: 'Logger', message: 'Avvio registrazione non riuscito');
    }
  }

  @override
  Widget build(BuildContext context) {
    final recorder = context.watch<SessionRecorder>();
    final connection = context.watch<ConnectionManager>();
    if (_lastState != recorder.state) {
      final changedToIdle = recorder.state == RecorderState.idle && _lastState != null;
      _lastState = recorder.state;
      if (changedToIdle) {
        _sessions = _services.store.listSessions();
      }
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Data Logger')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          _RecorderCard(recorder: recorder, connection: connection, onStart: _start),
          SectionTitle('Registrazioni',
              trailing: IconButton(
                tooltip: 'Aggiorna',
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: _reload,
              )),
          FutureBuilder<List<SessionInfo>>(
            future: _sessions,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final sessions = snapshot.data ?? const <SessionInfo>[];
              if (sessions.isEmpty) {
                return const EmptyState(
                  icon: Icons.folder_open,
                  title: 'Nessuna registrazione',
                  message: 'Collega il dispositivo e avvia la prima sessione.',
                );
              }
              return Column(
                children: [
                  for (final (i, s) in sessions.indexed)
                    Padding(
                      key: ValueKey(s.id),
                      padding: const EdgeInsets.only(bottom: 8),
                      child: FadeSlideIn(
                        index: i,
                        child: _SessionTile(
                          session: s,
                          recordingNow: recorder.sessionId == s.id,
                          onChanged: () => _revision.value++,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RecorderCard extends StatefulWidget {
  const _RecorderCard({required this.recorder, required this.connection, required this.onStart});

  final SessionRecorder recorder;
  final ConnectionManager connection;
  final VoidCallback onStart;

  @override
  State<_RecorderCard> createState() => _RecorderCardState();
}

class _RecorderCardState extends State<_RecorderCard> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (widget.recorder.isActive && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recorder = widget.recorder;
    final theme = Theme.of(context);
    if (!recorder.isActive) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.connection.isReady
                    ? 'Pronto a registrare da ${widget.connection.device?.name ?? ''}.'
                    : 'Collega un dispositivo per registrare.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              GradientButton(
                icon: Icons.fiber_manual_record_rounded,
                label: 'Avvia registrazione',
                onPressed: widget.connection.isReady ? widget.onStart : null,
              ),
            ],
          ),
        ),
      );
    }
    final paused = recorder.state == RecorderState.paused;
    final interrupted = !widget.connection.isReady;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                StatusDot(paused ? Palette.warning : Palette.danger),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(recorder.sessionName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(formatDuration(recorder.elapsed),
                style: numericStyle.copyWith(fontSize: 36, color: theme.colorScheme.onSurface)),
            Text(
              '${formatCount(recorder.writtenSamples)} campioni salvati'
              '${recorder.droppedSamples > 0 ? ', ${formatCount(recorder.droppedSamples)} persi' : ''}',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (interrupted) ...[
              const SizedBox(height: 8),
              const Text('Collegamento interrotto: la sessione riprende alla riconnessione.',
                  style: TextStyle(color: Palette.warning)),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: Icon(paused ? Icons.play_arrow : Icons.pause),
                    label: Text(paused ? 'Riprendi' : 'Pausa'),
                    onPressed: paused ? recorder.resume : recorder.pause,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.stop),
                    label: const Text('Termina'),
                    onPressed: recorder.stop,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session, required this.recordingNow, required this.onChanged});

  final SessionInfo session;
  final bool recordingNow;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          title: Text(session.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('${formatDateTime(session.startedAtMs)} · ${formatDuration(session.duration)}'),
                if (session.sourceTag != null)
                  TagChip(session.sourceTag!, color: Palette.simulation),
                if (session.status == SessionStatus.interrupted)
                  const TagChip('INTERROTTA', color: Palette.warning),
                if (recordingNow) const TagChip('IN CORSO', color: Palette.danger),
              ],
            ),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: recordingNow
              ? null
              : () => showModalBottomSheet<void>(
                    context: context,
                    showDragHandle: true,
                    isScrollControlled: true,
                    builder: (_) => _SessionSheet(session: session, onChanged: onChanged),
                  ),
        ),
      );
}

class _SessionSheet extends StatelessWidget {
  const _SessionSheet({required this.session, required this.onChanged});

  final SessionInfo session;
  final VoidCallback onChanged;

  Future<void> _export(BuildContext context, ExportFormat format) async {
    final services = context.read<AppServices>();
    try {
      await services.exporter.share(session, format);
    } catch (e) {
      ErrorCenter.instance.reportAny(e, tag: 'Export', message: 'Esportazione non riuscita');
    }
  }

  Future<void> _rename(BuildContext context) async {
    final services = context.read<AppServices>();
    final navigator = Navigator.of(context);
    final controller = TextEditingController(text: session.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rinomina sessione'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annulla')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text),
              child: const Text('Salva')),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    await services.store.renameSession(session.id, name.trim());
    navigator.pop();
    onChanged();
  }

  Future<void> _delete(BuildContext context) async {
    final services = context.read<AppServices>();
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminare la sessione?'),
        content: Text('"${session.name}" verrà eliminata definitivamente.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Annulla')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Palette.danger),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Elimina')),
        ],
      ),
    );
    if (confirmed != true) return;
    await services.store.deleteSession(session.id);
    navigator.pop();
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(session.name,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (session.sourceTag != null) ...[
              TagChip(
                session.isSimulated
                    ? 'DATI SIMULATI, NON SONO MISURE REALI'
                    : 'SENSORI DEL TELEFONO, NON DELLA SENSORTILE',
                color: Palette.simulation,
              ),
              const SizedBox(height: 8),
            ],
            Text('Dispositivo: ${session.deviceName}', style: muted),
            Text('Firmware: ${session.firmware}', style: muted),
            Text('Inizio: ${formatDateTime(session.startedAtMs)}', style: muted),
            Text('Durata: ${formatDuration(session.duration)}', style: muted),
            Text('Campioni: ${formatCount(session.sampleCount)}', style: muted),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.analytics_outlined),
              title: const Text('Analizza'),
              onTap: () {
                final nav = context.read<NavController>();
                Navigator.pop(context);
                nav.openAnalysis(session.id);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.table_chart_outlined),
              title: const Text('Esporta CSV'),
              onTap: () => _export(context, ExportFormat.csv),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.data_object),
              title: const Text('Esporta JSON'),
              onTap: () => _export(context, ExportFormat.json),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rinomina'),
              onTap: () => _rename(context),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.delete_outline, color: Palette.danger),
              title: const Text('Elimina', style: TextStyle(color: Palette.danger)),
              onTap: () => _delete(context),
            ),
          ],
        ),
      ),
    );
  }
}
