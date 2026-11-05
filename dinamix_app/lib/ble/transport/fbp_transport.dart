import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:permission_handler/permission_handler.dart';

import '../../core/app_error.dart';
import '../../core/keep_alive.dart';
import '../../domain/sensor_kind.dart';
import '../protocol/advertising.dart';
import 'ble_transport.dart';

/// Real Bluetooth radio, through flutter_blue_plus.
class FbpTransport implements BleTransport {
  /// flutter_blue_plus requires the license type to be declared. This project is
  /// educational: a for-profit release requires `License.commercial`.
  static const fbp.License _license = fbp.License.nonprofit;

  final Map<String, Map<String, fbp.BluetoothCharacteristic>> _characteristics = {};

  @override
  DataSource get dataSource => DataSource.hardware;

  @override
  AdapterStatus get adapterStatusNow => _mapAdapter(fbp.FlutterBluePlus.adapterStateNow);

  @override
  Stream<AdapterStatus> get adapterStatus =>
      fbp.FlutterBluePlus.adapterState.map(_mapAdapter);

  static AdapterStatus _mapAdapter(fbp.BluetoothAdapterState state) => switch (state) {
        fbp.BluetoothAdapterState.on => AdapterStatus.on,
        fbp.BluetoothAdapterState.off => AdapterStatus.off,
        fbp.BluetoothAdapterState.turningOn => AdapterStatus.turningOn,
        fbp.BluetoothAdapterState.turningOff => AdapterStatus.turningOff,
        fbp.BluetoothAdapterState.unauthorized => AdapterStatus.unauthorized,
        fbp.BluetoothAdapterState.unavailable => AdapterStatus.unsupported,
        _ => AdapterStatus.unknown,
      };

  @override
  Stream<List<BleScanResult>> get scanResults =>
      fbp.FlutterBluePlus.scanResults.map((list) => list.map(_mapResult).toList());

  static BleScanResult _mapResult(fbp.ScanResult r) {
    final adv = r.advertisementData;
    final name = adv.advName.isNotEmpty ? adv.advName : r.device.platformName;
    return BleScanResult(
      id: r.device.remoteId.str,
      name: name,
      rssi: r.rssi,
      connectable: adv.connectable,
      advertising: BlueStAdvertising.parse(adv.msd),
    );
  }

  @override
  Stream<bool> get isScanning => fbp.FlutterBluePlus.isScanning;

  @override
  Future<void> ensurePermissions() async {
    final sdk = await androidSdkInt();
    if (sdk != null && sdk < 31) {
      // Up to Android 11 BLE scanning requires the location permission.
      final result = await Permission.locationWhenInUse.request();
      if (!result.isGranted) {
        throw const AppError(AppErrorCode.permissionDenied,
            'Su questa versione di Android la scansione BLE richiede il permesso di posizione.');
      }
      return;
    }
    final statuses = await [Permission.bluetoothScan, Permission.bluetoothConnect].request();
    final denied = statuses.values.any((s) => !s.isGranted);
    if (denied) {
      throw const AppError(AppErrorCode.permissionDenied,
          'Permessi Bluetooth negati. Abilitali nelle impostazioni di Android.');
    }
  }

  @override
  Future<void> turnOnAdapter() => fbp.FlutterBluePlus.turnOn();

  @override
  Future<void> startScan({Duration timeout = const Duration(seconds: 15)}) async {
    try {
      await fbp.FlutterBluePlus.startScan(timeout: timeout);
    } catch (e) {
      throw AppError(AppErrorCode.scanFailed,
          'Scansione non riuscita. Verifica Bluetooth e posizione.', cause: e);
    }
  }

  @override
  Future<void> stopScan() => fbp.FlutterBluePlus.stopScan();

  fbp.BluetoothDevice _device(String id) => fbp.BluetoothDevice.fromId(id);

