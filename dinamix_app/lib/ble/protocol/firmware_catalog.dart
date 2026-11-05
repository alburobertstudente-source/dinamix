/// Generated from the official ST catalog:
/// github.com/STMicroelectronics/appconfig, bluestsdkv2/catalog.json,
/// entries with ble_dev_id 0x0D. Used only to show a readable name:
/// the available features are always read from the device GATT table.
const int deviceIdSensorTileBoxPro = 0x0D;

class FirmwareInfo {
  const FirmwareInfo(this.name, this.version);

  final String name;
  final String version;

  String get label => '$name $version';
}

const String _dual = 'FP-SNS-STBOX1 BLEDualProgram';
const String _sensors = 'FP-SNS-STBOX1 BLESensors';
const String _mlc = 'FP-SNS-STBOX1 BLEMLC';
const String _piano = 'FP-SNS-STBOX1 BLEPiano';
const String _pnpl = 'FP-SNS-STBOX1 BLESensorsPnPL';
const String _datalog = 'FP-SNS-DATALOG2 Datalog2';
const String _atr = 'FP-ATR-BLE1';
const String _entry = 'STSW-MKBOXPRO Entry/Expert Mode';
const String _craft = 'STAIOTCRAFT AI_SSM';

const Map<int, FirmwareInfo> sensorTileBoxProFirmwares = {
  0x01: FirmwareInfo(_dual, '1.5.0'),
  0x02: FirmwareInfo(_sensors, '1.5.0'),
  0x03: FirmwareInfo(_mlc, '1.5.0'),
  0x04: FirmwareInfo(_piano, '1.5.0'),
  0x05: FirmwareInfo(_pnpl, '1.5.0'),
  0x06: FirmwareInfo(_datalog, '1.1.0'),
  0x07: FirmwareInfo(_atr, '2.0.0'),
  0x08: FirmwareInfo(_entry, '1.0.0'),
  0x09: FirmwareInfo(_datalog, '1.2.0'),
  0x0A: FirmwareInfo(_datalog, '1.2.1'),
  0x0B: FirmwareInfo(_datalog, '2.0.0'),
  0x0C: FirmwareInfo(_atr, '2.1.0'),
  0x0D: FirmwareInfo(_dual, '1.6.0'),
  0x0E: FirmwareInfo(_sensors, '1.6.0'),
  0x0F: FirmwareInfo(_mlc, '1.6.0'),
  0x10: FirmwareInfo(_piano, '1.6.0'),
  0x11: FirmwareInfo(_pnpl, '1.6.0'),
  0x12: FirmwareInfo(_entry, '1.0.7'),
  0x13: FirmwareInfo(_datalog, '2.0.1'),
  0x14: FirmwareInfo(_datalog, '2.1.0'),
  0x15: FirmwareInfo(_entry, '1.1.0'),
  0x16: FirmwareInfo(_datalog, '2.1.1'),
  0x17: FirmwareInfo(_entry, '1.1.1'),
  0x18: FirmwareInfo(_datalog, '2.2.0'),
  0x19: FirmwareInfo(_datalog, '2.3.0'),
  0x1A: FirmwareInfo(_datalog, '3.0.0'),
  0x1B: FirmwareInfo(_entry, '1.2.0'),
  0x1C: FirmwareInfo(_entry, '1.2.1'),
  0x1D: FirmwareInfo(_datalog, '3.1.0'),
  0x1E: FirmwareInfo(_dual, '2.1.0'),
  0x1F: FirmwareInfo(_mlc, '2.1.0'),
  0x20: FirmwareInfo(_piano, '2.1.0'),
  0x21: FirmwareInfo(_pnpl, '2.1.0'),
  0x22: FirmwareInfo(_entry, '1.3.0'),
  0x23: FirmwareInfo('STBP-ASSET-TRACKING', '1.0.0'),
  0x24: FirmwareInfo(_entry, '1.3.1'),
  0x25: FirmwareInfo('AI-SSM', '1.0.0'),
  0x26: FirmwareInfo(_datalog, '3.2.0'),
  0x27: FirmwareInfo('FP-SNS-STAIOTCFT AI_SSM', '1.0.0'),
  0x28: FirmwareInfo(_datalog, '3.3.0'),
  0x29: FirmwareInfo(_craft, '1.0.0'),
  0x2A: FirmwareInfo(_entry, '1.4.1'),
  0x2B: FirmwareInfo(_datalog, '3.4.0'),
  0x2C: FirmwareInfo(_craft, '1.1.0'),
  0x2F: FirmwareInfo(_dual, '2.0.0'),
  0x30: FirmwareInfo(_mlc, '2.0.0'),
  0x31: FirmwareInfo(_piano, '2.0.0'),
  0x32: FirmwareInfo(_pnpl, '2.0.0'),
};

FirmwareInfo? lookupFirmware(int deviceId, int firmwareId) =>
    deviceId == deviceIdSensorTileBoxPro
        ? sensorTileBoxProFirmwares[firmwareId]
        : null;

/// Device ID table from ST BlueST-SDK.md.
String boardNameFor(int deviceId) => switch (deviceId) {
      0x00 => 'Dispositivo generico',
      0x01 => 'STEVAL-WESU1',
      0x02 => 'SensorTile (STEVAL-STLKT01V1)',
      0x03 => 'BlueCoin (STEVAL-BCNKT01V1)',
      0x04 => 'BlueNRG-2 (STEVAL-IDB008V1/2)',
      0x05 => 'BlueNRG-Tile (STEVAL-BCN002V1B)',
      0x06 => 'SensorTile.box (STEVAL-MKSBOX1V1)',
      0x07 => 'IoT Node (B-L475E-IOT01A)',
      0x08 => 'STWIN (STEVAL-STWINKT1)',
      0x09 => 'STWIN (STEVAL-STWINKT1B)',
      0x0A => 'B-L4S5I-IOT01A',
      0x0B => 'B-U585I-IOT02A',
      0x0C => 'ASTRA',
      0x0D => 'SensorTile.box PRO',
      0x0E => 'STWIN.box',
      0x0F => 'STEVAL-PROTEUS',
      0x10 => 'STSYS-SBU06',
      >= 0xF0 => 'Scheda personalizzata',
      _ => 'Scheda ST (0x${deviceId.toRadixString(16).padLeft(2, '0')})',
    };
