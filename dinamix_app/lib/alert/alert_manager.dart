import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/app_logger.dart';
import '../monitoring/event_store.dart';
import '../profile/profile.dart';
import 'platform_alert.dart';

enum AlertPhase { idle, alarming, countdown, sending, finished }

/// Alert procedure (report §12.2): sound for 30 s, countdown to 60 s from the
/// detection, then the SMS to the emergency contact unless cancelled.
///
/// - One alert per detection: the store refuses a second alert row for the same
///   event (idempotency) and a sent SMS is never sent again.
/// - Dry run: simulated sources or the dry-run setting never call the SMS API.
class AlertManager extends ChangeNotifier {
  AlertManager({
    required this.store,
    required this.profiles,
    required this.player,
    required this.sms,
    this.soundDuration = const Duration(seconds: 30),
    this.countdown = const Duration(seconds: 60),
    this.retryDelays = const [Duration(seconds: 30), Duration(seconds: 60), Duration(seconds: 120), Duration(seconds: 300)],
    int Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  final EventStore store;
  final ProfileService profiles;
  final AlarmPlayer player;
  final SmsSender sms;
  final Duration soundDuration;
  final Duration countdown;
  final List<Duration> retryDelays;
  final int Function() _clock;

  AlertPhase phase = AlertPhase.idle;
  StoredAlert? current;
  String? title;
  String? detail;
  String? outcome;
  int _startedMs = 0;
  bool _soundOn = false;
  final List<Timer> _timers = [];
  final Set<int> _handled = {};

  bool get active => phase == AlertPhase.alarming || phase == AlertPhase.countdown || phase == AlertPhase.sending;

  /// Seconds left before the SMS (0 when not counting).
  int get secondsLeft {
    if (phase != AlertPhase.alarming && phase != AlertPhase.countdown) return 0;
    final left = countdown.inMilliseconds - (_clock() - _startedMs);
    return (left / 1000).ceil().clamp(0, countdown.inSeconds);
  }

  bool get soundOn => _soundOn;

  /// Starts the procedure for a detection. Returns false if ignored (another
  /// alert active, or this detection already handled).
  Future<bool> trigger({
    required int detectionId,
    required String title,
    required String detail,
    required bool dryRun,
  }) async {
    if (active || _handled.contains(detectionId)) return false;
    _handled.add(detectionId);
    _startedMs = _clock();
    var alert = StoredAlert(
      detectionId: detectionId,
      state: AlertState.alarming,
      startedAtMs: _startedMs,
      dryRun: dryRun,
    );
    final id = await store.insertAlert(alert);
    if (id == 0) return false; // Already in the store: never twice.
    alert = alert.copyWith(id: id);
    current = alert;
    this.title = title;
    this.detail = detail;
    outcome = null;
    phase = AlertPhase.alarming;
    _soundOn = true;
    await player.start();
    logger.w('Allarme', 'Allerta avviata per l\'evento $detectionId${dryRun ? ' (prova, nessun SMS)' : ''}');
    _timers
      ..add(Timer(soundDuration, _endSound))
      ..add(Timer(countdown, _countdownElapsed))
      ..add(Timer.periodic(const Duration(milliseconds: 500), (_) => notifyListeners()));
    notifyListeners();
    return true;
  }

  Future<void> _endSound() async {
    if (!_soundOn) return;
    _soundOn = false;
    if (phase == AlertPhase.alarming) phase = AlertPhase.countdown;
    notifyListeners();
    await player.stop();
    if (phase == AlertPhase.countdown) await _save(AlertState.countdown);
  }

  /// "Sto bene": stops everything, nothing is sent.
  Future<void> cancel() async {
    if (!active || phase == AlertPhase.sending) return;
    _clearTimers();
    if (_soundOn) {
      _soundOn = false;
      await player.stop();
    }
    phase = AlertPhase.finished;
    outcome = 'Allerta annullata. Nessun messaggio inviato.';
    await _save(AlertState.cancelled, ended: true);
    logger.i('Allarme', 'Allerta annullata dall\'utente');
    notifyListeners();
  }

  Future<void> _countdownElapsed() async {
    _clearTimers();
    if (_soundOn) {
      _soundOn = false;
      await player.stop();
    }
    final alert = current;
    if (alert == null) return;
    final contact = profiles.contact;
    if (alert.dryRun) {
      phase = AlertPhase.finished;
      outcome = 'Prova: il messaggio NON è stato inviato.\n"${alertMessage(profiles.profile)}"';
      await _save(AlertState.dryRun, ended: true, result: 'dry_run');
      notifyListeners();
      return;
    }
    if (contact == null || !contact.enabled) {
      phase = AlertPhase.finished;
      outcome = 'Nessun contatto di emergenza attivo: messaggio non inviato.';
      await _save(AlertState.failed, ended: true, result: 'no_contact');
      notifyListeners();
      return;
    }
    phase = AlertPhase.sending;
    notifyListeners();
    await _send(contact, 0, repeat: false);
  }

  Future<void> _send(EmergencyContact contact, int attempt, {required bool repeat}) async {
    final text = alertMessage(profiles.profile) + (repeat ? ' (ripetizione)' : '');
    final result = await sms.send(contact.number, text);
    final attempts = (current?.smsAttempts ?? 0) + 1;
    current = current?.copyWith(smsAttempts: attempts, smsResult: result.toString());
    logger.i('Allarme', 'SMS tentativo $attempts: $result');
    if (result.ok) {
      phase = AlertPhase.finished;
      outcome = 'Messaggio inviato a ${contact.name}.';
      await _save(AlertState.sent, ended: true, result: result.toString());
    } else if (result.outcome == SmsOutcome.unknown && !repeat) {
      // Unknown outcome: one marked repetition, because a lost alert costs more
      // than a duplicate (report §12.6).
      await _save(AlertState.unknown, result: result.toString());
      await _send(contact, attempt, repeat: true);
      return;
    } else if (result.retryable && attempt < retryDelays.length) {
      outcome = 'Rete non disponibile: nuovo tentativo tra ${retryDelays[attempt].inSeconds} s.';
      await _save(AlertState.failed, result: result.toString());
      _timers.add(Timer(retryDelays[attempt], () => _send(contact, attempt + 1, repeat: repeat)));
    } else {
      phase = AlertPhase.finished;
      outcome = switch (result.outcome) {
        SmsOutcome.noPermission => 'Permesso SMS mancante: messaggio non inviato.',
        _ => 'Invio non riuscito ($result).',
      };
      await _save(AlertState.failed, ended: true, result: result.toString());
    }
    notifyListeners();
  }

  Future<void> _save(AlertState state, {bool ended = false, String? result}) async {
    final a = current;
    if (a == null) return;
    current = a.copyWith(state: state, endedAtMs: ended ? _clock() : null, smsResult: result);
    try {
      await store.updateAlert(current!);
    } catch (e) {
      logger.e('Allarme', 'Stato allerta non salvato: $e');
    }
  }

  /// Closes the result panel.
  void dismiss() {
    if (active) return;
    phase = AlertPhase.idle;
    current = null;
    notifyListeners();
  }

  void _clearTimers() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
  }

  @override
  void dispose() {
    _clearTimers();
    super.dispose();
  }
}
