import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/app_error.dart';
import '../core/app_logger.dart';
import '../domain/sensor_kind.dart';
import 'protocol/advertising.dart';
import 'protocol/bluest_uuid.dart';
import 'protocol/decoder.dart';
import 'protocol/packet_loss.dart';
import 'transport/ble_transport.dart';

enum ConnectionPhase {
  idle,
  connecting,
  discovering,
  subscribing,
  ready,
  reconnecting,
  failed,
}

/// Receives decoded data. Implemented by the live hub and by the recorder.
abstract class ReadingSink {
  void ingest(SensorReading reading);
}

enum LinkEvent { established, lost, restored }

/// Counters of a characteristic, shown in the diagnostics screen.
class CharacteristicStatus {
  CharacteristicStatus(this.info) : parsed = BlueStUuid.parse(info.uuid);

  final BleCharInfo info;
  final BlueStUuid parsed;
  final PacketLossEstimator loss = PacketLossEstimator();

  bool subscribed = false;
  int bytes = 0;
  int decodeErrors = 0;
  String? lastError;
  String lastHex = '';

  bool get decodable => parsed.decodableKinds.isNotEmpty;
}

/// Target of a connection attempt.
class DeviceRef {
  const DeviceRef(this.id, this.name, {this.advertising});

  final String id;
  final String name;
  final BlueStAdvertising? advertising;
}

/// Connection state machine: connect, discover, subscribe, automatic reconnection.
class ConnectionManager extends ChangeNotifier {
  ConnectionManager(
    this._transport, {
    this.connectTimeout = const Duration(seconds: 20),
    this.maxBackoff = const Duration(seconds: 30),
    Duration Function(int attempt)? backoff,
  }) : _backoff = backoff;

  BleTransport _transport;
  final Duration connectTimeout;
  final Duration maxBackoff;
  final Duration Function(int attempt)? _backoff;

  final List<ReadingSink> _sinks = [];
  final List<StreamSubscription<Uint8List>> _dataSubs = [];
  final StreamController<LinkEvent> _events = StreamController<LinkEvent>.broadcast();
  final StreamController<String> _console = StreamController<String>.broadcast();

  StreamSubscription<LinkState>? _linkSub;
  Timer? _reconnectTimer;
  Timer? _rssiTimer;

  /// Each new user intent invalidates the operations still in progress.
  int _generation = 0;
  bool _wantConnected = false;
  bool _everReady = false;
  bool _linkUp = false;

  ConnectionPhase phase = ConnectionPhase.idle;
  DeviceRef? device;
  AppError? lastError;
  int reconnectAttempt = 0;
  int? mtu;
  int? rssi;
  int linkLossCount = 0;
  DateTime? connectedSince;
  List<BleServiceInfo> services = const [];
  List<CharacteristicStatus> characteristics = const [];

  bool autoReconnect = true;
  bool highThroughput = true;
  Set<SensorKind> disabledKinds = const {};

  /// Called once a connection is fully established (e.g. to save known devices).
  void Function(DeviceRef device)? onReady;

  bool get isSimulated => dataSource == DataSource.simulated;

  /// True when the data does not come from a real SensorTile.
  bool get isDemo => dataSource != DataSource.hardware;
  bool get isReady => phase == ConnectionPhase.ready;
  bool get isBusy =>
      phase == ConnectionPhase.connecting ||
      phase == ConnectionPhase.discovering ||
      phase == ConnectionPhase.subscribing ||
      phase == ConnectionPhase.reconnecting;

  DataSource get dataSource => _transport.dataSource;

  Stream<LinkEvent> get linkEvents => _events.stream;
  Stream<String> get consoleOutput => _console.stream;

  BleTransport get transport => _transport;

  void addSink(ReadingSink sink) => _sinks.add(sink);
  void removeSink(ReadingSink sink) => _sinks.remove(sink);

  /// Kinds available on this firmware, whether enabled by the user or not.
  Set<SensorKind> get availableKinds => {
        for (final c in characteristics)
          if (c.info.canNotify) ...c.parsed.decodableKinds,
      };

  /// Kinds whose notifications are actually enabled.
  Set<SensorKind> get activeKinds => {
        for (final c in characteristics)
          if (c.subscribed) ...c.parsed.decodableKinds,
      };

  int get estimatedLostPackets =>
      characteristics.fold(0, (sum, c) => sum + c.loss.estimatedLost);

  void switchTransport(BleTransport transport) {
    _transport = transport;
    notifyListeners();
  }

  Future<void> connect(DeviceRef target) async {
    if (isBusy || isReady) await disconnect();
    final generation = ++_generation;
    _wantConnected = true;
    _everReady = false;
    device = target;
    lastError = null;
    reconnectAttempt = 0;
    linkLossCount = 0;
    await _establish(generation);
  }

