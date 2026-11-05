import 'package:dinamix/alert/alert_manager.dart';
import 'package:dinamix/alert/platform_alert.dart';
import 'package:dinamix/monitoring/event_store.dart';
import 'package:dinamix/profile/profile.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> waitFor(bool Function() condition, {int ms = 2000}) async {
  final sw = Stopwatch()..start();
  while (!condition() && sw.elapsedMilliseconds < ms) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  group('Validazione del profilo', () {
    test('nome e cognome', () {
      expect(validateName('Maria', 'nome'), isNull);
      expect(validateName("D'Angelo-Rossi", 'cognome'), isNull);
      expect(validateName('  Élodie  ', 'nome'), isNull);
      expect(validateName('', 'nome'), isNotNull);
      expect(validateName('   ', 'nome'), isNotNull);
      expect(validateName('R2D2', 'nome'), isNotNull);
      expect(validateName('a' * 51, 'nome'), isNotNull);
      expect(validateName("'-", 'nome'), isNotNull);
    });

    test('età intera tra 1 e 120', () {
      expect(validateAge('17'), isNull);
      expect(validateAge('120'), isNull);
      for (final bad in ['', '0', '121', '-3', '12.5', 'abc', '1e2']) {
        expect(validateAge(bad), isNotNull, reason: bad);
      }
    });

    test('numero di telefono: normalizzazione E.164 e blocco dei numeri di emergenza', () {
      expect(normalizePhoneNumber('333 123 4567'), '+393331234567');
      expect(normalizePhoneNumber('0039 333-1234567'), '+393331234567');
      expect(normalizePhoneNumber('+44 7911 123456'), '+447911123456');
      expect(normalizePhoneNumber('06 1234 5678'), '+390612345678');
      expect(normalizePhoneNumber('12ab'), isNull);
      for (final n in ['112', '118', '113', '1515']) {
        expect(validatePhoneNumber(n), isNotNull, reason: n);
      }
      expect(validatePhoneNumber('+39 333 1234567'), isNull);
    });

    test('profilo e contatto salvati e cancellati', () async {
      final kv = MemoryKeyValue();
      final service = ProfileService(kv);
      await service.load();
      expect(service.registered, isFalse);
      await service.saveProfile(const UserProfile(firstName: 'Anna', lastName: 'Bianchi', age: 30));
      await service.saveContact(const EmergencyContact(name: 'Luca', number: '+393331234567', enabled: true));
      final again = ProfileService(kv);
      await again.load();
      expect(again.profile?.fullName, 'Anna Bianchi');
      expect(again.contactReady, isTrue);
      await again.deleteAll();
      expect(kv.values, isEmpty);
    });

    test('testo del messaggio come da specifica', () {
      expect(alertMessage(const UserProfile(firstName: 'Anna', lastName: 'Bianchi', age: 30)),
          "DYNAMIX: ALLERTA! Anna Bianchi ha ricevuto una botta forte e non ha disattivato l'allarme.");
    });
  });

  group('Allerta', () {
    late ProfileService profiles;
    late MemoryEventStore store;
    late SilentAlarmPlayer player;

    setUp(() async {
      profiles = ProfileService(MemoryKeyValue());
      await profiles.saveProfile(const UserProfile(firstName: 'Anna', lastName: 'Bianchi', age: 30));
      await profiles.saveContact(const EmergencyContact(name: 'Luca', number: '+393331234567', enabled: true));
      store = MemoryEventStore();
      player = SilentAlarmPlayer();
    });

    AlertManager manager(SmsSender sms) => AlertManager(
          store: store,
          profiles: profiles,
          player: player,
          sms: sms,
          soundDuration: const Duration(milliseconds: 60),
          countdown: const Duration(milliseconds: 120),
          retryDelays: const [Duration(milliseconds: 20), Duration(milliseconds: 20)],
        );

    test('annullata prima della scadenza: suono fermato, nessun SMS', () async {
      final sms = FakeSmsSender();
      final m = manager(sms);
      expect(await m.trigger(detectionId: 1, title: 't', detail: 'd', dryRun: false), isTrue);
      expect(player.playing, isTrue);
      await m.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(player.playing, isFalse);
      expect(sms.sent, isEmpty);
      expect(store.alerts.single.state, AlertState.cancelled);
    });

    test('senza annullare: suono 30 s poi SMS a 60 s, una sola volta', () async {
      final sms = FakeSmsSender();
      final m = manager(sms);
      await m.trigger(detectionId: 7, title: 't', detail: 'd', dryRun: false);
      await waitFor(() => !player.playing);
      expect(m.phase, AlertPhase.countdown);
      expect(sms.sent, isEmpty);
      await waitFor(() => m.phase == AlertPhase.finished);
      expect(sms.sent.single.$1, '+393331234567');
      expect(sms.sent.single.$2, contains('Anna Bianchi'));
      expect(store.alerts.single.state, AlertState.sent);
      // Same detection again: refused (no duplicate).
      m.dismiss();
      expect(await m.trigger(detectionId: 7, title: 't', detail: 'd', dryRun: false), isFalse);
      expect(sms.sent, hasLength(1));
    });

    test('rete assente: nuovi tentativi, poi invio', () async {
      final sms = FakeSmsSender(results: const [SmsResult(SmsOutcome.noService), SmsResult(SmsOutcome.sent)]);
      final m = manager(sms);
      await m.trigger(detectionId: 2, title: 't', detail: 'd', dryRun: false);
      await waitFor(() => m.phase == AlertPhase.finished);
      expect(sms.sent, hasLength(2));
      expect(store.alerts.single.state, AlertState.sent);
    });

    test('esito sconosciuto: una sola ripetizione marcata', () async {
      final sms = FakeSmsSender(results: const [SmsResult(SmsOutcome.unknown), SmsResult(SmsOutcome.sent)]);
      final m = manager(sms);
      await m.trigger(detectionId: 3, title: 't', detail: 'd', dryRun: false);
      await waitFor(() => m.phase == AlertPhase.finished);
      expect(sms.sent, hasLength(2));
      expect(sms.sent.last.$2, endsWith('(ripetizione)'));
    });

    test('prova (dry run): nessun SMS reale', () async {
      final sms = FakeSmsSender();
      final m = manager(sms);
      await m.trigger(detectionId: 4, title: 't', detail: 'd', dryRun: true);
      await waitFor(() => m.phase == AlertPhase.finished);
      expect(sms.sent, isEmpty);
      expect(store.alerts.single.state, AlertState.dryRun);
    });

    test('contatto disattivato: nessun invio, esito registrato', () async {
      await profiles.saveContact(const EmergencyContact(name: 'Luca', number: '+393331234567', enabled: false));
      final sms = FakeSmsSender();
      final m = manager(sms);
      await m.trigger(detectionId: 5, title: 't', detail: 'd', dryRun: false);
      await waitFor(() => m.phase == AlertPhase.finished);
      expect(sms.sent, isEmpty);
      expect(store.alerts.single.smsResult, 'no_contact');
    });
  });
}
