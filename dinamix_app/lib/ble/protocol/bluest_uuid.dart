import '../../domain/sensor_kind.dart';

enum BlueStCharType { basic, extended, generalPurpose, debug, config, other }

/// Parses `XXXXXXXX-SSSS-11e1-ac36-0002a5d5c51b`.
/// SSSS: 0001 basic, 0002 extended, 0003 general purpose, 000E debug, 000F config
/// (ST BlueST-SDK.md). The ST catalog lists the debug characteristics with the
/// `9ab4` block while the specification shows `ac36`, so both are accepted.
class BlueStUuid {
  const BlueStUuid(this.raw, this.type, this.id);

  final String raw;
  final BlueStCharType type;

  /// Basic: feature bitmask. Extended/general purpose: identifier.
  final int id;

  static final RegExp _pattern = RegExp(
      r'^([0-9a-f]{8})-([0-9a-f]{4})-11e1-(ac36|9ab4)-0002a5d5c51b$');

  static BlueStUuid parse(String uuid) {
    final lower = uuid.toLowerCase();
    final match = _pattern.firstMatch(lower);
    if (match == null) return BlueStUuid(lower, BlueStCharType.other, 0);
    final id = int.parse(match.group(1)!, radix: 16);
    final type = switch (match.group(2)) {
      '0001' => BlueStCharType.basic,
      '0002' => BlueStCharType.extended,
      '0003' => BlueStCharType.generalPurpose,
      '000e' => BlueStCharType.debug,
      '000f' => BlueStCharType.config,
      _ => BlueStCharType.other,
    };
    return BlueStUuid(lower, type, id);
  }

  bool get isDebugConsole => type == BlueStCharType.debug && id == 1;
  bool get isDebugStderr => type == BlueStCharType.debug && id == 2;

  /// Basic features exported by this characteristic, most significant bit first.
  /// That is the order of their data inside the packet.
  List<int> get basicMasks {
    if (type != BlueStCharType.basic) return const [];
    final masks = <int>[];
    for (var bit = 31; bit >= 0; bit--) {
      final mask = 1 << bit;
      if (id & mask != 0) masks.add(mask);
    }
    return masks;
  }

  /// Data kinds this app can decode from the characteristic.
  /// Empty when even one of the features has an unknown length.
  List<SensorKind> get decodableKinds {
    switch (type) {
      case BlueStCharType.basic:
        final kinds = <SensorKind>[];
        for (final mask in basicMasks) {
          final kind = basicFeatureKinds[mask];
          if (kind == null) return const [];
          kinds.add(kind);
        }
        return kinds;
      case BlueStCharType.extended:
        final kind = extendedFeatureKinds[id];
        return kind == null ? const [] : [kind];
      default:
        return const [];
    }
  }

  /// Human readable name for the diagnostics screen.
  String get displayName {
    switch (type) {
      case BlueStCharType.basic:
        return basicMasks
            .map((m) =>
                basicFeatureNames[m] ?? '0x${m.toRadixString(16).padLeft(8, '0')}')
            .join(' + ');
      case BlueStCharType.extended:
        return extendedFeatureNames[id] ??
            'Extended 0x${id.toRadixString(16).padLeft(2, '0')}';
      case BlueStCharType.generalPurpose:
        return 'General Purpose ${id.toRadixString(16)}';
      case BlueStCharType.debug:
        return id == 1 ? 'Debug console (stdin/stdout)' : 'Debug console (stderr)';
      case BlueStCharType.config:
        return 'Configurazione';
      case BlueStCharType.other:
        return 'Non BlueST';
    }
  }
}

/// Basic features decoded by the app. Mask table: Feature.kt, default branch of
/// BlueSTSDK_Android, which is the one used by SensorTile.box PRO.
const Map<int, SensorKind> basicFeatureKinds = {
  0x20000000: SensorKind.switchState,
  0x04000000: SensorKind.micLevel,
  0x00800000: SensorKind.accelerometer,
  0x00400000: SensorKind.gyroscope,
  0x00200000: SensorKind.magnetometer,
  0x00100000: SensorKind.pressure,
  0x00080000: SensorKind.humidity,
  0x00040000: SensorKind.temperature2,
  0x00020000: SensorKind.battery,
  0x00010000: SensorKind.temperature,
  0x00000100: SensorKind.quaternion,
  0x00000080: SensorKind.quaternion,
  0x00000040: SensorKind.compass,
  0x00000010: SensorKind.activity,
  0x00000001: SensorKind.pedometer,
};

const Map<int, SensorKind> extendedFeatureKinds = {
  0x0D: SensorKind.euler,
  0x16: SensorKind.qvar,
  0x1D: SensorKind.eventCounter,
};

/// Includes features that are recognized but not decoded.
const Map<int, String> basicFeatureNames = {
  0x40000000: 'Audio ADPCM Sync',
  0x20000000: 'Switch',
  0x10000000: 'Direction of Arrival',
  0x08000000: 'Audio ADPCM',
  0x04000000: 'Mic Level',
  0x02000000: 'Proximity',
  0x01000000: 'Luminosity',
  0x00800000: 'Accelerometer',
  0x00400000: 'Gyroscope',
  0x00200000: 'Magnetometer',
  0x00100000: 'Pressure',
  0x00080000: 'Humidity',
  0x00040000: 'Temperature',
  0x00020000: 'Battery',
  0x00010000: 'Temperature',
  0x00008000: 'CO Sensor',
  0x00002000: 'Stepper Motor',
  0x00001000: 'SD Logging',
  0x00000800: 'Beamforming',
  0x00000400: 'Acceleration Event',
  0x00000200: 'Free Fall',
  0x00000100: 'MEMS Sensor Fusion Compact',
  0x00000080: 'MEMS Sensor Fusion',
  0x00000040: 'Compass',
  0x00000020: 'Motion Intensity',
  0x00000010: 'Activity',
  0x00000008: 'Carry Position',
  0x00000004: 'Proximity Gesture',
  0x00000002: 'MEMS Gesture',
  0x00000001: 'Pedometer',
};

const Map<int, String> extendedFeatureNames = {
  0x01: 'Audio Opus',
  0x02: 'Audio Opus Conf',
  0x03: 'Audio Classification',
  0x04: 'AI Logging',
  0x05: 'FFT Amplitude',
  0x0A: 'Motion Algorithm',
  0x0D: 'Euler Angle',
  0x0E: 'Fitness Activity',
  0x0F: 'Machine Learning Core',
  0x10: 'Finite State Machine',
  0x11: 'HS Datalog Config',
  0x14: 'Ext Configuration',
  0x16: 'QVAR',
  0x19: 'NEAI Anomaly Detection',
  0x1A: 'NEAI Classification',
  0x1B: 'PnPLike',
  0x1C: 'Piano',
  0x1D: 'Event Counter',
  0x1F: 'Gesture Navigation',
  0x20: 'JSON NFC',
  0x21: 'MEMS Normalization',
  0x22: 'Binary Content',
  0x30: 'Asset Tracking Event',
};
