import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:dinamix/app/dinamix_app.dart';
import 'package:dinamix/app/services.dart';
import 'package:dinamix/ble/connection_manager.dart';
import 'package:dinamix/ble/device_scanner.dart';
import 'package:dinamix/ble/transport/phone_transport.dart';
import 'package:dinamix/ble/transport/simulated_transport.dart';
import 'package:dinamix/core/keep_alive.dart';
import 'package:dinamix/data/session_recorder.dart';
import 'package:dinamix/domain/sensor_kind.dart';
import 'package:dinamix/session/live_session.dart';
import 'package:dinamix/settings/app_settings.dart';
import 'package:dinamix/ui/screens/activity_screen.dart';
import 'package:dinamix/alert/alert_manager.dart';
import 'package:dinamix/monitoring/monitoring_service.dart';
import 'package:dinamix/profile/profile.dart';
import 'package:dinamix/ui/screens/detection/alarm_overlay.dart';
import 'package:dinamix/ui/screens/detection/dashboard_screen.dart';
import 'package:dinamix/ui/screens/detection/detection_screen.dart';
import 'package:dinamix/ui/screens/onboarding/mode_screen.dart';
import 'package:dinamix/ui/screens/onboarding/registration_screen.dart';
import 'package:dinamix/ui/screens/live_screen.dart';
import 'package:dinamix/ui/screens/session_screen.dart';
import 'package:dinamix/ui/screens/summary_screen.dart';
import 'package:dinamix/ui/theme.dart';
import 'package:dinamix/ui/widgets/effects.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

/// Renders the main screens to PNG for visual review. Runs only with:
/// flutter test --update-goldens --dart-define=SCREENSHOTS=true test/screenshots_test.dart
const bool _enabled = bool.fromEnvironment('SCREENSHOTS');

Future<void> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final dir = '$root/bin/cache/artifacts/material_fonts';
  Future<ByteData> read(String name) async {
    final bytes = await File('$dir/$name').readAsBytes();
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }

  final roboto = FontLoader('Roboto');
  for (final name in ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf']) {
    if (File('$dir/$name').existsSync()) roboto.addFont(read(name));
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons')..addFont(read('MaterialIcons-Regular.otf'));
  await icons.load();
}

class _NoSensors implements PhoneSensorSource {
  @override
  Stream<Vector3Sample> accelerometer() => const Stream.empty();
  @override
  Stream<Vector3Sample> gyroscope() => const Stream.empty();
  @override
  Stream<Vector3Sample> magnetometer() => const Stream.empty();
  @override
  Stream<double> barometer() => const Stream.empty();
}

