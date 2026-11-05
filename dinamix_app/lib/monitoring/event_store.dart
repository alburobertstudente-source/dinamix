import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// A detection event as saved on the phone (report §15.5).
class StoredDetection {
  StoredDetection({
    this.id,
    required this.atMs,
    required this.source,
    required this.algoVersion,
    required this.level,
    required this.category,
    required this.confidence,
    required this.quality,
    required this.alarm,
    required this.features,
    required this.classification,
    required this.raw,
    this.label,
  });

  final int? id;

  /// Wall clock of the event (ms since epoch).
  final int atMs;
  final String source;
  final String algoVersion;
  final int level;
  final String category;
  final double confidence;
  final double quality;
  final bool alarm;
  final Map<String, Object?> features;
  final Map<String, Object?> classification;

  /// Raw window: [t_s, fx, fy, fz, wx, wy, wz] per sample.
  final List<List<double>> raw;

  /// Manual label for the dataset (report §14.3).
  final String? label;

  StoredDetection copyWith({int? id, String? label}) => StoredDetection(
        id: id ?? this.id,
        atMs: atMs,
        source: source,
        algoVersion: algoVersion,
        level: level,
        category: category,
        confidence: confidence,
        quality: quality,
        alarm: alarm,
        features: features,
        classification: classification,
        raw: raw,
        label: label ?? this.label,
      );
}

/// State of an alert (report §12.2).
enum AlertState { alarming, countdown, sending, sent, failed, unknown, cancelled, dryRun }

class StoredAlert {
  StoredAlert({
    this.id,
    required this.detectionId,
    required this.state,
    required this.startedAtMs,
    this.endedAtMs,
    this.smsAttempts = 0,
    this.smsResult,
    required this.dryRun,
  });

  final int? id;
  final int detectionId;
  final AlertState state;
  final int startedAtMs;
  final int? endedAtMs;
  final int smsAttempts;
  final String? smsResult;
  final bool dryRun;

  StoredAlert copyWith({
    int? id,
    AlertState? state,
    int? endedAtMs,
    int? smsAttempts,
    String? smsResult,
  }) =>
      StoredAlert(
        id: id ?? this.id,
        detectionId: detectionId,
        state: state ?? this.state,
        startedAtMs: startedAtMs,
        endedAtMs: endedAtMs ?? this.endedAtMs,
        smsAttempts: smsAttempts ?? this.smsAttempts,
        smsResult: smsResult ?? this.smsResult,
        dryRun: dryRun,
      );
}

abstract class EventStore {
  Future<int> insertDetection(StoredDetection d);
  Future<List<StoredDetection>> listDetections({int limit = 200, bool withRaw = false});
  Future<StoredDetection?> getDetection(int id);
  Future<void> setLabel(int id, String? label);
  Future<int> insertAlert(StoredAlert a);
  Future<void> updateAlert(StoredAlert a);
  Future<List<StoredAlert>> listAlerts({int limit = 100});
  Future<void> deleteAll();
}

/// SQLite implementation in a database of its own, separate from the sessions.
class SqliteEventStore implements EventStore {
  SqliteEventStore._(this._db);

  final Database _db;
  static const int keep = 300;

  static Future<SqliteEventStore> open() async {
    final path = p.join(await getDatabasesPath(), 'dynamix_events.db');
    final db = await openDatabase(path, version: 1, onCreate: (db, _) async {
      await db.execute('''
        CREATE TABLE detections (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          at_ms INTEGER NOT NULL,
          source TEXT NOT NULL,
          algo_version TEXT NOT NULL,
          level INTEGER NOT NULL,
          category TEXT NOT NULL,
          confidence REAL NOT NULL,
          quality REAL NOT NULL,
          alarm INTEGER NOT NULL,
          features TEXT NOT NULL,
          classification TEXT NOT NULL,
          raw TEXT NOT NULL,
          label TEXT
        )''');
      await db.execute('''
        CREATE TABLE alerts (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          detection_id INTEGER NOT NULL UNIQUE,
          state TEXT NOT NULL,
          started_at_ms INTEGER NOT NULL,
          ended_at_ms INTEGER,
          sms_attempts INTEGER NOT NULL DEFAULT 0,
          sms_result TEXT,
          dry_run INTEGER NOT NULL
        )''');
    });
    return SqliteEventStore._(db);
  }

  Map<String, Object?> _row(StoredDetection d) => {
        'at_ms': d.atMs,
        'source': d.source,
        'algo_version': d.algoVersion,
        'level': d.level,
        'category': d.category,
        'confidence': d.confidence,
        'quality': d.quality,
        'alarm': d.alarm ? 1 : 0,
        'features': jsonEncode(d.features),
        'classification': jsonEncode(d.classification),
        'raw': jsonEncode(d.raw),
        'label': d.label,
      };

