/// Where a value comes from. The tag is set at the source and carried up to the
/// database and the exported files: SensorTile, phone sensors or simulator.
enum DataSource { hardware, phone, simulated }

class ChannelDef {
  const ChannelDef(this.key, this.label, this.unit);

  final String key;
  final String label;

  /// Canonical unit: the one stored in the database and in exported files.
  final String unit;
}

/// Data types the app is able to decode. Canonical units follow the ST SDK.
enum SensorKind {
  accelerometer('acc', 'Accelerometro', [
    ChannelDef('x', 'X', 'mg'),
    ChannelDef('y', 'Y', 'mg'),
    ChannelDef('z', 'Z', 'mg'),
  ]),
  gyroscope('gyro', 'Giroscopio', [
    ChannelDef('x', 'X', 'dps'),
    ChannelDef('y', 'Y', 'dps'),
    ChannelDef('z', 'Z', 'dps'),
  ]),
  magnetometer('mag', 'Magnetometro', [
    ChannelDef('x', 'X', 'mGa'),
    ChannelDef('y', 'Y', 'mGa'),
    ChannelDef('z', 'Z', 'mGa'),
  ]),
  temperature('temp', 'Temperatura', [ChannelDef('value', 'Temperatura', '°C')]),
  temperature2('temp2', 'Temperatura 2', [ChannelDef('value', 'Temperatura', '°C')]),
  pressure('press', 'Pressione', [ChannelDef('value', 'Pressione', 'hPa')]),
  humidity('hum', 'Umidità', [ChannelDef('value', 'Umidità', '%')]),
  battery('batt', 'Batteria', [
    ChannelDef('level', 'Carica', '%'),
    ChannelDef('voltage', 'Tensione', 'V'),
    ChannelDef('current', 'Corrente', 'mA'),
    ChannelDef('status', 'Stato', ''),
  ]),
  quaternion('quat', 'Quaternioni', [
    ChannelDef('qi', 'qi', ''),
    ChannelDef('qj', 'qj', ''),
    ChannelDef('qk', 'qk', ''),
    ChannelDef('qs', 'qs', ''),
  ]),
  euler('euler', 'Angoli di Eulero', [
    ChannelDef('yaw', 'Yaw', '°'),
    ChannelDef('pitch', 'Pitch', '°'),
    ChannelDef('roll', 'Roll', '°'),
  ]),
  compass('compass', 'Bussola', [ChannelDef('angle', 'Direzione', '°')]),
  pedometer('steps', 'Contapassi', [
    ChannelDef('steps', 'Passi', 'passi'),
    ChannelDef('frequency', 'Cadenza', 'passi/min'),
  ]),
  activity('activity', 'Attività', [ChannelDef('code', 'Codice', '')]),
  micLevel('mic', 'Livello microfono', [ChannelDef('level', 'Livello', 'dB')]),
  switchState('switch', 'Interruttore', [ChannelDef('state', 'Stato', '')]),
  eventCounter('events', 'Contatore eventi', [ChannelDef('count', 'Eventi', '')]),
  qvar('qvar', 'QVAR (touch)', [
    ChannelDef('qvar', 'QVAR', 'LSB'),
    ChannelDef('flag', 'Flag', ''),
    ChannelDef('dqvar', 'DQVAR', 'LSB'),
    ChannelDef('param', 'Parametro', ''),
  ]);

  const SensorKind(this.id, this.label, this.channels);

  final String id;
  final String label;
  final List<ChannelDef> channels;

  bool get isTriaxial =>
      this == accelerometer || this == gyroscope || this == magnetometer;

  /// Values that are categories: a time chart would be misleading.
  bool get isCategorical => this == activity || this == switchState;

  static SensorKind? fromId(String id) {
    for (final kind in SensorKind.values) {
      if (kind.id == id) return kind;
    }
    return null;
  }
}

class SensorReading {
  const SensorReading({
    required this.kind,
    required this.deviceTicks,
    required this.receivedAtMs,
    required this.values,
    required this.source,
  });

  final SensorKind kind;

  /// 16-bit timestamp of the BlueST packet. Unit depends on the firmware.
  final int deviceTicks;

  /// Phone clock when the packet was received (ms since epoch).
  final int receivedAtMs;

  /// One value per channel; NaN when the packet does not carry that channel.
  final List<double> values;
  final DataSource source;
}

/// Mapping from ST BlueSTSDK_Android (ActivityInfo.getActivityType).
String activityLabel(int code) => switch (code) {
      0 => 'Nessuna attività',
      1 => 'Fermo',
      2 => 'Camminata',
      3 => 'Camminata veloce',
      4 => 'Corsa',
      5 => 'Bicicletta',
      6 => 'Guida',
      7 => 'Scale',
      8 => 'Adulto in auto',
      _ => 'Errore',
    };

/// Mapping from ST BlueSTSDK_Android (BatteryInfo.getBatteryStatus).
String batteryStatusLabel(int code) => switch (code) {
      0 => 'Batteria scarica',
      1 => 'In scarica',
      2 => 'Collegata, non in carica',
      3 => 'In carica',
      4 => 'Sconosciuto',
      _ => 'Errore',
    };
