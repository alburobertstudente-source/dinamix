import 'package:flutter/foundation.dart';

import '../ble/connection_manager.dart';
import '../ble/device_scanner.dart';
import '../ble/transport/ble_transport.dart';
import '../ble/transport/fbp_transport.dart';
import '../ble/transport/phone_transport.dart';
import '../ble/transport/simulated_transport.dart';
import '../core/app_logger.dart';
import '../core/keep_alive.dart';
import '../data/sensor_hub.dart';
import '../data/session_recorder.dart';
import '../data/session_store.dart';
import '../domain/sensor_kind.dart';
import '../export/session_exporter.dart';
import '../alert/alert_manager.dart';
import '../alert/platform_alert.dart';
import '../monitoring/event_store.dart';
import '../monitoring/monitoring_service.dart';
import '../profile/profile.dart';
import '../settings/app_settings.dart';

const String appVersion = '2.0.0';

/// Composition root: creates the services and connects them.
class AppServices {
  AppServices._({
    required this.settings,
    required this.store,
    required this.connection,
    required this.scanner,
    required this.hub,
    required this.recorder,
    required this.exporter,
    required BleTransport hardware,
    required this.simulator,
    required this.phone,
    required this.events,
    required this.profiles,
    required this.alerts,
    required this.monitoring,
  }) : _hardware = hardware;

  final AppSettings settings;
  final SessionStore store;
  final ConnectionManager connection;
  final DeviceScanner scanner;
  final SensorHub hub;
  final SessionRecorder recorder;
  final SessionExporter exporter;
  final BleTransport _hardware;
  final SimulatedTransport simulator;
  final PhoneTransport phone;
  final EventStore events;
  final ProfileService profiles;
  final AlertManager alerts;
  final MonitoringService monitoring;

  /// Sessions found open at startup, reported once to the user.
  int recoveredSessions = 0;

  /// Bumped when sessions are renamed or deleted, so that open lists reload.
  final ValueNotifier<int> sessionsRevision = ValueNotifier<int>(0);

  static Future<AppServices> create({
    required AppSettings settings,
    required SessionStore store,
    required KeepAlive keepAlive,
    PhoneSensorSource? phoneSensors,
    EventStore? events,
    SecureKeyValue? secure,
    AlarmPlayer? alarmPlayer,
    SmsSender? smsSender,
  }) async {
    final eventStore = events ?? MemoryEventStore();
    final profiles = ProfileService(secure ?? MemoryKeyValue());
    await profiles.load();
    final alerts = AlertManager(
      store: eventStore,
      profiles: profiles,
      player: alarmPlayer ?? SilentAlarmPlayer(),
      sms: smsSender ?? FakeSmsSender(),
    );
    final hardware = FbpTransport();
    final simulator = SimulatedTransport();
    final phone = PhoneTransport(sensors: phoneSensors);
    final BleTransport initial = settings.simulationMode ? simulator : hardware;
    final connection = ConnectionManager(initial);
    final hub = SensorHub(refreshHz: settings.chartRefreshHz);
    final recorder = SessionRecorder(store, keepAlive: keepAlive);
    final monitoring = MonitoringService(
      settings: settings,
      connection: connection,
      phone: phone,
      store: eventStore,
      alerts: alerts,
      keepAlive: keepAlive,
    );
    final services = AppServices._(
      settings: settings,
      store: store,
      connection: connection,
      scanner: DeviceScanner(initial),
      hub: hub,
      recorder: recorder,
      exporter: SessionExporter(store),
      hardware: hardware,
      simulator: simulator,
      phone: phone,
      events: eventStore,
      profiles: profiles,
      alerts: alerts,
      monitoring: monitoring,
    );
    connection
      ..addSink(hub)
      ..addSink(recorder);
    connection.linkEvents.listen(recorder.onLinkEvent);
    connection.onReady = services._onDeviceReady;
    services._applySettings();
    settings.addListener(services._applySettings);
    services.recoveredSessions = await store.recoverInterrupted();
    await monitoring.loadRecent();
    if (services.recoveredSessions > 0) {
      logger.w('Logger', '${services.recoveredSessions} sessioni interrotte recuperate');
    }
    return services;
  }

  int _lastRefreshHz = 0;

  void _applySettings() {
    connection
      ..autoReconnect = settings.autoReconnect
      ..highThroughput = settings.highThroughput
      ..disabledKinds = settings.disabledKinds;
    if (_lastRefreshHz != settings.chartRefreshHz) {
      _lastRefreshHz = settings.chartRefreshHz;
      hub.setRefreshHz(settings.chartRefreshHz);
    }
  }

