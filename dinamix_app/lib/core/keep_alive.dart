import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app_logger.dart';

const MethodChannel _platformChannel = MethodChannel('dinamix/keep_alive');

/// Android API level, null if the native side does not answer.
Future<int?> androidSdkInt() async {
  try {
    return await _platformChannel.invokeMethod<int>('sdkInt');
  } catch (e) {
    logger.w('Platform', 'Versione Android non disponibile: $e');
    return null;
  }
}

/// Keeps the process alive during long recordings through the native
/// foreground service (see android/.../RecordingService.kt).
abstract class KeepAlive {
  Future<void> start(String title);
  Future<void> stop();
}

class AndroidKeepAlive implements KeepAlive {
  @override
  Future<void> start(String title) async {
    try {
      await Permission.notification.request();
      await _platformChannel.invokeMethod<void>('start', {'title': title});
    } catch (e) {
      // Recording still works in foreground: warn, never fail the session.
      logger.w('KeepAlive', 'Servizio in primo piano non avviato: $e');
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _platformChannel.invokeMethod<void>('stop');
    } catch (e) {
      logger.w('KeepAlive', 'Arresto servizio fallito: $e');
    }
  }
}

class NoopKeepAlive implements KeepAlive {
  @override
  Future<void> start(String title) async {}

  @override
  Future<void> stop() async {}
}
