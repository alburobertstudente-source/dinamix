import 'dart:typed_data';

import '../../domain/sensor_kind.dart';
import '../protocol/advertising.dart';

enum AdapterStatus { unknown, on, off, turningOn, turningOff, unauthorized, unsupported }

enum LinkState { connected, disconnected }

class BleScanResult {
  const BleScanResult({
    required this.id,
    required this.name,
    required this.rssi,
    required this.connectable,
    this.advertising,
  });

  final String id;
  final String name;
  final int rssi;
  final bool connectable;

  /// Null when the device does not advertise BlueST data.
  final BlueStAdvertising? advertising;
}

class BleCharInfo {
  const BleCharInfo({
    required this.serviceUuid,
    required this.uuid,
    this.canRead = false,
    this.canWrite = false,
    this.canWriteWithoutResponse = false,
    this.canNotify = false,
    this.canIndicate = false,
  });

  final String serviceUuid;
  final String uuid;
  final bool canRead;
  final bool canWrite;
  final bool canWriteWithoutResponse;
  final bool canNotify;
  final bool canIndicate;

  String get propertiesLabel => [
        if (canRead) 'R',
        if (canWrite) 'W',
        if (canWriteWithoutResponse) 'WNR',
        if (canNotify) 'N',
        if (canIndicate) 'I',
      ].join(' ');
}

class BleServiceInfo {
  const BleServiceInfo(this.uuid, this.characteristics);

  final String uuid;
  final List<BleCharInfo> characteristics;
}

/// Boundary towards the radio. The hardware implementation and the simulator are
/// two separate classes: everything above this interface is the same code.
abstract class BleTransport {
  /// Tag applied to everything this transport produces.
  DataSource get dataSource;

  AdapterStatus get adapterStatusNow;
  Stream<AdapterStatus> get adapterStatus;

  Stream<List<BleScanResult>> get scanResults;
  Stream<bool> get isScanning;

  /// Throws [AppError] with code permissionDenied when not granted.
  Future<void> ensurePermissions();
  Future<void> turnOnAdapter();

  Future<void> startScan({Duration timeout});
  Future<void> stopScan();

  Future<void> connect(String deviceId, {required Duration timeout});
  Future<void> disconnect(String deviceId);
  Stream<LinkState> linkState(String deviceId);

  Future<List<BleServiceInfo>> discover(String deviceId);
  Future<int> currentMtu(String deviceId);
  Future<void> setHighThroughput(String deviceId, bool enabled);
  Future<void> createBond(String deviceId);
  Future<int> readRssi(String deviceId);

  Future<Stream<Uint8List>> subscribe(String deviceId, BleCharInfo characteristic);
  Future<void> unsubscribe(String deviceId, BleCharInfo characteristic);
  Future<void> write(String deviceId, BleCharInfo characteristic, List<int> value,
      {required bool withoutResponse});
}
