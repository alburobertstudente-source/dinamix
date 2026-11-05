// End-to-end test on a real Android device or emulator (report §18.2):
// flutter test integration_test/app_flow_test.dart -d <device>
import 'package:dinamix/alert/alert_manager.dart';
import 'package:dinamix/app/services.dart';
import 'package:dinamix/main.dart' as app;
import 'package:dinamix/monitoring/monitoring_service.dart';
import 'package:dinamix/ui/screens/detection/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

Future<void> pumpFor(WidgetTester tester, Duration d) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> waitFor(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 20)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return;
  }
  expect(finder, findsWidgets, reason: 'non comparso entro $timeout');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('primo avvio, registrazione, monitoraggio, allarme di prova', (tester) async {
    app.main();
    // Splash, then registration (fresh install) or dashboard (already registered).
    await pumpFor(tester, const Duration(seconds: 3));
    if (find.byKey(const Key('field_first')).evaluate().isNotEmpty) {
      await tester.enterText(find.byKey(const Key('field_first')), 'Test');
      await tester.enterText(find.byKey(const Key('field_last')), 'Emulatore');
      await tester.enterText(find.byKey(const Key('field_age')), '30');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('register_button')));
      await pumpFor(tester, const Duration(seconds: 1));
    }
    if (find.byKey(const Key('mode_phone')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const Key('mode_phone')));
      await pumpFor(tester, const Duration(seconds: 1));
    }
    await waitFor(tester, find.byType(DashboardScreen));
    final context = tester.element(find.byType(DashboardScreen));
    final services = context.read<AppServices>();
    final monitoring = context.read<MonitoringService>();

    // Monitoring with the phone (emulator virtual) sensors.
    await tester.tap(find.byKey(const Key('monitoring_toggle')));
    await pumpFor(tester, const Duration(seconds: 6));
    expect(monitoring.running, isTrue);
    expect(monitoring.engine.framesProcessed, greaterThan(50), reason: 'nessun campione dai sensori');
    // ignore: avoid_print
    print('Frequenza misurata: ${monitoring.engine.measuredRateHz.toStringAsFixed(1)} Hz, '
        'qualità ${(monitoring.quality.value * 100).round()}/100');

    // Alarm test in dry run: sound, overlay, hold to cancel, nothing sent.
    await services.alerts.trigger(detectionId: -1, title: 'Prova', detail: 'integration test', dryRun: true);
    await pumpFor(tester, const Duration(seconds: 2));
    expect(services.alerts.phase, AlertPhase.alarming);
    expect(find.byKey(const Key('hold_to_cancel')), findsOneWidget);
    final gesture = await tester.startGesture(tester.getCenter(find.byKey(const Key('hold_to_cancel'))));
    await pumpFor(tester, const Duration(milliseconds: 1500));
    await gesture.up();
    await pumpFor(tester, const Duration(seconds: 1));
    expect(services.alerts.phase, AlertPhase.finished);
    expect(services.alerts.current?.dryRun, isTrue);
    await tester.tap(find.text('Chiudi'));
    await pumpFor(tester, const Duration(milliseconds: 500));

    // Main screens open without errors.
    for (final label in ['Diagnostica', 'Storico']) {
      await tester.tap(find.text(label).first);
      await pumpFor(tester, const Duration(seconds: 2));
      await tester.pageBack();
      await pumpFor(tester, const Duration(seconds: 1));
    }
    await tester.tap(find.byTooltip('Impostazioni'));
    await pumpFor(tester, const Duration(seconds: 2));
    expect(find.text('Emergency Contact'), findsWidgets);
    await tester.pageBack();
    await pumpFor(tester, const Duration(seconds: 1));

    await tester.tap(find.byKey(const Key('monitoring_toggle')));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(monitoring.running, isFalse);
  });
}
