import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../domain/sensor_kind.dart';
import '../domain/session.dart';
import 'session_store.dart';

class SqliteSessionStore implements SessionStore {
  SqliteSessionStore._(this._db);

  final Database _db;

  static Future<SqliteSessionStore> open() async {
    final path = p.join(await getDatabasesPath(), 'dinamix.db');
    final db = await openDatabase(
      path,
      version: 1,
      onConfigure: (db) async {
        await db.rawQuery('PRAGMA journal_mode=WAL');
        await db.rawQuery('PRAGMA foreign_keys=ON');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE sessions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            started_at INTEGER NOT NULL,
            ended_at INTEGER,
            device_name TEXT NOT NULL,
            device_id TEXT NOT NULL,
            firmware TEXT NOT NULL,
            source TEXT NOT NULL,
            status TEXT NOT NULL,
            config TEXT NOT NULL
          )''');
        await db.execute('''
          CREATE TABLE samples (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id INTEGER NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
            kind TEXT NOT NULL,
            t_ms INTEGER NOT NULL,
            ticks INTEGER NOT NULL,
            v0 REAL, v1 REAL, v2 REAL, v3 REAL
          )''');
        await db.execute('CREATE INDEX idx_samples_session ON samples(session_id, kind, id)');
        await db.execute('''
          CREATE TABLE events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id INTEGER NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
            at_ms INTEGER NOT NULL,
            type TEXT NOT NULL,
            detail TEXT NOT NULL
          )''');
      },
    );
    return SqliteSessionStore._(db);
  }

  @override
  Future<int> recoverInterrupted() async {
    final open = await _db.query('sessions',
        columns: ['id'], where: 'status = ?', whereArgs: [SessionStatus.recording.name]);
    for (final row in open) {
      final id = row['id'] as int;
      final last = await _db.rawQuery('SELECT MAX(t_ms) AS t FROM samples WHERE session_id = ?', [id]);
      await _db.update(
        'sessions',
        {'status': SessionStatus.interrupted.name, 'ended_at': last.first['t']},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    return open.length;
  }

  @override
  Future<int> createSession({
    required String name,
    required int startedAtMs,
    required String deviceName,
    required String deviceId,
    required String firmware,
    required DataSource source,
    required String configJson,
  }) =>
      _db.insert('sessions', {
        'name': name,
        'started_at': startedAtMs,
        'device_name': deviceName,
        'device_id': deviceId,
        'firmware': firmware,
        'source': source.name,
        'status': SessionStatus.recording.name,
        'config': configJson,
      });

  @override
  Future<void> insertSamples(int sessionId, List<SensorReading> readings) async {
    if (readings.isEmpty) return;
    await _db.transaction((txn) async {
      final batch = txn.batch();
      for (final r in readings) {
        batch.insert('samples', {
          'session_id': sessionId,
          'kind': r.kind.id,
          't_ms': r.receivedAtMs,
          'ticks': r.deviceTicks,
          for (var i = 0; i < maxStoredChannels; i++)
            'v$i': i < r.values.length && !r.values[i].isNaN ? r.values[i] : null,
        });
      }
      await batch.commit(noResult: true);
    });
  }

  @override
  Future<void> addEvent(int sessionId, SessionEvent event) => _db.insert('events', {
        'session_id': sessionId,
        'at_ms': event.atMs,
        'type': event.type,
        'detail': event.detail,
      });

  @override
  Future<void> finishSession(int sessionId,
      {required int endedAtMs, required SessionStatus status, required String configJson}) async {
    await _db.update(
      'sessions',
      {'ended_at': endedAtMs, 'status': status.name, 'config': configJson},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  static const String _sessionSelect = '''
    SELECT s.*, (SELECT COUNT(*) FROM samples m WHERE m.session_id = s.id) AS sample_count
    FROM sessions s''';

  SessionInfo _mapSession(Map<String, Object?> row) => SessionInfo(
        id: row['id'] as int,
        name: row['name'] as String,
        startedAtMs: row['started_at'] as int,
        endedAtMs: row['ended_at'] as int?,
        deviceName: row['device_name'] as String,
        deviceId: row['device_id'] as String,
        firmware: row['firmware'] as String,
        source: DataSource.values.byName(row['source'] as String),
        status: SessionStatus.values.byName(row['status'] as String),
        sampleCount: (row['sample_count'] as int?) ?? 0,
        configJson: row['config'] as String,
      );

  @override
  Future<List<SessionInfo>> listSessions() async {
    final rows = await _db.rawQuery('$_sessionSelect ORDER BY s.started_at DESC');
    return rows.map(_mapSession).toList();
  }

  @override
  Future<SessionInfo?> getSession(int sessionId) async {
    final rows = await _db.rawQuery('$_sessionSelect WHERE s.id = ?', [sessionId]);
    return rows.isEmpty ? null : _mapSession(rows.first);
  }

  @override
  Future<void> renameSession(int sessionId, String name) async {
    await _db.update('sessions', {'name': name}, where: 'id = ?', whereArgs: [sessionId]);
  }

  @override
  Future<void> deleteSession(int sessionId) async {
    await _db.delete('sessions', where: 'id = ?', whereArgs: [sessionId]);
  }

  @override
  Future<void> deleteAll() async {
    await _db.delete('sessions');
  }

  @override
  Future<List<SessionEvent>> events(int sessionId) async {
    final rows = await _db.query('events',
        where: 'session_id = ?', whereArgs: [sessionId], orderBy: 'id');
    return rows
        .map((r) => SessionEvent(r['at_ms'] as int, r['type'] as String,
            detail: r['detail'] as String))
        .toList();
  }

  @override
  Future<List<SensorKind>> kindsIn(int sessionId) async {
    final rows = await _db.rawQuery('SELECT DISTINCT kind FROM samples WHERE session_id = ?', [sessionId]);
    return rows
        .map((r) => SensorKind.fromId(r['kind'] as String))
        .whereType<SensorKind>()
        .toList();
  }

  @override
  Future<List<StoredSample>> pageSamples(int sessionId,
      {SensorKind? kind, int afterRowId = 0, int limit = 5000}) async {
    final where = StringBuffer('session_id = ? AND id > ?');
    final args = <Object>[sessionId, afterRowId];
    if (kind != null) {
      where.write(' AND kind = ?');
      args.add(kind.id);
    }
    final rows = await _db.query('samples',
        where: where.toString(), whereArgs: args, orderBy: 'id', limit: limit);
    final out = <StoredSample>[];
    for (final r in rows) {
      final k = SensorKind.fromId(r['kind'] as String);
      if (k == null) continue;
      final count = k.channels.length.clamp(0, maxStoredChannels);
      out.add(StoredSample(
        rowId: r['id'] as int,
        kind: k,
        receivedAtMs: r['t_ms'] as int,
        deviceTicks: r['ticks'] as int,
        values: [
          for (var i = 0; i < count; i++) (r['v$i'] as num?)?.toDouble() ?? double.nan,
        ],
      ));
    }
    return out;
  }
}
