import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../ble/connection_manager.dart';
import '../core/app_error.dart';
import '../core/app_logger.dart';
import '../core/keep_alive.dart';
import '../domain/sensor_kind.dart';
import '../domain/session.dart';
import 'session_store.dart';

enum RecorderState { idle, recording, paused }

/// Data logger. Readings are buffered in memory and written in batches, so the
/// BLE callback never waits for the disk.
class SessionRecorder extends ChangeNotifier implements ReadingSink {
  SessionRecorder(
    this._store, {
    KeepAlive? keepAlive,
    this.flushInterval = const Duration(seconds: 1),
    this.maxPending = 200000,
    int Function()? clock,
  })  : _keepAlive = keepAlive ?? NoopKeepAlive(),
        _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  final SessionStore _store;
  final KeepAlive _keepAlive;
  final Duration flushInterval;

  /// Above this size, with a failing disk, the oldest data is dropped and counted.
  final int maxPending;
  final int Function() _clock;

  RecorderState state = RecorderState.idle;
  int? sessionId;
  String sessionName = '';
  DataSource? _source;
  int writtenSamples = 0;
  int droppedSamples = 0;
  int _startedAtMs = 0;
  int _pausedTotalMs = 0;
  int? _pausedAtMs;
  Map<String, Object?> _config = const {};
  final Map<SensorKind, int> _counts = {};

  List<SensorReading> _pending = [];
  Timer? _flushTimer;
  Future<void> _writeChain = Future<void>.value();
  bool _writeFailureReported = false;

  bool get isActive => state != RecorderState.idle;

  /// Recording time, pauses excluded.
  Duration get elapsed {
    if (!isActive) return Duration.zero;
    final now = _pausedAtMs ?? _clock();
    return Duration(milliseconds: now - _startedAtMs - _pausedTotalMs);
  }

  int get pendingSamples => _pending.length;

  Future<void> start({
    required String name,
    required String deviceName,
    required String deviceId,
    required String firmware,
    required DataSource source,
    required Map<String, Object?> config,
  }) async {
    if (isActive) return;
    final trimmed = name.trim();
    sessionName = trimmed.isEmpty ? defaultSessionName(_clock()) : trimmed;
    _source = source;
    _startedAtMs = _clock();
    _pausedTotalMs = 0;
    _pausedAtMs = null;
    writtenSamples = 0;
    droppedSamples = 0;
    _counts.clear();
    _config = config;
    _writeFailureReported = false;
    try {
      sessionId = await _store.createSession(
        name: sessionName,
        startedAtMs: _startedAtMs,
        deviceName: deviceName,
        deviceId: deviceId,
        firmware: firmware,
        source: source,
        configJson: jsonEncode(config),
      );
      await _store.addEvent(sessionId!, SessionEvent(_startedAtMs, 'start'));
    } catch (e) {
      sessionId = null;
      throw AppError(AppErrorCode.storageFailed, 'Impossibile creare la sessione.', cause: e);
    }
    state = RecorderState.recording;
    _flushTimer = Timer.periodic(flushInterval, (_) => flush());
    await _keepAlive.start('Registrazione: $sessionName');
    logger.i('Logger', 'Sessione $sessionId avviata');
    notifyListeners();
  }

  @override
  void ingest(SensorReading reading) {
    if (state != RecorderState.recording) return;
    // A session never mixes real and simulated data.
    if (reading.source != _source) return;
    _pending.add(reading);
    _counts[reading.kind] = (_counts[reading.kind] ?? 0) + 1;
  }

  Future<void> pause() async {
    if (state != RecorderState.recording) return;
    state = RecorderState.paused;
    _pausedAtMs = _clock();
    await flush();
    await _event('pause');
    notifyListeners();
  }

  Future<void> resume() async {
    if (state != RecorderState.paused) return;
    final pausedAt = _pausedAtMs;
    if (pausedAt != null) _pausedTotalMs += _clock() - pausedAt;
    _pausedAtMs = null;
    state = RecorderState.recording;
    await _event('resume');
    notifyListeners();
  }

  /// Stops and finalizes the session. Returns its ID.
  Future<int?> stop() async {
    if (!isActive) return null;
    final id = sessionId;
    state = RecorderState.idle;
    _flushTimer?.cancel();
    _flushTimer = null;
    await flush();
    await _writeChain;
    final end = _clock();
    if (id != null) {
      try {
        await _store.addEvent(id, SessionEvent(end, 'stop'));
        await _store.finishSession(
          id,
          endedAtMs: end,
          status: SessionStatus.completed,
          configJson: jsonEncode({
            ..._config,
            'dropped_samples': droppedSamples,
            'mean_rate_hz': _meanRates(end),
          }),
        );
      } catch (e) {
        ErrorCenter.instance.report(
            AppError(AppErrorCode.storageFailed, 'Chiusura sessione non riuscita.', cause: e),
            tag: 'Logger');
      }
    }
    await _keepAlive.stop();
    sessionId = null;
    _source = null;
    logger.i('Logger', 'Sessione $id chiusa: $writtenSamples campioni');
    notifyListeners();
    return id;
  }

  Map<String, double> _meanRates(int endMs) {
    final seconds = (endMs - _startedAtMs - _pausedTotalMs) / 1000.0;
    if (seconds <= 0) return const {};
    return {
      for (final e in _counts.entries) e.key.id: double.parse((e.value / seconds).toStringAsFixed(2)),
    };
  }

  /// Records link interruptions: the samples missing in a gap stay explainable.
  Future<void> onLinkEvent(LinkEvent event) async {
    if (!isActive) return;
    switch (event) {
      case LinkEvent.lost:
        await _event('link_lost');
      case LinkEvent.restored:
        await _event('link_restored');
      case LinkEvent.established:
        break;
    }
  }

  Future<void> _event(String type, {String detail = ''}) async {
    final id = sessionId;
    if (id == null) return;
    try {
      await _store.addEvent(id, SessionEvent(_clock(), type, detail: detail));
    } catch (e) {
      logger.w('Logger', 'Evento $type non salvato: $e');
    }
  }

  /// Writes are chained: two batches never run out of order.
  Future<void> flush() {
    _writeChain = _writeChain.then((_) => _flushOnce());
    return _writeChain;
  }

  Future<void> _flushOnce() async {
    final id = sessionId;
    if (id == null || _pending.isEmpty) return;
    final batch = _pending;
    _pending = [];
    try {
      await _store.insertSamples(id, batch);
      writtenSamples += batch.length;
      _writeFailureReported = false;
      notifyListeners();
    } catch (e) {
      // Keep the data and retry on the next flush.
      _pending = [...batch, ..._pending];
      final overflow = _pending.length - maxPending;
      if (overflow > 0) {
        _pending.removeRange(0, overflow);
        droppedSamples += overflow;
      }
      if (!_writeFailureReported) {
        _writeFailureReported = true;
        ErrorCenter.instance.report(
            AppError(AppErrorCode.storageFailed, 'Scrittura su disco non riuscita, nuovo tentativo in corso.', cause: e),
            tag: 'Logger');
      }
    }
  }

  @override
  void dispose() {
    _flushTimer?.cancel();
    super.dispose();
  }
}

String defaultSessionName(int atMs) {
  final t = DateTime.fromMillisecondsSinceEpoch(atMs);
  String two(int v) => v.toString().padLeft(2, '0');
  return 'Sessione ${two(t.day)}/${two(t.month)}/${t.year} ${two(t.hour)}:${two(t.minute)}';
}
