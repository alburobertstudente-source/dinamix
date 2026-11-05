import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/dinamix_app.dart';
import 'app/services.dart';
import 'core/app_error.dart';
import 'core/keep_alive.dart';
import 'alert/platform_alert.dart';
import 'data/sqlite_session_store.dart';
import 'monitoring/event_store.dart';
import 'profile/profile.dart';
import 'settings/app_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    ErrorCenter.instance.reportAny(details.exception, tag: 'Flutter');
  };
  // Uncaught asynchronous errors: logged, never a crash (report §18.3).
  PlatformDispatcher.instance.onError = (error, stack) {
    ErrorCenter.instance.reportAny(error, tag: 'Async');
    return true;
  };

  final prefs = await SharedPreferences.getInstance();
  final store = await SqliteSessionStore.open();
  final services = await AppServices.create(
    settings: AppSettings(prefs),
    store: store,
    keepAlive: AndroidKeepAlive(),
    events: await SqliteEventStore.open(),
    secure: KeystoreKeyValue(),
    alarmPlayer: NativeAlarmPlayer(),
    smsSender: NativeSmsSender(),
  );
  runApp(DinamixApp(services: services));
}
