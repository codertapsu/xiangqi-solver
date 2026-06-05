/// Low-level exceptions thrown by data sources and platform integrations.
///
/// These are intentionally distinct from [Failure] (in `failure.dart`), which
/// is the user-facing, presentation-layer representation. Data sources throw
/// exceptions; repositories catch them and map them to failures.
library;

/// Base type for all app exceptions so they can be caught uniformly.
abstract class AppException implements Exception {
  const AppException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => '$runtimeType(code: $code, message: $message)';
}

/// A transport-level networking error (timeout, connection refused, etc.).
class NetworkException extends AppException {
  const NetworkException(super.message, {super.code});
}

/// The server responded but with a non-2xx status or an error envelope.
class ServerException extends AppException {
  const ServerException(
    super.message, {
    super.code,
    this.statusCode,
    this.details,
  });

  final int? statusCode;
  final Object? details;
}

/// A response body could not be parsed into the expected model.
class ParseException extends AppException {
  const ParseException(super.message, {super.code});
}

/// A native platform call failed or is unavailable on this platform.
class PlatformChannelException extends AppException {
  const PlatformChannelException(super.message, {super.code});
}

/// A required local file (e.g. a screenshot) is missing or invalid.
class FileException extends AppException {
  const FileException(super.message, {super.code});
}
