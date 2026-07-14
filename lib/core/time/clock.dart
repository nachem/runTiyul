/// Abstraction over wall-clock time so calculations and controllers are
/// deterministic and unit-testable.
///
/// Domain code must never call `DateTime.now()` directly; inject a [Clock]
/// instead. See `docs/wiki/03-target-architecture.md` section 7.
abstract class Clock {
  /// The current instant, in UTC.
  DateTime nowUtc();
}

/// Production [Clock] backed by the system clock.
final class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime nowUtc() => DateTime.now().toUtc();
}

/// Deterministic [Clock] for tests. Call [advance] to move time forward.
final class FakeClock implements Clock {
  FakeClock(DateTime initial) : _now = initial.toUtc();

  DateTime _now;

  @override
  DateTime nowUtc() => _now;

  void advance(Duration duration) {
    _now = _now.add(duration);
  }

  void set(DateTime value) {
    _now = value.toUtc();
  }
}
