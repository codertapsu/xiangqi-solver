import 'package:equatable/equatable.dart';

import '../errors/failure.dart';

/// A lightweight functional result type used across the data layer.
///
/// Every repository method returns an [ApiResult] so callers handle success and
/// failure explicitly instead of relying on thrown exceptions bubbling up into
/// the UI. Use [when] to fold both cases.
sealed class ApiResult<T> extends Equatable {
  const ApiResult();

  /// Wraps a successful [value].
  const factory ApiResult.success(T value) = Success<T>;

  /// Wraps a [failure].
  const factory ApiResult.failure(Failure failure) = FailureResult<T>;

  bool get isSuccess => this is Success<T>;
  bool get isFailure => this is FailureResult<T>;

  /// Returns the value if this is a [Success], otherwise `null`.
  T? get valueOrNull => switch (this) {
    Success<T>(:final value) => value,
    FailureResult<T>() => null,
  };

  /// Returns the failure if this is a [FailureResult], otherwise `null`.
  Failure? get failureOrNull => switch (this) {
    Success<T>() => null,
    FailureResult<T>(:final failure) => failure,
  };

  /// Folds both cases into a single value of type [R].
  R when<R>({
    required R Function(T value) success,
    required R Function(Failure failure) failure,
  }) {
    return switch (this) {
      Success<T>(value: final v) => success(v),
      FailureResult<T>(failure: final f) => failure(f),
    };
  }

  /// Maps the success value, preserving a failure unchanged.
  ApiResult<R> map<R>(R Function(T value) transform) {
    return switch (this) {
      Success<T>(value: final v) => ApiResult<R>.success(transform(v)),
      FailureResult<T>(failure: final f) => ApiResult<R>.failure(f),
    };
  }
}

class Success<T> extends ApiResult<T> {
  const Success(this.value);

  final T value;

  @override
  List<Object?> get props => [value];
}

class FailureResult<T> extends ApiResult<T> {
  const FailureResult(this.failure);

  final Failure failure;

  @override
  List<Object?> get props => [failure];
}
