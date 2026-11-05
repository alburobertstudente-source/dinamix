import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/app_logger.dart';

/// Alarm sound: native, on the alarm stream at the maximum volume allowed by
/// Android, with vibration. The previous volume is restored when it stops.
abstract class AlarmPlayer {
  Future<void> start();
  Future<void> stop();
}

enum SmsOutcome { sent, noService, radioOff, failed, noPermission, unknown }

class SmsResult {
  const SmsResult(this.outcome, [this.detail = '']);
  final SmsOutcome outcome;
  final String detail;

  bool get ok => outcome == SmsOutcome.sent;

  /// Temporary network conditions: worth retrying.
  bool get retryable => outcome == SmsOutcome.noService || outcome == SmsOutcome.radioOff;

  @override
  String toString() => detail.isEmpty ? outcome.name : '${outcome.name}: $detail';
}

abstract class SmsSender {
  Future<bool> hasPermission();
  Future<bool> requestPermission();
  Future<SmsResult> send(String number, String text);
}

const MethodChannel _alertChannel = MethodChannel('dynamix/alert');

class NativeAlarmPlayer implements AlarmPlayer {
  @override
  Future<void> start() async {
    try {
      await _alertChannel.invokeMethod<void>('startAlarm');
    } catch (e) {
      logger.e('Allarme', 'Suono non avviato: $e');
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _alertChannel.invokeMethod<void>('stopAlarm');
    } catch (e) {
      logger.w('Allarme', 'Arresto del suono non riuscito: $e');
    }
  }
}

/// SmsManager through the native channel; the sent PendingIntent gives the result.
class NativeSmsSender implements SmsSender {
  @override
  Future<bool> hasPermission() async => Permission.sms.isGranted;

  @override
  Future<bool> requestPermission() async => (await Permission.sms.request()).isGranted;

  @override
  Future<SmsResult> send(String number, String text) async {
    if (!await hasPermission()) return const SmsResult(SmsOutcome.noPermission);
    try {
      final code = await _alertChannel
          .invokeMethod<String>('sendSms', {'number': number, 'text': text})
          .timeout(const Duration(seconds: 60));
      return switch (code) {
        'sent' => const SmsResult(SmsOutcome.sent),
        'no_service' => const SmsResult(SmsOutcome.noService),
        'radio_off' => const SmsResult(SmsOutcome.radioOff),
        _ => SmsResult(SmsOutcome.failed, code ?? ''),
      };
    } on PlatformException catch (e) {
      return SmsResult(SmsOutcome.failed, e.message ?? e.code);
    } catch (e) {
      // Timeout: the message may or may not have left the phone.
      return SmsResult(SmsOutcome.unknown, '$e');
    }
  }
}

/// Never sends anything: used in tests, simulation and dry-run mode.
class FakeSmsSender implements SmsSender {
  FakeSmsSender({this.results = const []});

  final List<SmsResult> results;
  final List<(String, String)> sent = [];
  bool permission = true;

  @override
  Future<bool> hasPermission() async => permission;
  @override
  Future<bool> requestPermission() async => permission;

  @override
  Future<SmsResult> send(String number, String text) async {
    sent.add((number, text));
    final i = sent.length - 1;
    return i < results.length ? results[i] : const SmsResult(SmsOutcome.sent);
  }
}

class SilentAlarmPlayer implements AlarmPlayer {
  int starts = 0;
  int stops = 0;
  bool get playing => starts > stops;
  @override
  Future<void> start() async => starts++;
  @override
  Future<void> stop() async => stops++;
}
