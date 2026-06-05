import 'dart:developer' as developer;

/// A tiny, dependency-free logging facade.
///
/// Wraps `dart:developer.log` so call sites stay clean and we avoid the
/// `avoid_print` lint while still getting structured output in debug tooling.
class AppLogger {
  const AppLogger(this._name);

  final String _name;

  void debug(String message) => _emit(message, level: 500);

  void info(String message) => _emit(message, level: 800);

  void warn(String message) => _emit(message, level: 900);

  void error(String message, [Object? error, StackTrace? stackTrace]) {
    _emit(message, level: 1000, error: error, stackTrace: stackTrace);
  }

  void _emit(
    String message, {
    required int level,
    Object? error,
    StackTrace? stackTrace,
  }) {
    developer.log(
      message,
      name: _name,
      level: level,
      error: error,
      stackTrace: stackTrace,
    );
  }
}
