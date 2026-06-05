import 'package:equatable/equatable.dart';

/// User-facing, presentation-friendly representation of an error.
///
/// Repositories translate low-level [AppException]s into [Failure]s so the UI
/// layer never has to reason about transport details. Every failure carries a
/// short [message] suitable for direct display.
sealed class Failure extends Equatable {
  const Failure(this.message, {this.code});

  /// A concise, user-readable description of what went wrong.
  final String message;

  /// An optional machine-readable code (e.g. from the backend envelope or a
  /// [PlatformException]).
  final String? code;

  @override
  List<Object?> get props => [message, code];

  @override
  String toString() => '$runtimeType(code: $code, message: $message)';
}

/// Networking failed before/while talking to the backend.
class NetworkFailure extends Failure {
  const NetworkFailure(super.message, {super.code});
}

/// The backend returned an error response.
class ServerFailure extends Failure {
  const ServerFailure(super.message, {super.code, this.statusCode});

  final int? statusCode;

  @override
  List<Object?> get props => [...super.props, statusCode];
}

/// A response could not be decoded into the expected shape.
class ParseFailure extends Failure {
  const ParseFailure(super.message, {super.code});
}

/// A native (platform-channel) operation failed.
class PlatformFailure extends Failure {
  const PlatformFailure(super.message, {super.code});
}

/// A required permission (overlay / screen capture) was denied.
class PermissionFailure extends Failure {
  const PermissionFailure(super.message, {super.code});
}

/// A local file operation failed.
class FileFailure extends Failure {
  const FileFailure(super.message, {super.code});
}

/// A catch-all for anything not covered above.
class UnknownFailure extends Failure {
  const UnknownFailure(super.message, {super.code});
}

/// On-device (Offline) mode could not complete — e.g. the local engine is not
/// bundled yet, or the user's own API key is missing.
class OnDeviceFailure extends Failure {
  const OnDeviceFailure(super.message, {super.code});
}
