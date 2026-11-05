import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Local user profile: only what the alert message needs (report §13.1).
class UserProfile {
  const UserProfile({required this.firstName, required this.lastName, required this.age});

  final String firstName;
  final String lastName;
  final int age;

  String get fullName => '$firstName $lastName';

  Map<String, Object> toJson() => {'first': firstName, 'last': lastName, 'age': age};

  static UserProfile? fromJson(Map<String, dynamic> m) {
    final first = m['first'], last = m['last'], age = m['age'];
    if (first is! String || last is! String || age is! int) return null;
    return UserProfile(firstName: first, lastName: last, age: age);
  }
}

class EmergencyContact {
  const EmergencyContact({
    required this.name,
    required this.number,
    required this.enabled,
    this.lastTestAtMs,
    this.lastTestOk,
  });

  final String name;

  /// E.164 format, e.g. +393331234567.
  final String number;
  final bool enabled;
  final int? lastTestAtMs;
  final bool? lastTestOk;

  EmergencyContact copyWith({bool? enabled, int? lastTestAtMs, bool? lastTestOk}) => EmergencyContact(
        name: name,
        number: number,
        enabled: enabled ?? this.enabled,
        lastTestAtMs: lastTestAtMs ?? this.lastTestAtMs,
        lastTestOk: lastTestOk ?? this.lastTestOk,
      );

  Map<String, Object?> toJson() => {
        'name': name,
        'number': number,
        'enabled': enabled,
        'test_at': lastTestAtMs,
        'test_ok': lastTestOk,
      };

  static EmergencyContact? fromJson(Map<String, dynamic> m) {
    final name = m['name'], number = m['number'];
    if (name is! String || number is! String) return null;
    return EmergencyContact(
      name: name,
      number: number,
      enabled: m['enabled'] == true,
      lastTestAtMs: m['test_at'] as int?,
      lastTestOk: m['test_ok'] as bool?,
    );
  }
}

// ---------------------------------------------------------------------------
// Validation (pure functions, unit-tested).

final RegExp _nameChars = RegExp(r"^[\p{L}\p{M}' \-]+$", unicode: true);

/// Null when valid, otherwise the message to show.
String? validateName(String? raw, String field) {
  final v = (raw ?? '').trim();
  if (v.isEmpty) return 'Inserisci il $field';
  if (v.length > 50) return 'Massimo 50 caratteri';
  if (!_nameChars.hasMatch(v)) return 'Usa solo lettere, spazi, apostrofi e trattini';
  if (!RegExp(r'\p{L}', unicode: true).hasMatch(v)) return 'Il $field deve contenere lettere';
  return null;
}

/// Age as a whole number between 1 and 120.
String? validateAge(String? raw) {
  final v = (raw ?? '').trim();
  if (v.isEmpty) return "Inserisci l'età";
  final n = int.tryParse(v);
  if (n == null) return "L'età deve essere un numero intero";
  if (n < 1 || n > 120) return "Inserisci un'età tra 1 e 120 anni";
  return null;
}

/// Emergency services: automatic SMS to them is not appropriate (report §12.5).
const Set<String> blockedNumbers = {'112', '113', '115', '117', '118', '1515', '1530', '116117', '911'};

/// Normalizes to E.164 with +39 as default country. Returns null if not valid.
String? normalizePhoneNumber(String raw) {
  var v = raw.replaceAll(RegExp(r'[\s\-.()/]'), '');
  if (v.startsWith('00')) v = '+${v.substring(2)}';
  if (!v.startsWith('+')) {
    if (!RegExp(r'^\d+$').hasMatch(v)) return null;
    // Italian mobiles start with 3, landlines with 0 (kept after +39).
    if (v.startsWith('3') || v.startsWith('0')) {
      v = '+39$v';
    } else {
      return null;
    }
  }
  if (!RegExp(r'^\+\d{8,15}$').hasMatch(v)) return null;
  return v;
}

String? validatePhoneNumber(String? raw) {
  final v = (raw ?? '').trim();
  if (v.isEmpty) return 'Inserisci il numero';
  final digits = v.replaceAll(RegExp(r'\D'), '');
  if (blockedNumbers.contains(digits) || digits.length <= 6 && !v.startsWith('+')) {
    return 'I numeri di emergenza e i numeri brevi non sono ammessi: inserisci il cellulare di una persona';
  }
  if (normalizePhoneNumber(v) == null) {
    return 'Numero non valido. Esempio: +39 333 123 4567';
  }
  return null;
}

// ---------------------------------------------------------------------------

abstract class SecureKeyValue {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Android Keystore-backed storage (report §13.2).
class KeystoreKeyValue implements SecureKeyValue {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class MemoryKeyValue implements SecureKeyValue {
  final Map<String, String> values = {};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// Profile and emergency contact, kept in encrypted storage, never sent anywhere
/// except the alert SMS to the contact chosen by the user.
class ProfileService extends ChangeNotifier {
  ProfileService(this._kv);

  final SecureKeyValue _kv;
  static const String _profileKey = 'dynamix.profile';
  static const String _contactKey = 'dynamix.contact';

  UserProfile? profile;
  EmergencyContact? contact;
  bool loaded = false;

  bool get registered => profile != null;
  bool get contactReady => contact != null && contact!.enabled;

  Future<void> load() async {
    try {
      final p = await _kv.read(_profileKey);
      final c = await _kv.read(_contactKey);
      profile = p == null ? null : UserProfile.fromJson(jsonDecode(p) as Map<String, dynamic>);
      contact = c == null ? null : EmergencyContact.fromJson(jsonDecode(c) as Map<String, dynamic>);
    } catch (_) {
      // Unreadable storage (e.g. restored on another device): start again.
      profile = null;
      contact = null;
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> saveProfile(UserProfile p) async {
    await _kv.write(_profileKey, jsonEncode(p.toJson()));
    profile = p;
    notifyListeners();
  }

  Future<void> saveContact(EmergencyContact c) async {
    await _kv.write(_contactKey, jsonEncode(c.toJson()));
    contact = c;
    notifyListeners();
  }

  Future<void> deleteContact() async {
    await _kv.delete(_contactKey);
    contact = null;
    notifyListeners();
  }

  /// Deletes profile and contact (report §13.1).
  Future<void> deleteAll() async {
    await _kv.delete(_profileKey);
    await _kv.delete(_contactKey);
    profile = null;
    contact = null;
    notifyListeners();
  }
}

/// Exact text of the specification (§12).
String alertMessage(UserProfile? p) {
  final name = p == null ? "L'utente" : p.fullName;
  return "DYNAMIX: ALLERTA! $name ha ricevuto una botta forte e non ha disattivato l'allarme.";
}

String testMessage(UserProfile? p) =>
    'DYNAMIX: messaggio di PROVA inviato da ${p?.fullName ?? "un utente"}. '
    'Nessuna emergenza: è solo una verifica del contatto di emergenza.';
