import 'firmware_catalog.dart';

/// BlueST manufacturer data.
///
/// v2 (ST BlueST-SDK.md): 0x30 0x00, SDK version 0x02, device ID, firmware ID,
/// 3 option bytes, optional 6 byte MAC.
/// v1 (ST UM2496): version 0x01, device ID, 4 byte big-endian feature mask,
/// optional 6 byte MAC, with no company identifier.
class BlueStAdvertising {
  const BlueStAdvertising({
    required this.protocolVersion,
    required this.deviceId,
    required this.isSleeping,
    this.firmwareId,
    this.featureMask,
    this.optionBytes = const [],
    this.macAddress,
  });

  final int protocolVersion;
  final int deviceId;
  final bool isSleeping;
  final int? firmwareId;
  final int? featureMask;
  final List<int> optionBytes;
  final String? macAddress;

  bool get isSensorTileBoxPro => deviceId == deviceIdSensorTileBoxPro;

  String get boardName => boardNameFor(deviceId);

  /// Name and version from the ST catalog, null when the ID is not known.
  FirmwareInfo? get firmware =>
      firmwareId == null ? null : lookupFirmware(deviceId, firmwareId!);

  String get firmwareLabel {
    final id = firmwareId;
    if (id == null) return 'Non indicato (BlueST v1)';
    if (id == 0xFF) return 'Firmware sperimentale (0xFF)';
    final info = firmware;
    if (info != null) return info.label;
    return 'Non in catalogo (0x${id.toRadixString(16).padLeft(2, '0')})';
  }

  /// [msdEntries]: manufacturer data as lists starting with the two bytes of the
  /// company identifier, low byte first (flutter_blue_plus `msd` getter).
  static BlueStAdvertising? parse(Iterable<List<int>> msdEntries) {
    for (final entry in msdEntries) {
      final parsed = _parseV2(entry) ?? _parseV1(entry);
      if (parsed != null) return parsed;
    }
    return null;
  }

  static BlueStAdvertising? _parseV2(List<int> d) {
    if ((d.length != 8 && d.length != 14) || d[0] != 0x30 || d[1] != 0x00) {
      return null;
    }
    if (d[2] != 0x02) return null;
    return BlueStAdvertising(
      protocolVersion: 2,
      deviceId: d[3],
      firmwareId: d[4],
      optionBytes: d.sublist(5, 8),
      macAddress: d.length == 14 ? _mac(d.sublist(8, 14)) : null,
      isSleeping: false,
    );
  }

  static BlueStAdvertising? _parseV1(List<int> d) {
    if ((d.length != 6 && d.length != 12) || d[0] != 0x01) return null;
    final nodeType = d[1];
    final isNucleo = nodeType & 0x80 == 0x80;
    return BlueStAdvertising(
      protocolVersion: 1,
      deviceId: isNucleo ? nodeType : nodeType & 0x1F,
      isSleeping: !isNucleo && nodeType & 0x40 == 0x40,
      featureMask: (d[2] << 24) | (d[3] << 16) | (d[4] << 8) | d[5],
      macAddress: d.length == 12 ? _mac(d.sublist(6, 12)) : null,
    );
  }

  static String _mac(List<int> bytes) => bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(':');
}
