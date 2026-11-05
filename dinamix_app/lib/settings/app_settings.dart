import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/sensor_kind.dart';
import '../domain/units.dart';

class KnownDevice {
  const KnownDevice(this.id, this.name, this.lastConnectedMs, this.firmware);

  final String id;
  final String name;
  final int lastConnectedMs;
  final String firmware;

  Map<String, Object?> toJson() =>
      {'id': id, 'name': name, 'last': lastConnectedMs, 'fw': firmware};

  static KnownDevice fromJson(Map<String, dynamic> m) => KnownDevice(
      m['id'] as String, m['name'] as String, m['last'] as int, (m['fw'] as String?) ?? '');
}

/// Detection mode chosen by the user (report §25.7).
enum DetectionMode {
  phone('Sensori dello smartphone'),
  sensorTile('SensorTile STMicroelectronics');

  const DetectionMode(this.label);
  final String label;
}

/// Amount of decorative animation (report §20.4).
enum AnimationLevel {
  full('Complete'),
  light('Leggere'),
  off('Statiche');

  const AnimationLevel(this.label);
  final String label;
}

class AppSettings extends ChangeNotifier {
  AppSettings(this._prefs) {
    _load();
  }

  final SharedPreferences _prefs;

  ThemeMode themeMode = ThemeMode.dark;
  int chartRefreshHz = 15;
  int chartWindowSeconds = 10;
  bool autoReconnect = true;
  bool highThroughput = true;
  bool simulationMode = false;
  bool phoneDemo = false;
  double impactThresholdG = 4;
  UnitPrefs units = const UnitPrefs();
  Set<SensorKind> disabledKinds = {};
  List<KnownDevice> knownDevices = [];

  /// Null until the user has chosen a mode after the registration.
  DetectionMode? detectionMode;
  int samplingHz = 200;
  bool smsDryRun = false;
  bool developerMode = false;
  AnimationLevel animationLevel = AnimationLevel.full;

  static T _byName<T extends Enum>(List<T> values, String? name, T fallback) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return fallback;
  }

  void _load() {
    themeMode = _byName(ThemeMode.values, _prefs.getString('theme'), ThemeMode.dark);
    chartRefreshHz = _prefs.getInt('refresh_hz') ?? 15;
    chartWindowSeconds = _prefs.getInt('window_s') ?? 10;
    autoReconnect = _prefs.getBool('auto_reconnect') ?? true;
    highThroughput = _prefs.getBool('high_throughput') ?? true;
    simulationMode = _prefs.getBool('simulation') ?? false;
    impactThresholdG = _prefs.getDouble('impact_g') ?? 4;
    final mode = _prefs.getString('detection_mode');
    detectionMode = mode == null ? null : _byName(DetectionMode.values, mode, DetectionMode.phone);
    samplingHz = _prefs.getInt('sampling_hz') ?? 200;
    smsDryRun = _prefs.getBool('sms_dry_run') ?? false;
    developerMode = _prefs.getBool('developer') ?? false;
    animationLevel = _byName(AnimationLevel.values, _prefs.getString('animations'), AnimationLevel.full);
    units = UnitPrefs(
      acc: _byName(AccUnit.values, _prefs.getString('unit_acc'), AccUnit.mg),
      gyro: _byName(GyroUnit.values, _prefs.getString('unit_gyro'), GyroUnit.dps),
      mag: _byName(MagUnit.values, _prefs.getString('unit_mag'), MagUnit.mGa),
      temp: _byName(TempUnit.values, _prefs.getString('unit_temp'), TempUnit.celsius),
      pressure: _byName(PressureUnit.values, _prefs.getString('unit_press'), PressureUnit.hPa),
    );
    disabledKinds = (_prefs.getStringList('disabled_kinds') ?? const [])
        .map(SensorKind.fromId)
        .whereType<SensorKind>()
        .toSet();
    final raw = _prefs.getString('known_devices');
    if (raw != null) {
      try {
        knownDevices = (jsonDecode(raw) as List)
            .map((e) => KnownDevice.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        knownDevices = [];
      }
    }
  }

  void setThemeMode(ThemeMode mode) {
    themeMode = mode;
    _prefs.setString('theme', mode.name);
    notifyListeners();
  }

  void setChartRefreshHz(int hz) {
    chartRefreshHz = hz;
    _prefs.setInt('refresh_hz', hz);
    notifyListeners();
  }

  void setChartWindowSeconds(int seconds) {
    chartWindowSeconds = seconds;
    _prefs.setInt('window_s', seconds);
    notifyListeners();
  }

  void setAutoReconnect(bool value) {
    autoReconnect = value;
    _prefs.setBool('auto_reconnect', value);
    notifyListeners();
  }

  void setHighThroughput(bool value) {
    highThroughput = value;
    _prefs.setBool('high_throughput', value);
    notifyListeners();
  }

  void setSimulationMode(bool value) {
    simulationMode = value;
    _prefs.setBool('simulation', value);
    notifyListeners();
  }

  /// Not persisted: at every launch the app starts ready for the SensorTile.
  void setPhoneDemo(bool value) {
    phoneDemo = value;
    notifyListeners();
  }

  void setImpactThresholdG(double value) {
    impactThresholdG = value;
    _prefs.setDouble('impact_g', value);
    notifyListeners();
  }

  void setUnits(UnitPrefs value) {
    units = value;
    _prefs.setString('unit_acc', value.acc.name);
    _prefs.setString('unit_gyro', value.gyro.name);
    _prefs.setString('unit_mag', value.mag.name);
    _prefs.setString('unit_temp', value.temp.name);
    _prefs.setString('unit_press', value.pressure.name);
    notifyListeners();
  }

  void setKindEnabled(SensorKind kind, bool enabled) {
    if (enabled) {
      disabledKinds.remove(kind);
    } else {
      disabledKinds.add(kind);
    }
    _prefs.setStringList('disabled_kinds', disabledKinds.map((k) => k.id).toList());
    notifyListeners();
  }

  void setDetectionMode(DetectionMode mode) {
    detectionMode = mode;
    _prefs.setString('detection_mode', mode.name);
    notifyListeners();
  }

  void setSamplingHz(int hz) {
    samplingHz = hz;
    _prefs.setInt('sampling_hz', hz);
    notifyListeners();
  }

  void setSmsDryRun(bool value) {
    smsDryRun = value;
    _prefs.setBool('sms_dry_run', value);
    notifyListeners();
  }

  void setDeveloperMode(bool value) {
    developerMode = value;
    _prefs.setBool('developer', value);
    if (!value && simulationMode) setSimulationMode(false);
    notifyListeners();
  }

  void setAnimationLevel(AnimationLevel value) {
    animationLevel = value;
    _prefs.setString('animations', value.name);
    notifyListeners();
  }

  /// Removes the app choices (profile deletion, report §13.1).
  Future<void> resetOnboarding() async {
    detectionMode = null;
    await _prefs.remove('detection_mode');
    notifyListeners();
  }

  void rememberDevice(KnownDevice device) {
    knownDevices = [
      device,
      ...knownDevices.where((d) => d.id != device.id),
    ].take(10).toList();
    _saveKnown();
    notifyListeners();
  }

  void forgetDevice(String id) {
    knownDevices = knownDevices.where((d) => d.id != id).toList();
    _saveKnown();
    notifyListeners();
  }

  void _saveKnown() {
    _prefs.setString('known_devices', jsonEncode(knownDevices.map((d) => d.toJson()).toList()));
  }
}
