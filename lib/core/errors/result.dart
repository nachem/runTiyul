import 'app_failure.dart';

/// A result that is either a success value [T] or an [AppFailure].
///
/// Repositories, use cases, and services return [Result] rather than
/// throwing, so that failures are explicit and cannot be accidentally
/// swallowed by a broad `catch`.
sealed class Result<T> {
  const Result();

  /// Creates a successful result.
  const factory Result.ok(T value) = Ok<T>;

  /// Creates a failed result.
  const factory Result.err(AppFailure failure) = Err<T>;

  bool get isOk => this is Ok<T>;

  bool get isErr => this is Err<T>;

  /// Returns the success value, or `null` if this is a failure.
  T? get valueOrNull => switch (this) {
    Ok<T>(:final value) => value,
    Err<T>() => null,
  };

  /// Returns the failure, or `null` if this is a success.
  AppFailure? get failureOrNull => switch (this) {
    Ok<T>() => null,
    Err<T>(:final failure) => failure,
  };

  /// Applies [onOk] or [onErr] depending on the variant.
  R fold<R>(R Function(T value) onOk, R Function(AppFailure failure) onErr) {
    return switch (this) {
      Ok<T>(:final value) => onOk(value),
      Err<T>(:final failure) => onErr(failure),
    };
  }

  /// Transforms the success value, leaving a failure untouched.
  Result<R> map<R>(R Function(T value) transform) {
    return switch (this) {
      Ok<T>(:final value) => Result.ok(transform(value)),
      Err<T>(:final failure) => Result.err(failure),
    };
  }

  /// Chains another [Result]-returning operation, leaving a failure
  /// untouched.
  Result<R> andThen<R>(Result<R> Function(T value) transform) {
    return switch (this) {
      Ok<T>(:final value) => transform(value),
      Err<T>(:final failure) => Result.err(failure),
    };
  }
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);

  final T value;

  @override
  bool operator ==(Object other) => other is Ok<T> && other.value == value;

  @override
  int get hashCode => Object.hash(Ok, value);

  @override
  String toString() => 'Ok($value)';
}

final class Err<T> extends Result<T> {
  const Err(this.failure);

  final AppFailure failure;

  @override
  bool operator ==(Object other) => other is Err<T> && other.failure == failure;

  @override
  int get hashCode => Object.hash(Err, failure);

  @override
  String toString() => 'Err($failure)';
}
