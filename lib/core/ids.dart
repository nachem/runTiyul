import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Base class for typed, stable string identifiers.
///
/// Using distinct types per entity (rather than passing raw [String]s)
/// prevents accidentally mixing up, for example, a [RouteId] and an
/// [ActivityId] at a call site.
abstract class TypedId {
  const TypedId(this.value);

  final String value;

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is TypedId &&
      other.value == value;

  @override
  int get hashCode => Object.hash(runtimeType, value);

  @override
  String toString() => value;
}

final class RouteId extends TypedId {
  const RouteId(super.value);

  factory RouteId.generate() => RouteId(_uuid.v4());
}

final class RoutePointSourceId extends TypedId {
  const RoutePointSourceId(super.value);
}

final class ActivityId extends TypedId {
  const ActivityId(super.value);

  factory ActivityId.generate() => ActivityId(_uuid.v4());
}

final class OfflineAreaId extends TypedId {
  const OfflineAreaId(super.value);

  factory OfflineAreaId.generate() => OfflineAreaId(_uuid.v4());
}
