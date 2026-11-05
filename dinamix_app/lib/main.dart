import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/dinamix_app.dart';
import 'app/services.dart';
import 'core/app_error.dart';
import 'core/keep_alive.dart';
import 'data/sqlite_session_store.dart';
import 'settings/app_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    ErrorCenter.instance.reportAny(details.exception, tag: 'Flutter');
  };

  final prefs = await SharedPreferences.getInstance();
  final store = await SqliteSessionStore.open();
  final services = await AppServices.create(
    settings: AppSettings(prefs),
    store: store,
    keepAlive: AndroidKeepAlive(),
  );
  runApp(DinamixApp(services: services));
}