  @override
  Future<void> connect(String deviceId, {required Duration timeout}) async {
    try {
      await _device(deviceId).connect(license: _license, timeout: timeout, mtu: 512);
    } catch (e) {
      final isTimeout = e is TimeoutException || e.toString().contains('timeout');
      throw AppError(
        isTimeout ? AppErrorCode.connectTimeout : AppErrorCode.connectFailed,
        isTimeout
            ? 'Il dispositivo non ha risposto in tempo. Verifica che sia acceso e vicino.'
            : 'Connessione non riuscita.',
        cause: e,
      );
    }
  }

  @override
  Future<void> disconnect(String deviceId) async {
    _characteristics.remove(deviceId);
    await _device(deviceId).disconnect();
  }

  @override
  Stream<LinkState> linkState(String deviceId) =>
      _device(deviceId).connectionState.map((s) => s == fbp.BluetoothConnectionState.connected
          ? LinkState.connected
          : LinkState.disconnected);

  @override
  Future<List<BleServiceInfo>> discover(String deviceId) async {
    final List<fbp.BluetoothService> services;
    try {
      services = await _device(deviceId).discoverServices();
    } catch (e) {
      throw AppError(AppErrorCode.discoveryFailed, 'Lettura dei servizi BLE non riuscita.',
          cause: e);
    }
    final cache = <String, fbp.BluetoothCharacteristic>{};
    final result = <BleServiceInfo>[];
    for (final service in services) {
      final chars = <BleCharInfo>[];
      for (final c in service.characteristics) {
        final info = BleCharInfo(
          serviceUuid: service.uuid.str128,
          uuid: c.uuid.str128,
          canRead: c.properties.read,
          canWrite: c.properties.write,
          canWriteWithoutResponse: c.properties.writeWithoutResponse,
          canNotify: c.properties.notify,
          canIndicate: c.properties.indicate,
        );
        chars.add(info);
        cache[_key(info)] = c;
      }
      result.add(BleServiceInfo(service.uuid.str128, chars));
    }
    _characteristics[deviceId] = cache;
    return result;
  }

  static String _key(BleCharInfo info) => '${info.serviceUuid}/${info.uuid}';

  fbp.BluetoothCharacteristic _characteristic(String deviceId, BleCharInfo info) {
    final c = _characteristics[deviceId]?[_key(info)];
    if (c == null) {
      throw AppError(AppErrorCode.subscribeFailed, 'Caratteristica ${info.uuid} non trovata.');
    }
    return c;
  }

  @override
  Future<int> currentMtu(String deviceId) async => _device(deviceId).mtuNow;

  @override
  Future<void> setHighThroughput(String deviceId, bool enabled) =>
      _device(deviceId).requestConnectionPriority(
        connectionPriorityRequest:
            enabled ? fbp.ConnectionPriority.high : fbp.ConnectionPriority.balanced,
      );

  @override
  Future<void> createBond(String deviceId) => _device(deviceId).createBond();

  @override
  Future<int> readRssi(String deviceId) => _device(deviceId).readRssi();

  @override
  Future<Stream<Uint8List>> subscribe(String deviceId, BleCharInfo characteristic) async {
    final c = _characteristic(deviceId, characteristic);
    final stream = c.onValueReceived.map(Uint8List.fromList);
    try {
      await c.setNotifyValue(true, timeout: 30);
    } catch (e) {
      throw AppError(AppErrorCode.subscribeFailed,
          'Attivazione notifiche non riuscita per ${characteristic.uuid}.', cause: e);
    }
    return stream;
  }

  @override
  Future<void> unsubscribe(String deviceId, BleCharInfo characteristic) async {
    await _characteristic(deviceId, characteristic).setNotifyValue(false);
  }

  @override
  Future<void> write(String deviceId, BleCharInfo characteristic, List<int> value,
      {required bool withoutResponse}) async {
    try {
      await _characteristic(deviceId, characteristic)
          .write(value, withoutResponse: withoutResponse);
    } catch (e) {
      throw AppError(AppErrorCode.writeFailed, 'Scrittura BLE non riuscita.', cause: e);
    }
  }
}
