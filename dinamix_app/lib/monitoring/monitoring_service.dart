import 'dart:async';

import 'package:flutter/foundation.dart';

import '../alert/alert_manager.dart';
import '../ble/connection_manager.dart';
import '../ble/transport/phone_transport.dart';
import '../core/app_logger.dart';
import '../core/keep_alive.dart';
import '../domain/sensor_kind.dart';
import '../sensing/classify/classifier.dart';
import '../sensing/detection_engine.dart';
import '../sensing/math/vec3.dart';
import '../sensing/motion_sample.dart';
import '../settings/app_settings.dart';
import 'bluest_adapter.dart';
import 'event_store.dart';

/// Glue between the sources, the shared engine, the event store and the alert
/// (report §15.1). The UI only reads its state.
class MonitoringService extends ChangeNotifier {
  MonitoringService({
    required this.settings,
    required this.connection,
    required this.phone,
    required this.store,
    required this.alerts,
    required this.keepAlive,
  }) {
    _adapter = BlueStMotionAdapter(_onBleSample);
    connection.addSink(_adapter);
  }

  final AppSettings settings;
  final ConnectionManager connection;
  final PhoneTransport phone;
  final EventStore store;
  final AlertManager alerts;
  final KeepAlive keepAlive;
  late final BlueStMotionAdapter _adapter;

  DetectionEngine engine = DetectionEngine();
  bool running = false;
  DateTime? startedAt;
  int? _t0Ns;
  Timer? _ticker;
  int samplesAcc = 0;
  int samplesGyro = 0;
  bool _ownsKeepAlive = false;
  final List<StoredDetection> recent = [];

  /// Last event, provisional or final, for the live display.
  DetectionEvent? lastEvent;
  DetectionEvent? lastFinal;

  /// Bumped at every final event: lists reload.
  final ValueNotifier<int> eventsRevision = ValueNotifier<int>(0);

  DetectionMode get mode => settings.detectionMode ?? DetectionMode.phone;

  SourceProfile get _profile {
    if (connection.dataSource == DataSource.simulated) return SourceProfile.simulated.copyWith(nominalRateHz: 50);
    return mode == DetectionMode.phone
        ? SourceProfile.phone.copyWith(nominalRateHz: settings.samplingHz.toDouble())
        : SourceProfile.sensorTile;
  }

  bool get sourceIsSimulated => connection.dataSource == DataSource.simulated;

  DangerLevel get currentLevel => running ? engine.currentLevel : DangerLevel.normal;

  QualityReport get quality => engine.quality();

  bool get hasData => engine.framesProcessed > 0;

  /// Ready to start: phone mode needs nothing, SensorTile mode a connected board.
  bool get canStart => mode == DetectionMode.phone || connection.isReady;

  Future<void> loadRecent() async {
    try {
      recent
        ..clear()
        ..addAll(await store.listDetections(limit: 50));
      notifyListeners();
    } catch (e) {
      logger.w('Monitoraggio', 'Storico non caricato: $e');
    }
  }

  /// Starts monitoring with the selected mode. For the phone mode the caller
  /// connects the phone transport first (AppServices.startMonitoring).
  Future<void> start() async {
    if (running) return;
    engine = DetectionEngine(profile: _profile);
    engine.addListener(_onEvent);
    _adapter.reset();
    _t0Ns = null;
    samplesAcc = 0;
    samplesGyro = 0;
    lastEvent = null;
    phone.motionListener = _onPhoneSample;
    running = true;
    startedAt = DateTime.now();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => notifyListeners());
    try {
      await keepAlive.start('DYNAMIX: monitoraggio attivo',
          sensorsOnly: connection.dataSource == DataSource.phone);
      _ownsKeepAlive = true;
    } catch (_) {}
    logger.i('Monitoraggio', 'Avviato: ${engine.profile.name}, ${settings.samplingHz} Hz richiesti');
    notifyListeners();
  }

  Future<void> stop({bool keepService = false}) async {
    if (!running) return;
    running = false;
    engine.flush();
    engine.removeListener(_onEvent);
    phone.motionListener = null;
    _ticker?.cancel();
    _ticker = null;
    if (_ownsKeepAlive && !keepService) {
      await keepAlive.stop();
      _ownsKeepAlive = false;
    }
    logger.i('Monitoraggio', 'Fermato');
    notifyListeners();
  }

  int _rebase(int tNs) {
    final t0 = _t0Ns ??= tNs;
    return tNs - t0;
  }

  void _onPhoneSample(bool gyro, int tNs, double x, double y, double z) {
    if (!running || mode != DetectionMode.phone || connection.dataSource != DataSource.phone) return;
    if (gyro) {
      samplesGyro++;
    } else {
      samplesAcc++;
    }
    engine.ingest(MotionSample(gyro ? SampleKind.gyro : SampleKind.acc, _rebase(tNs), Vec3(x, y, z)));
  }

  void _onBleSample(MotionSample s) {
    if (!running || connection.dataSource == DataSource.phone) return;
    if (s.kind == SampleKind.gyro) {
      samplesGyro++;
    } else {
      samplesAcc++;
    }
    engine.ingest(MotionSample(s.kind, _rebase(s.tNs), s.v, flags: s.flags));
  }

  /// GPS speed (m/s) and its accuracy, when the location source is active.
  void ingestGps(int tNs, double speed, double accuracy) {
    if (!running) return;
    engine.ingest(MotionSample(SampleKind.gps, _rebase(tNs), Vec3(speed, accuracy, 0)));
  }

  void _onEvent(DetectionEvent e) {
    lastEvent = e;
    if (e.provisional) {
      notifyListeners();
      return;
    }
    lastFinal = e;
    unawaited(_persist(e));
  }

  Future<void> _persist(DetectionEvent e) async {
    if (e.level == DangerLevel.normal && !e.classification.alarm) {
      notifyListeners();
      return;
    }
    final stored = StoredDetection(
      atMs: DateTime.now().millisecondsSinceEpoch,
      source: sourceIsSimulated ? 'simulated' : e.source.kind.name,
      algoVersion: algorithmVersion,
      level: e.level.value,
      category: e.category.name,
      confidence: e.classification.confidence,
      quality: e.features.quality,
      alarm: e.classification.alarm,
      features: e.features.toJson(),
      classification: e.classification.toJson(),
      raw: [
        for (final r in e.raw) [r.tS, r.f.x, r.f.y, r.f.z, r.omega.x, r.omega.y, r.omega.z],
      ],
    );
    var id = 0;
    try {
      id = await store.insertDetection(stored);
      recent.insert(0, stored.copyWith(id: id));
      if (recent.length > 50) recent.removeLast();
      eventsRevision.value++;
    } catch (err) {
      logger.e('Monitoraggio', 'Evento non salvato: $err');
    }
    if (e.classification.alarm) {
      await alerts.trigger(
        detectionId: id == 0 ? -DateTime.now().millisecondsSinceEpoch : id,
        title: e.category.label,
        detail: '${e.level.label} · confidenza ${(e.classification.confidence * 100).round()}/100',
        dryRun: sourceIsSimulated || settings.smsDryRun,
      );
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    connection.removeSink(_adapter);
    super.dispose();
  }
}
