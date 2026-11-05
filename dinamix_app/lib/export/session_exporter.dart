import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/app_error.dart';
import '../data/session_store.dart';
import '../domain/sensor_kind.dart';
import '../domain/session.dart';

enum ExportFormat { csv, json }

/// Exports are streamed page by page: long sessions do not need to fit in memory.
class SessionExporter {
  SessionExporter(this._store);

  final SessionStore _store;

  Future<void> writeCsv(SessionInfo session, StringSink sink) async {
    final events = await _store.events(session.id);
    sink.writeln('# DinamiX - sessione di misura');
    sink.writeln('# nome: ${_comment(session.name)}');
    sink.writeln('# origine_dati: ${_sourceLabel(session)}');
    sink.writeln('# dispositivo: ${_comment(session.deviceName)} (${_comment(session.deviceId)})');
    sink.writeln('# firmware: ${_comment(session.firmware)}');
    sink.writeln('# inizio: ${_iso(session.startedAtMs)}');
    sink.writeln('# fine: ${session.endedAtMs == null ? '' : _iso(session.endedAtMs!)}');
    sink.writeln('# stato: ${session.status.name}');
    sink.writeln('# configurazione: ${session.configJson}');
    for (final e in events) {
      sink.writeln('# evento: ${_iso(e.atMs)} ${e.type} ${_comment(e.detail)}');
    }
    sink.writeln('timestamp_iso,timestamp_ms,device_ticks,sensor,channel,value,unit,source');
    var after = 0;
    while (true) {
      final page = await _store.pageSamples(session.id, afterRowId: after);
      if (page.isEmpty) break;
      for (final s in page) {
        final iso = _iso(s.receivedAtMs);
        for (var i = 0; i < s.values.length; i++) {
          final channel = s.kind.channels[i];
          final value = s.values[i];
          sink.writeln([
            iso,
            s.receivedAtMs,
            s.deviceTicks,
            s.kind.id,
            channel.key,
            value.isNaN ? '' : value,
            csvField(channel.unit),
            session.source.name,
          ].join(','));
        }
      }
      after = page.last.rowId;
    }
  }

  Future<void> writeJson(SessionInfo session, StringSink sink) async {
    final events = await _store.events(session.id);
    final kinds = await _store.kindsIn(session.id);
    final header = {
      'format': 'dinamix-session-1',
      'session': {
        'id': session.id,
        'name': session.name,
        'data_source': session.source.name,
        'device_name': session.deviceName,
        'device_id': session.deviceId,
        'firmware': session.firmware,
        'started_at': _iso(session.startedAtMs),
        'ended_at': session.endedAtMs == null ? null : _iso(session.endedAtMs!),
        'status': session.status.name,
        'configuration': session.config,
      },
      'sensors': {
        for (final k in kinds)
          k.id: {
            'label': k.label,
            'channels': [
              for (final c in k.channels) {'key': c.key, 'label': c.label, 'unit': c.unit},
            ],
          },
      },
      'events': [
        for (final e in events) {'at': _iso(e.atMs), 'type': e.type, 'detail': e.detail},
      ],
    };
    final encoded = jsonEncode(header);
    // Open the object again to stream the samples array.
    sink.write(encoded.substring(0, encoded.length - 1));
    sink.write(',"samples":[');
    var after = 0;
    var first = true;
    while (true) {
      final page = await _store.pageSamples(session.id, afterRowId: after);
      if (page.isEmpty) break;
      for (final s in page) {
        if (!first) sink.write(',');
        first = false;
        sink.write(jsonEncode({
          't': s.receivedAtMs,
          'ticks': s.deviceTicks,
          'sensor': s.kind.id,
          // JSON has no NaN/Infinity: those values become null.
          'values': [for (final v in s.values) v.isFinite ? v : null],
        }));
      }
      after = page.last.rowId;
    }
    sink.write(']}');
  }

  /// Writes the file in the temporary directory, returns its path.
  Future<String> exportToFile(SessionInfo session, ExportFormat format) async {
    final dir = await getTemporaryDirectory();
    final safeName = session.name.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    final tag = session.sourceTag;
    final prefix = tag == null ? '' : '${tag}_';
    final file = File(p.join(dir.path, '$prefix${safeName}_${session.id}.${format.name}'));
    final sink = file.openWrite();
    try {
      if (format == ExportFormat.csv) {
        await writeCsv(session, sink);
      } else {
        await writeJson(session, sink);
      }
      await sink.flush();
    } catch (e) {
      throw AppError(AppErrorCode.exportFailed, 'Esportazione non riuscita.', cause: e);
    } finally {
      await sink.close();
    }
    return file.path;
  }

  Future<void> share(SessionInfo session, ExportFormat format) async {
    final path = await exportToFile(session, format);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(path)],
      title: session.name,
    ));
  }

  static String _iso(int ms) =>
      DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();

  static String _sourceLabel(SessionInfo s) => switch (s.source) {
        DataSource.hardware => 'hardware',
        DataSource.phone => 'TELEFONO - sensori dello smartphone, non della SensorTile',
        DataSource.simulated => 'SIMULATO - non sono misure reali',
      };

  static String _comment(String text) => text.replaceAll(RegExp(r'[\r\n]+'), ' ');
}

/// RFC 4180 quoting.
String csvField(String value) {
  if (value.contains(RegExp(r'[",\r\n]'))) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}
