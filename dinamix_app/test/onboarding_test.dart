import 'package:dinamix/app/dinamix_app.dart';
import 'package:dinamix/app/services.dart';
import 'package:dinamix/core/keep_alive.dart';
import 'package:dinamix/profile/profile.dart';
import 'package:dinamix/settings/app_settings.dart';
import 'package:dinamix/ui/screens/detection/dashboard_screen.dart';
import 'package:dinamix/ui/screens/onboarding/mode_screen.dart';
import 'package:dinamix/ui/screens/onboarding/registration_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

void main() {
  Future<AppServices> make(MemoryKeyValue kv, Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    final p = await SharedPreferences.getInstance();
    return AppServices.create(
      settings: AppSettings(p),
      store: MemorySessionStore(),
      keepAlive: NoopKeepAlive(),
      secure: kv,
    );
  }

  testWidgets('primo avvio: registrazione → modalità → dashboard; al riavvio niente registrazione',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final kv = MemoryKeyValue();
    final prefs = <String, Object>{'simulation': true};
    final services = await make(kv, prefs);

    await tester.pumpWidget(DinamixApp(services: services));
    await tester.pump(const Duration(milliseconds: 1500)); // splash
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(RegistrationScreen), findsOneWidget);

    // Invalid age: the button stays disabled.
    await tester.enterText(find.byKey(const Key('field_first')), 'Giulia');
    await tester.enterText(find.byKey(const Key('field_last')), 'Rossi');
    await tester.enterText(find.byKey(const Key('field_age')), '130');
    await tester.pump();
    await tester.tap(find.byKey(const Key('register_button')), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 500));
    expect(services.profiles.registered, isFalse);

    await tester.enterText(find.byKey(const Key('field_age')), '17');
    await tester.pump();
    await tester.tap(find.byKey(const Key('register_button')));
    await tester.pump(const Duration(milliseconds: 600));
    expect(services.profiles.profile?.fullName, 'Giulia Rossi');
    expect(find.byType(ModeScreen), findsOneWidget);

    await tester.tap(find.byKey(const Key('mode_phone')));
    await tester.pump(const Duration(milliseconds: 600));
    expect(services.settings.detectionMode, DetectionMode.phone);
    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(find.text('Ciao, Giulia'), findsOneWidget);

    // Restart with the same storage: straight to the dashboard.
    await tester.pumpWidget(const SizedBox());
    final again = await make(kv, {'simulation': true, 'detection_mode': 'phone'});
    await tester.pumpWidget(DinamixApp(services: again));
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(RegistrationScreen), findsNothing);
    expect(find.byType(DashboardScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 4));
    services.hub.dispose();
    again.hub.dispose();
  });
}
