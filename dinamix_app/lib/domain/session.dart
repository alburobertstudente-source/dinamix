import 'dart:convert';

import 'sensor_kind.dart';

enum SessionStatus { recording, completed, interrupted }

class SessionInfo {
  const SessionInfo({
    required this.id,
    required this.name,
    required this.startedAtMs,
    required this.deviceName,
    required this.deviceId,
    required this.firmware,
    required this.source,
    required this.status,
    this.endedAtMs,
    this.sampleCount = 0,
    this.configJson = '{}',
  });

  final int id;
  final String name;
  final int startedAtMs;
  final int? endedAtMs;
  final String deviceName;
  final String deviceId;
  final String firmware;
  final DataSource source;
  final SessionStatus status;
  final int sampleCount;

  /// Acquisition configuration: kinds, units, phone-measured frequency, MTU.
  final String configJson;

  Map<String, dynamic> get config {
    try {
      return jsonDecode(configJson) as Map<String, dynamic>;
    } catch (_) {
      return const {};
    }
  }

  Duration get duration =>
      Duration(milliseconds: (endedAtMs ?? startedAtMs) - startedAtMs);

  bool get isSimulated => source == DataSource.simulated;

  /// Label for data that does not come from the SensorTile, null otherwise.
  String? get sourceTag => switch (source) {
        DataSource.hardware => null,
        DataSource.phone => 'TELEFONO',
        DataSource.simulated => 'SIMULATO',
      };
}

class SessionEvent {
  const SessionEvent(this.atMs, this.type, {this.detail = ''});

  final int atMs;

  /// start, pause, resume, stop, link_lost, link_restored, write_error.
  final String type;
  final String detail;
}

class StoredSample {
  const StoredSample({
    required this.rowId,
    required this.kind,
    required this.receivedAtMs,
    required this.deviceTicks,
    required this.values,
  });

  final int rowId;
  final SensorKind kind;
  final int receivedAtMs;
  final int deviceTicks;
  final List<double> values;
}
