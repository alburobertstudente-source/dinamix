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
import '../settings/app_settings.dart';

const String appVersion = '1.0.0';

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

  /// Sessions found open at startup, reported once to the user.
  int recoveredSessions = 0;

  /// Bumped when sessions are renamed or deleted, so that open lists reload.
  final ValueNotifier<int> sessionsRevision = ValueNotifier<int>(0);

  static Future<AppServices> create({
    required AppSettings settings,
    required SessionStore store,
    required KeepAlive keepAlive,
    PhoneSensorSource? phoneSensors,
  }) async {
    final hardware = FbpTransport();
    final simulator = SimulatedTransport();
    final phone = PhoneTransport(sensors: phoneSensors);
    final BleTransport initial = settings.simulationMode ? simulator : hardware;
    final connection = ConnectionManager(initial);
    final hub = SensorHub(refreshHz: settings.chartRefreshHz);
    final recorder = SessionRecorder(store, keepAlive: keepAlive);
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
    );
    connection
      ..addSink(hub)
      ..addSink(recorder);
    connection.linkEvents.listen(recorder.onLinkEvent);
    connection.onReady = services._onDeviceReady;
    services._applySettings();
    settings.addListener(services._applySettings);
    services.recoveredSessions = await store.recoverInterrupted();
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

  void dispose() {
    settings.removeListener(_applySettings);
  }
}