  Future<void> _establish(int generation) async {
    final target = device;
    if (target == null) return;
    final isReconnect = _everReady;
    _setPhase(isReconnect ? ConnectionPhase.reconnecting : ConnectionPhase.connecting);
    try {
      // A reconnection may run in background, where no dialog can be shown.
      if (!isReconnect) await _transport.ensurePermissions();
      await _transport.connect(target.id, timeout: connectTimeout);
      if (generation != _generation) return;
      _linkUp = true;
      await _linkSub?.cancel();
      _linkSub = _transport.linkState(target.id).listen((state) {
        if (generation == _generation) _onLinkState(state, generation);
      });

      _setPhase(isReconnect ? ConnectionPhase.reconnecting : ConnectionPhase.discovering);
      final discovered = await _transport.discover(target.id);
      if (generation != _generation) return;
      services = discovered;
      characteristics = [
        for (final s in discovered)
          for (final c in s.characteristics) CharacteristicStatus(c),
      ];
      logger.i('BLE', '${discovered.length} servizi, ${characteristics.length} caratteristiche');

      mtu = await _safe(() => _transport.currentMtu(target.id));
      if (highThroughput) {
        await _safe(() => _transport.setHighThroughput(target.id, true));
      }
      if (generation != _generation) return;

      if (!isReconnect) _setPhase(ConnectionPhase.subscribing);
      await _subscribeAll(target.id, generation);
      if (generation != _generation) return;
      await _attachConsole(target.id, generation);
      if (generation != _generation) return;

      if (activeKinds.isEmpty && availableKinds.isEmpty) {
        throw const AppError(AppErrorCode.noSupportedFeatures,
            'Il firmware non espone dati decodificabili da questa app. Controlla la schermata Diagnostica.');
      }

      connectedSince = DateTime.now();
      reconnectAttempt = 0;
      lastError = null;
      _setPhase(ConnectionPhase.ready);
      _events.add(isReconnect ? LinkEvent.restored : LinkEvent.established);
      _everReady = true;
      onReady?.call(target);
      _startRssiPolling(target.id, generation);
      logger.i('BLE', 'Pronto: attivi ${activeKinds.map((k) => k.id).join(', ')}');
    } catch (e) {
      if (generation != _generation) return;
      final error = e is AppError
          ? e
          : AppError(AppErrorCode.connectFailed, 'Connessione non riuscita.', cause: e);
      logger.e('BLE', error.toString());
      await _teardownLink(target.id);
      if (generation != _generation) return;
      lastError = error;
      if (_everReady && autoReconnect && _wantConnected) {
        _scheduleReconnect(generation);
      } else {
        _wantConnected = false;
        _setPhase(ConnectionPhase.failed);
        ErrorCenter.instance.report(error, tag: 'BLE');
      }
    }
  }