  StoredDetection _fromRow(Map<String, Object?> r, {required bool withRaw}) => StoredDetection(
        id: r['id'] as int,
        atMs: r['at_ms'] as int,
        source: r['source'] as String,
        algoVersion: r['algo_version'] as String,
        level: r['level'] as int,
        category: r['category'] as String,
        confidence: (r['confidence'] as num).toDouble(),
        quality: (r['quality'] as num).toDouble(),
        alarm: r['alarm'] == 1,
        features: (jsonDecode(r['features'] as String) as Map).cast<String, Object?>(),
        classification: (jsonDecode(r['classification'] as String) as Map).cast<String, Object?>(),
        raw: withRaw && r['raw'] != null
            ? [
                for (final row in jsonDecode(r['raw'] as String) as List)
                  [for (final v in row as List) (v as num).toDouble()],
              ]
            : const [],
        label: r['label'] as String?,
      );

  @override
  Future<int> insertDetection(StoredDetection d) async {
    final id = await _db.insert('detections', _row(d));
    // Bounded history: the oldest events are removed beyond [keep].
    await _db.rawDelete(
        'DELETE FROM detections WHERE id NOT IN (SELECT id FROM detections ORDER BY id DESC LIMIT ?)', [keep]);
    return id;
  }

  @override
  Future<List<StoredDetection>> listDetections({int limit = 200, bool withRaw = false}) async {
    final columns = withRaw
        ? null
        : ['id', 'at_ms', 'source', 'algo_version', 'level', 'category', 'confidence', 'quality', 'alarm',
            'features', 'classification', 'label'];
    final rows = await _db.query('detections', columns: columns, orderBy: 'id DESC', limit: limit);
    return [for (final r in rows) _fromRow(r, withRaw: withRaw)];
  }

  @override
  Future<StoredDetection?> getDetection(int id) async {
    final rows = await _db.query('detections', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : _fromRow(rows.first, withRaw: true);
  }

  @override
  Future<void> setLabel(int id, String? label) =>
      _db.update('detections', {'label': label}, where: 'id = ?', whereArgs: [id]);

  Map<String, Object?> _alertRow(StoredAlert a) => {
        'detection_id': a.detectionId,
        'state': a.state.name,
        'started_at_ms': a.startedAtMs,
        'ended_at_ms': a.endedAtMs,
        'sms_attempts': a.smsAttempts,
        'sms_result': a.smsResult,
        'dry_run': a.dryRun ? 1 : 0,
      };

  @override
  Future<int> insertAlert(StoredAlert a) =>
      _db.insert('alerts', _alertRow(a), conflictAlgorithm: ConflictAlgorithm.ignore);

  @override
  Future<void> updateAlert(StoredAlert a) =>
      _db.update('alerts', _alertRow(a), where: 'id = ?', whereArgs: [a.id]);

  @override
  Future<List<StoredAlert>> listAlerts({int limit = 100}) async {
    final rows = await _db.query('alerts', orderBy: 'id DESC', limit: limit);
    return [
      for (final r in rows)
        StoredAlert(
          id: r['id'] as int,
          detectionId: r['detection_id'] as int,
          state: AlertState.values.byName(r['state'] as String),
          startedAtMs: r['started_at_ms'] as int,
          endedAtMs: r['ended_at_ms'] as int?,
          smsAttempts: r['sms_attempts'] as int,
          smsResult: r['sms_result'] as String?,
          dryRun: r['dry_run'] == 1,
        ),
    ];
  }

  @override
  Future<void> deleteAll() async {
    await _db.delete('alerts');
    await _db.delete('detections');
  }
}

/// In-memory implementation for tests and for the simulation mode.
class MemoryEventStore implements EventStore {
  final List<StoredDetection> detections = [];
  final List<StoredAlert> alerts = [];
  int _nextId = 1;
  int _nextAlert = 1;

  @override
  Future<int> insertDetection(StoredDetection d) async {
    final id = _nextId++;
    detections.add(d.copyWith(id: id));
    return id;
  }

  @override
  Future<List<StoredDetection>> listDetections({int limit = 200, bool withRaw = false}) async =>
      detections.reversed.take(limit).toList();

  @override
  Future<StoredDetection?> getDetection(int id) async {
    for (final d in detections) {
      if (d.id == id) return d;
    }
    return null;
  }

  @override
  Future<void> setLabel(int id, String? label) async {
    final i = detections.indexWhere((d) => d.id == id);
    if (i >= 0) {
      final d = detections[i];
      detections[i] = StoredDetection(
        id: d.id,
        atMs: d.atMs,
        source: d.source,
        algoVersion: d.algoVersion,
        level: d.level,
        category: d.category,
        confidence: d.confidence,
        quality: d.quality,
        alarm: d.alarm,
        features: d.features,
        classification: d.classification,
        raw: d.raw,
        label: label,
      );
    }
  }

  @override
  Future<int> insertAlert(StoredAlert a) async {
    if (alerts.any((x) => x.detectionId == a.detectionId)) return 0;
    final id = _nextAlert++;
    alerts.add(a.copyWith(id: id));
    return id;
  }

  @override
  Future<void> updateAlert(StoredAlert a) async {
    final i = alerts.indexWhere((x) => x.id == a.id);
    if (i >= 0) alerts[i] = a;
  }

  @override
  Future<List<StoredAlert>> listAlerts({int limit = 100}) async => alerts.reversed.take(limit).toList();

  @override
  Future<void> deleteAll() async {
    detections.clear();
    alerts.clear();
  }
}
