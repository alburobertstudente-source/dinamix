import 'math/vec3.dart';

/// Standard gravity, used only to express accelerations in G.
const double g0 = 9.80665;

/// Where the motion data comes from. The detection engine is the same for all.
enum SourceKind {
  phone('Sensori dello smartphone'),
  sensorTile('SensorTile STMicroelectronics'),
  simulated('Simulazione'),
  replay('Riproduzione');

  const SourceKind(this.label);
  final String label;
}

/// How trustworthy the sample times are.
enum TimestampQuality {
  /// Sensor hardware timestamps (Android SensorEvent.timestamp).
  hardware,

  /// Reconstructed from a device counter and the receive times (BLE, §25.5).
  reconstructed,

  /// Receive time only: includes transport jitter.
  received,
}

enum SampleKind { acc, gyro, gps }

/// One normalized measurement, in SI units and in the device frame of the source.
///
/// acc: specific force in m/s² (reads +g upwards at rest); gyro: rad/s;
/// gps: x = speed m/s, y = speed accuracy m/s (NaN if unknown), z = unused.
class MotionSample {
  const MotionSample(this.kind, this.tNs, this.v, {this.flags = 0});

  final SampleKind kind;

  /// Sample time on a monotonic clock, nanoseconds.
  final int tNs;
  final Vec3 v;
  final int flags;

  static const int flagSaturated = 1;
  static const int flagGapBefore = 2;

  double get tS => tNs / 1e9;
}

/// Static description of a source, with the calibration of its hardware.
/// The same engine runs with different profiles (§25.4).
class SourceProfile {
  const SourceProfile({
    required this.kind,
    required this.name,
    required this.nominalRateHz,
    required this.timestampQuality,
    this.accRange,
    this.gyroRange,
    this.leverArmMax = 0.08,
    this.verified = false,
    this.notes = '',
  });

  final SourceKind kind;
  final String name;
  final double nominalRateHz;
  final TimestampQuality timestampQuality;

  /// Full scale of the accelerometer (m/s²) and gyroscope (rad/s); null if unknown.
  final double? accRange;
  final double? gyroRange;

  /// Upper bound of the distance between accelerometer and centre of mass (m),
  /// used for the free-fall tolerance under rotation (§9.1).
  final double leverArmMax;

  /// False while the hardware characteristics have not been checked on a real unit.
  final bool verified;
  final String notes;

  /// Phone: full scale read at runtime when available; 8 cm is the largest
  /// dimension of a phone from its centre.
  static const SourceProfile phone = SourceProfile(
    kind: SourceKind.phone,
    name: 'Smartphone',
    nominalRateHz: 200,
    timestampQuality: TimestampQuality.hardware,
    leverArmMax: 0.08,
    notes: 'Fondo scala non letto: saturazione stimata dal valore massimo osservato.',
  );

  /// SensorTile.box PRO over BlueST. Characteristics NOT verified on a real board
  /// (report §25.2): the gyro wire format stops at ±3276.7 dps.
  static const SourceProfile sensorTile = SourceProfile(
    kind: SourceKind.sensorTile,
    name: 'SensorTile.box PRO',
    nominalRateHz: 50,
    timestampQuality: TimestampQuality.reconstructed,
    accRange: 32.767 * g0,
    gyroRange: 3276.7 * 3.141592653589793 / 180,
    leverArmMax: 0.05,
    notes: 'NON VERIFICATO su scheda reale: fondo scala, frequenza e unità del timestamp.',
  );

  static const SourceProfile simulated = SourceProfile(
    kind: SourceKind.simulated,
    name: 'Simulatore fisico',
    nominalRateHz: 200,
    timestampQuality: TimestampQuality.hardware,
    accRange: 16 * g0,
    gyroRange: 2000 * 3.141592653589793 / 180,
    verified: true,
  );

  SourceProfile copyWith({double? nominalRateHz, double? accRange, double? gyroRange}) =>
      SourceProfile(
        kind: kind,
        name: name,
        nominalRateHz: nominalRateHz ?? this.nominalRateHz,
        timestampQuality: timestampQuality,
        accRange: accRange ?? this.accRange,
        gyroRange: gyroRange ?? this.gyroRange,
        leverArmMax: leverArmMax,
        verified: verified,
        notes: notes,
      );
}
