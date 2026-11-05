import 'dart:async';

import 'app_logger.dart';

enum AppErrorCode {
  bluetoothOff,
  permissionDenied,
  bluetoothUnsupported,
  scanFailed,
  connectFailed,
  connectTimeout,
  discoveryFailed,
  noSupportedFeatures,
  subscribeFailed,
  writeFailed,
  storageFailed,
  exportFailed,
  unknown,
}

/// Typed error with an Italian message that is safe to show to the user.
class AppError implements Exception {
  const AppError(this.code, this.message, {this.cause});

  final AppErrorCode code;
  final String message;
  final Object? cause;

  @override
  String toString() =>
      cause == null ? '${code.name}: $message' : '${code.name}: $message ($cause)';
}

/// Single place where failures are logged and surfaced to the UI.
class ErrorCenter {
  ErrorCenter._();
  static final ErrorCenter instance = ErrorCenter._();

  final StreamController<AppError> _controller =
      StreamController<AppError>.broadcast();

  Stream<AppError> get errors => _controller.stream;

  void report(AppError error, {String tag = 'App'}) {
    logger.e(tag, error.toString());
    _controller.add(error);
  }

  void reportAny(Object error, {String tag = 'App', String? message}) {
    report(
      error is AppError
          ? error
          : AppError(AppErrorCode.unknown, message ?? 'Errore imprevisto',
              cause: error),
      tag: tag,
    );
  }
}
