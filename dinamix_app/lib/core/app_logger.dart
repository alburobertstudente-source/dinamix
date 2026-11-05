import 'package:flutter/foundation.dart';

enum AppLogLevel { debug, info, warning, error }

class LogEntry {
  const LogEntry(this.time, this.level, this.tag, this.message);

  final DateTime time;
  final AppLogLevel level;
  final String tag;
  final String message;

  @override
  String toString() =>
      '${time.toIso8601String()} ${level.name.toUpperCase()} [$tag] $message';
}

/// Ring buffer of recent log lines, shown in the diagnostics screen.
class AppLogger {
  AppLogger._();
  static final AppLogger instance = AppLogger._();

  static const int _capacity = 500;
  final List<LogEntry> _entries = [];

  /// Bumped on every new line so that the UI can rebuild only when visible.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  List<LogEntry> get entries => List.unmodifiable(_entries);

  void log(AppLogLevel level, String tag, String message) {
    final entry = LogEntry(DateTime.now(), level, tag, message);
    _entries.add(entry);
    if (_entries.length > _capacity) _entries.removeAt(0);
    revision.value++;
    if (kDebugMode) debugPrint(entry.toString());
  }

  void d(String tag, String message) => log(AppLogLevel.debug, tag, message);
  void i(String tag, String message) => log(AppLogLevel.info, tag, message);
  void w(String tag, String message) => log(AppLogLevel.warning, tag, message);
  void e(String tag, String message) => log(AppLogLevel.error, tag, message);

  void clear() {
    _entries.clear();
    revision.value++;
  }
}

final AppLogger logger = AppLogger.instance;
