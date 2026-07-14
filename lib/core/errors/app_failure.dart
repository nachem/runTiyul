/// Typed application failures.
///
/// Repositories and services return an [AppFailure] instead of throwing or
/// silently returning empty/default data, so callers can distinguish "no
/// data" from "could not read data". See `docs/wiki/03-target-architecture.md`
/// section 2 for the underlying rule.
sealed class AppFailure {
  const AppFailure(this.message);

  /// Human-readable, UI-safe description of the failure.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// User-supplied or imported data failed validation (e.g. malformed GPX,
/// invalid bounds, invalid zoom range).
final class ValidationFailure extends AppFailure {
  const ValidationFailure(super.message);
}

/// A local storage operation (database or filesystem) failed.
final class StorageFailure extends AppFailure {
  const StorageFailure(super.message, {this.cause});

  /// The underlying exception, retained for logs/diagnostics only. Never
  /// shown directly to the user.
  final Object? cause;
}

/// A network/tile-provider request failed.
final class NetworkFailure extends AppFailure {
  const NetworkFailure(super.message, {this.statusCode, this.cause});

  /// HTTP status code when available.
  final int? statusCode;

  final Object? cause;

  /// Whether retrying the same request might succeed later.
  bool get isTransient =>
      statusCode == null ||
      statusCode == 408 ||
      statusCode == 429 ||
      (statusCode! >= 500 && statusCode! < 600);
}

/// A required OS permission was denied, permanently denied, or the
/// underlying service (e.g. location services) is disabled.
final class PermissionFailure extends AppFailure {
  const PermissionFailure(super.message, {required this.reason});

  final PermissionFailureReason reason;
}

enum PermissionFailureReason {
  denied,
  permanentlyDenied,
  serviceDisabled,
  restricted,
}

/// A requested entity does not exist.
final class NotFoundFailure extends AppFailure {
  const NotFoundFailure(super.message);
}

/// Parsing of an imported file (GPX) failed.
final class ParsingFailure extends AppFailure {
  const ParsingFailure(super.message, {this.cause});

  final Object? cause;
}

/// An operation was cancelled by the user or the system.
final class CancelledFailure extends AppFailure {
  const CancelledFailure([super.message = 'Operation cancelled.']);
}

/// A safety limit (tile count, download size, zoom span) was exceeded.
final class LimitExceededFailure extends AppFailure {
  const LimitExceededFailure(super.message);
}

/// Insufficient device storage to complete an operation.
final class InsufficientStorageFailure extends AppFailure {
  const InsufficientStorageFailure(super.message);
}

/// A requested state transition is not valid from the current state.
final class InvalidStateFailure extends AppFailure {
  const InvalidStateFailure(super.message);
}