  void _onDeviceReady(DeviceRef device) {
    if (connection.isDemo) return; // Never mixed with real devices.
    settings.rememberDevice(KnownDevice(
      device.id,
      device.name,
      DateTime.now().millisecondsSinceEpoch,
      device.advertising?.firmwareLabel ?? '',
    ));
  }

  /// Blocked during a recording, so a session cannot change data source.
  Future<bool> setSimulationMode(bool enabled) async {
    if (recorder.isActive) return false;
    settings
      ..setPhoneDemo(false)
      ..setSimulationMode(enabled);
    await _switchTo(enabled ? simulator : _hardware);
    logger.i('App', enabled ? 'Modalità simulazione attiva' : 'Modalità hardware attiva');
    return true;
  }

  Future<void> _switchTo(BleTransport transport) async {
    await connection.disconnect();
    await scanner.stop();
    hub.clear();
    connection.switchTransport(transport);
    scanner.switchTransport(transport);
  }

  /// Demo mode: starts reading the sensors of this phone.
  Future<bool> enterPhoneDemo() async {
    if (recorder.isActive) return false;
    settings.setPhoneDemo(true);
    await _switchTo(phone);
    logger.i('App', 'Demo con i sensori del telefono');
    await connection.connect(
        const DeviceRef(PhoneTransport.deviceId, PhoneTransport.deviceName));
    return connection.isReady;
  }

  Future<bool> exitPhoneDemo() async {
    if (recorder.isActive) return false;
    settings.setPhoneDemo(false);
    await _switchTo(settings.simulationMode ? simulator : _hardware);
    return true;
  }

  Future<void> connectTo(DeviceRef device) async {
    await scanner.stop();
    hub.clear();
    await connection.connect(device);
  }

  Future<void> startRecording(String name) async {
    final device = connection.device;
    if (device == null || !connection.isReady) return;
    await recorder.start(
      name: name,
      deviceName: device.name,
      deviceId: device.id,
      firmware: device.advertising?.firmwareLabel ?? 'Sconosciuto',
      source: connection.dataSource,
      config: {
        'sensors': [
          for (final kind in connection.activeKinds)
            {
              'id': kind.id,
              'label': kind.label,
              'channels': [
                for (final c in kind.channels) {'key': c.key, 'unit': c.unit},
              ],
            },
        ],
        'board': device.advertising?.boardName ?? 'Sconosciuta',
        'mtu': connection.mtu,
        'high_throughput': connection.highThroughput,
        'note': 'Frequenza stabilita dal firmware; misurata sul telefono.',
      },
    );
  }

  SensorReading? get batteryReading => hub.latest(SensorKind.battery);

  /// Starts the detection with the chosen mode (report §25.7). Returns a message
  /// when it cannot start.
  Future<String?> startMonitoring() async {
    final mode = settings.detectionMode ?? DetectionMode.phone;
    if (mode == DetectionMode.phone) {
      final sensors = phone.sensors;
      if (sensors is DevicePhoneSensors) sensors.motionRateHz = settings.samplingHz;
      if (!(connection.dataSource == DataSource.phone && connection.isReady)) {
        final ok = await enterPhoneDemo();
        if (!ok) return 'Sensori del telefono non disponibili.';
      }
    } else if (!connection.isReady || connection.dataSource == DataSource.phone) {
      return 'Collega prima la SensorTile dalla scheda Sensori.';
    }
    await monitoring.start();
    return null;
  }

  Future<void> stopMonitoring() async {
    await monitoring.stop(keepService: recorder.isActive);
  }

  /// Applies a new mode: stops the monitoring and the current source.
  Future<void> changeMode(DetectionMode mode) async {
    if (recorder.isActive || alerts.active) return;
    await stopMonitoring();
    settings.setDetectionMode(mode);
    if (mode == DetectionMode.sensorTile && settings.phoneDemo) await exitPhoneDemo();
  }

  /// Profile deletion (report §13.1): profile, contact and app choices.
  Future<void> deleteProfile({bool alsoData = false}) async {
    await stopMonitoring();
    await profiles.deleteAll();
    await settings.resetOnboarding();
    if (alsoData) {
      await events.deleteAll();
      await store.deleteAll();
      monitoring.recent.clear();
      sessionsRevision.value++;
    }
  }

  void dispose() {
    settings.removeListener(_applySettings);
  }
}