  Future<T?> _safe<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (e) {
      logger.w('BLE', 'Operazione opzionale non riuscita: $e');
      return null;
    }
  }

  Future<void> _subscribeAll(String id, int generation) async {
    AppError? firstFailure;
    var attempted = 0;
    var succeeded = 0;
    var bondTried = false;
    for (final status in characteristics) {
      if (generation != _generation) return;
      if (!status.info.canNotify || !status.decodable) continue;
      if (status.parsed.decodableKinds.every(disabledKinds.contains)) continue;
      attempted++;
      try {
        await _subscribe(id, status, generation);
        succeeded++;
      } catch (e) {
        if (e is AppError) firstFailure ??= e;
        // Standard ST firmware may require pairing (PIN from the data brief):
        // ask Android to bond once, then retry.
        if (!bondTried) {
          bondTried = true;
          await _safe(() => _transport.createBond(id));
          if (generation != _generation) return;
          try {
            await _subscribe(id, status, generation);
            succeeded++;
            continue;
          } catch (retry) {
            logger.w('BLE', 'Riprova dopo associazione fallita: $retry');
          }
        }
        status.lastError = e.toString();
        logger.w('BLE', 'Notifiche non attive per ${status.info.uuid}: $e');
      }
    }
    if (attempted > 0 && succeeded == 0) {
      throw firstFailure ??
          const AppError(AppErrorCode.subscribeFailed,
              'Nessuna notifica attivata. Se richiesto, associa il dispositivo con il PIN.');
    }
    notifyListeners();
  }

  Future<void> _subscribe(String id, CharacteristicStatus status, int generation) async {
    final stream = await _transport.subscribe(id, status.info);
    if (generation != _generation) return;
    _dataSubs.add(stream.listen(
      (data) => _onData(status, data),
      onError: (Object e) {
        status.lastError = e.toString();
        logger.w('BLE', 'Errore notifica ${status.info.uuid}: $e');
      },
    ));
    status.subscribed = true;
  }

  /// Debug console output is shown in the diagnostics screen. Optional.
  Future<void> _attachConsole(String id, int generation) async {
    for (final status in characteristics) {
      if (!status.parsed.isDebugConsole && !status.parsed.isDebugStderr) continue;
      if (!status.info.canNotify) continue;
      try {
        final stream = await _transport.subscribe(id, status.info);
        if (generation != _generation) return;
        _dataSubs.add(stream.listen((data) {
          status.bytes += data.length;
          _console.add(utf8.decode(data, allowMalformed: true));
        }));
        status.subscribed = true;
      } catch (e) {
        logger.w('BLE', 'Console di debug non attiva: $e');
      }
    }
  }

  void _onData(CharacteristicStatus status, Uint8List data) {
    status.bytes += data.length;
    status.lastHex = hexString(data);
    final receivedAt = DateTime.now().millisecondsSinceEpoch;
    try {
      final result = BlueStDecoder.decode(
        uuid: status.parsed,
        data: data,
        receivedAtMs: receivedAt,
        source: dataSource,
      );
      status.loss.add(result.ticks);
      for (final reading in result.readings) {
        for (final sink in _sinks) {
          sink.ingest(reading);
        }
      }
    } on DecodeException catch (e) {
      status.decodeErrors++;
      status.lastError = e.message;
      // A malformed stream must not flood the log.
      if (status.decodeErrors <= 5) logger.w('Decoder', '${status.info.uuid}: ${e.message}');
    }
  }

  void _onLinkState(LinkState state, int generation) {
    if (state == LinkState.connected) return;
    if (!_linkUp) return;
    _linkUp = false;
    linkLossCount++;
    logger.w('BLE', 'Collegamento perso');
    _clearSubscriptions();
    _stopRssi();
    connectedSince = null;
    if (phase == ConnectionPhase.ready) _events.add(LinkEvent.lost);
    if (_wantConnected && autoReconnect) {
      _scheduleReconnect(generation);
    } else {
      _wantConnected = false;
      _everReady = false;
      lastError = const AppError(AppErrorCode.connectFailed, 'Collegamento perso.');
      _setPhase(ConnectionPhase.failed);
    }
  }

  /// Exponential backoff: 1, 2, 4... up to [maxBackoff].
  @visibleForTesting
  Duration backoffFor(int attempt) {
    final custom = _backoff;
    if (custom != null) return custom(attempt);
    final seconds = math.min(maxBackoff.inSeconds, 1 << math.min(attempt, 10));
    return Duration(seconds: seconds);
  }

  void _scheduleReconnect(int generation) {
    final delay = backoffFor(reconnectAttempt);
    reconnectAttempt++;
    _setPhase(ConnectionPhase.reconnecting);
    logger.i('BLE', 'Riconnessione $reconnectAttempt tra ${delay.inMilliseconds} ms');
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      if (generation == _generation && _wantConnected) _establish(generation);
    });
  }

  Future<void> disconnect() async {
    _generation++;
    _wantConnected = false;
    _everReady = false;
    _reconnectTimer?.cancel();
    _stopRssi();
    final id = device?.id;
    _linkUp = false;
    await _linkSub?.cancel();
    _linkSub = null;
    _clearSubscriptions();
    if (id != null) await _safe(() => _transport.disconnect(id));
    connectedSince = null;
    characteristics = const [];
    services = const [];
    rssi = null;
    mtu = null;
    _setPhase(ConnectionPhase.idle);
  }

  Future<void> _teardownLink(String id) async {
    _linkUp = false;
    await _linkSub?.cancel();
    _linkSub = null;
    _clearSubscriptions();
    await _safe(() => _transport.disconnect(id));
  }

  void _clearSubscriptions() {
    for (final sub in _dataSubs) {
      sub.cancel();
    }
    _dataSubs.clear();
    for (final c in characteristics) {
      c.subscribed = false;
    }
  }

  void _startRssiPolling(String id, int generation) {
    _stopRssi();
    _rssiTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (generation != _generation || !isReady) return;
      final value = await _safe(() => _transport.readRssi(id));
      if (value != null && generation == _generation) {
        rssi = value;
        notifyListeners();
      }
    });
  }

  void _stopRssi() {
    _rssiTimer?.cancel();
    _rssiTimer = null;
  }

  /// Sends a text command to the BlueST debug console, split in 20 byte chunks.
  Future<void> sendConsoleCommand(String command) async {
    final target = device;
    if (target == null || !isReady) return;
    CharacteristicStatus? console;
    for (final c in characteristics) {
      if (c.parsed.isDebugConsole) console = c;
    }
    if (console == null) {
      throw const AppError(AppErrorCode.writeFailed, 'Questo firmware non espone la console di debug.');
    }
    final bytes = utf8.encode('$command\n');
    for (var i = 0; i < bytes.length; i += 20) {
      await _transport.write(
        target.id,
        console.info,
        bytes.sublist(i, math.min(i + 20, bytes.length)),
        withoutResponse: !console.info.canWrite,
      );
    }
  }

  void _setPhase(ConnectionPhase next) {
    phase = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _stopRssi();
    _linkSub?.cancel();
    _clearSubscriptions();
    _events.close();
    _console.close();
    super.dispose();
  }
}

String hexString(List<int> data) =>
    data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
