import 'package:flutter/foundation.dart';

enum LogLevel { debug, info, warn, error }

typedef LogMeta = Map<String, Object?>;

/// Logger minimo com escopo; o nivel debug some em release.
class AppLogger {
  const AppLogger(this.scope);

  final String scope;

  void debug(String message, [LogMeta? meta]) {
    if (!kDebugMode) {
      return;
    }
    _print(LogLevel.debug, message, meta);
  }

  void info(String message, [LogMeta? meta]) {
    _print(LogLevel.info, message, meta);
  }

  void warn(String message, [LogMeta? meta]) {
    _print(LogLevel.warn, message, meta);
  }

  void error(String message, [Object? error, LogMeta? meta]) {
    _print(LogLevel.error, '$message ${error ?? ''}'.trim(), meta);
  }

  void _print(LogLevel level, String message, LogMeta? meta) {
    final suffix = meta == null || meta.isEmpty ? '' : ' $meta';
    debugPrint('[${level.name.toUpperCase()}][$scope] $message$suffix');
  }
}