void main() {
  late AppServices services;

  setUpAll(() async {
    if (_enabled) await _loadFonts();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({'simulation': true, 'detection_mode': 'phone'});
    final prefs = await SharedPreferences.getInstance();
    services = await AppServices.create(
      settings: AppSettings(prefs),
      store: MemorySessionStore(),
      keepAlive: NoopKeepAlive(),
      phoneSensors: _NoSensors(),
    );
    await services.profiles.saveProfile(const UserProfile(firstName: 'Giulia', lastName: 'Rossi', age: 17));
  });

  tearDown(() => services.hub.dispose());

  Widget app(Widget home) => MultiProvider(
        providers: [
          Provider<AppServices>.value(value: services),
          ChangeNotifierProvider<AppSettings>.value(value: services.settings),
          ChangeNotifierProvider<ConnectionManager>.value(value: services.connection),
          ChangeNotifierProvider<DeviceScanner>.value(value: services.scanner),
          ChangeNotifierProvider<SessionRecorder>.value(value: services.recorder),
          ChangeNotifierProvider<NavController>(create: (_) => NavController()),
          ChangeNotifierProvider<ProfileService>.value(value: services.profiles),
          ChangeNotifierProvider<MonitoringService>.value(value: services.monitoring),
          ChangeNotifierProvider<AlertManager>.value(value: services.alerts),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.dark),
          builder: (context, child) => Stack(
            fit: StackFit.expand,
            children: [const AuroraBackground(), if (child != null) child, const AlarmOverlay()],
          ),
          home: home,
        ),
      );

  Future<void> shot(WidgetTester tester, String name, Widget screen,
      {Future<void> Function()? before}) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    debugDisableShadows = false;
    if (before != null) await before();
    await tester.pumpWidget(app(screen));
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/$name.png'));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    debugDisableShadows = true;
  }

  // Waits until the connection reaches the wanted state. Part of the
  // connection work completes on the fake test clock and part on the real
  // event loop (stream cancellation), so both are advanced in turn. The state
  // is polled because the returned futures do not complete in the fake zone.
  Future<void> pumpUntil(WidgetTester tester, bool Function() condition, String what) async {
    for (var i = 0; i < 50 && !condition(); i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    }
    expect(condition(), isTrue, reason: 'Simulatore: $what non completata');
  }

  Future<void> connectSimulator(WidgetTester tester) async {
    services.connection
        .connect(const DeviceRef(SimulatedTransport.deviceId, 'Simulatore DinamiX'))
        .ignore();
    await pumpUntil(tester, () => services.connection.isReady, 'connessione');
  }

  // Also stops the simulator's periodic timers, which would otherwise fail
  // the test as still pending.
  Future<void> disconnect(WidgetTester tester) async {
    services.connection.disconnect().ignore();
    await pumpUntil(tester, () => services.connection.phase == ConnectionPhase.idle, 'disconnessione');
  }

  testWidgets('home', skip: !_enabled, (tester) async {
    await shot(tester, 'home', const DashboardScreen());
  });

  testWidgets('registrazione', skip: !_enabled, (tester) async {
    await services.profiles.deleteAll();
    await shot(tester, 'registration', const RegistrationScreen());
  });

  testWidgets('modalita', skip: !_enabled, (tester) async {
    await shot(tester, 'mode', const ModeScreen(onboarding: true));
  });

  testWidgets('diagnostica rilevamento', skip: !_enabled, (tester) async {
    await shot(tester, 'detection', const DetectionScreen());
  });

  testWidgets('allarme', skip: !_enabled, (tester) async {
    await shot(tester, 'alarm', const DashboardScreen(), before: () async {
      await services.alerts.trigger(
          detectionId: 99, title: 'Possibile caduta della persona', detail: 'Livello 3 · confidenza 62/100', dryRun: true);
    });
    await services.alerts.cancel();
  });

  testWidgets('attivita', skip: !_enabled, (tester) async {
    await connectSimulator(tester);
    await shot(tester, 'activity', const ActivityScreen());
    await disconnect(tester);
  });

  testWidgets('sessione', skip: !_enabled, (tester) async {
    await connectSimulator(tester);
    final session = LiveSessionController(impactThresholdG: 4);
    final start = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < 200; i++) {
      final t = start + i * 40;
      session.ingest(reading(SensorKind.accelerometer, t,
          [220 * math.sin(i / 7), 240 + 150 * math.sin(i / 3), 1000 + 180 * math.cos(i / 5)]));
      session.ingest(reading(SensorKind.gyroscope, t, [90, 60, 40]));
    }
    await shot(
      tester,
      'session',
      SessionScreen(activity: RideActivity.mountainBike, controller: session, record: false),
    );
    // The session screen starts the monitoring: stop it (and its UI ticker).
    unawaited(services.monitoring.stop());
    await disconnect(tester);
  });

  testWidgets('riepilogo', skip: !_enabled, (tester) async {
    await shot(
      tester,
      'summary',
      const SummaryScreen(
        summary: SessionSummary(
          activity: RideActivity.mountainBike,
          duration: Duration(minutes: 12, seconds: 42),
          peakG: 6.84,
          meanG: 1.12,
          peakRotationDps: 412,
          impacts: 3,
          samples: 38100,
          sessionId: 1,
          source: DataSource.phone,
        ),
      ),
    );
  });

  testWidgets('live', skip: !_enabled, (tester) async {
    await connectSimulator(tester);
    final now = DateTime.now().millisecondsSinceEpoch;
    for (var i = 400; i >= 0; i--) {
      final spike = i == 120 ? 5000.0 : 0.0;
      services.hub.ingest(reading(SensorKind.accelerometer, now - i * 25,
          [140 * math.sin(i / 9) + spike, 110 * math.cos(i / 6), 1000 + 70 * math.sin(i / 4)]));
    }
    await shot(tester, 'live', const LiveScreen());
    await disconnect(tester);
  });
}
