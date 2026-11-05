import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/app_error.dart';
import '../core/app_logger.dart';
import 'transport/ble_transport.dart';

/// Scan state and adapter status for the UI.
class DeviceScanner extends ChangeNotifier {
  DeviceScanner(this._transport) {
    _bind();
  }

  BleTransport _transport;
  StreamSubscription<List<BleScanResult>>? _resultsSub;
  StreamSubscription<bool>? _scanningSub;
  StreamSubscription<AdapterStatus>? _adapterSub;

  List<BleScanResult> results = const [];
  bool isScanning = false;
  AdapterStatus adapterStatus = AdapterStatus.unknown;
  bool onlyBlueSt = true;

  /// Devices for the list: strongest signal first, SensorTile.box PRO on top.
  List<BleScanResult> get visibleResults {
    final list = results
        .where((r) => !onlyBlueSt || r.advertising != null)
        .toList()
      ..sort((a, b) {
        final aTarget = a.advertising?.isSensorTileBoxPro ?? false;
        final bTarget = b.advertising?.isSensorTileBoxPro ?? false;
        if (aTarget != bTarget) return aTarget ? -1 : 1;
        return b.rssi.compareTo(a.rssi);
      });
    return list;
  }

  void setOnlyBlueSt(bool value) {
    onlyBlueSt = value;
    notifyListeners();
  }

  void switchTransport(BleTransport transport) {
    _transport = transport;
    results = const [];
    isScanning = false;
    _unbind();
    _bind();
    notifyListeners();
  }

  void _bind() {
    adapterStatus = _transport.adapterStatusNow;
    _adapterSub = _transport.adapterStatus.listen((status) {
      adapterStatus = status;
      notifyListeners();
    });
    _resultsSub = _transport.scanResults.listen(
      (list) {
        results = list;
        notifyListeners();
      },
      onError: (Object e) => ErrorCenter.instance.reportAny(e, tag: 'Scan'),
    );
    _scanningSub = _transport.isScanning.listen((scanning) {
      isScanning = scanning;
      notifyListeners();
    });
  }

  void _unbind() {
    _adapterSub?.cancel();
    _resultsSub?.cancel();
    _scanningSub?.cancel();
  }

  Future<void> turnOnBluetooth() async {
    try {
      await _transport.ensurePermissions();
      await _transport.turnOnAdapter();
    } catch (e) {
      ErrorCenter.instance.reportAny(e, tag: 'Scan', message: 'Bluetooth non attivato');
    }
  }

  Future<void> start() async {
    try {
      await _transport.ensurePermissions();
      if (_transport.adapterStatusNow != AdapterStatus.on) {
        throw const AppError(AppErrorCode.bluetoothOff, 'Attiva il Bluetooth per cercare i dispositivi.');
      }
      results = const [];
      notifyListeners();
      logger.i('Scan', 'Avvio scansione');
      await _transport.startScan(timeout: const Duration(seconds: 15));
    } catch (e) {
      ErrorCenter.instance.reportAny(e, tag: 'Scan', message: 'Scansione non riuscita');
    }
  }

  Future<void> stop() async {
    try {
      await _transport.stopScan();
    } catch (e) {
      logger.w('Scan', 'Arresto scansione: $e');
    }
  }

  @override
  void dispose() {
    _unbind();
    super.dispose();
  }
}
