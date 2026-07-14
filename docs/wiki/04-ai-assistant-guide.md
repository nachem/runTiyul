# AI Assistant Development Guide

This document is the handoff contract for future AI coding assistants working
on RunTiyul.

## 1. Start here

Before editing code:

1. Read the repository-level `AGENTS.md`.
2. Read `docs/wiki/INDEX.md`.
3. Read `docs/wiki/01-product-requirements.md`.
4. Read `docs/wiki/02-implementation-status.md`.
5. Read the relevant section of `docs/wiki/03-target-architecture.md`.
6. Inspect the actual source and tests; never rely only on the wiki snapshot.
7. Check the working tree before editing and preserve unrelated user changes.
8. Run baseline analysis/tests when the existing toolchain permits.

The product requirements describe desired behavior. The implementation status
describes a dated snapshot. Code and tests determine what is currently real.

## 2. Current handoff

As of 2026-07-14:

- The functional MVP exists under feature-oriented `lib/` directories.
- Android builds and was exercised on an Android 14/API 34 emulator.
- Manual routes, GPX parsing/import, visual route selection, GPS recording,
  activity history, and offline map management are implemented.
- Offline downloads are disabled unless an approved provider or explicit
  development-only override is configured.
- Network-disabled primary-map preview rendered downloaded tiles in Offline
  mode.
- Format and analyzer pass; 14 automated tests pass.
- iOS, physical-device background tracking, native GPX picking, route progress,
  off-route alerts, free-space checks, and production provider configuration
  remain unverified or unimplemented.

Use `02-implementation-status.md` for the exact feature matrix. Do not upgrade a
partial or emulator-only status without new source, tests, and runnable
verification evidence.

## 3. Recommended implementation sequence

The milestones below remain the intended dependency order. Milestones 1 and 2
have an MVP implementation; milestones 3 and 4 are partially complete and need
the documented hardening. Do not reimplement working slices without inspecting
their current source and tests.

### Milestone 1: application foundation

- Replace the demo with the app entry point, theme, and primary navigation.
- Establish feature directories and Riverpod dependency boundaries.
- Add domain IDs/value objects and typed failures.
- Add database initialization, schema versioning, and migration tests.
- Add explicit loading/error/empty presentation patterns.

Exit criteria:

- App shell runs on Android.
- Analyzer and tests pass.
- A database can be created, closed, reopened, and migrated in tests.

### Milestone 2: routes and map

- Add map provider configuration and visible attribution.
- Add route entities and SQLite repository.
- Implement GPX import with malformed/empty/duplicate cases.
- Implement route library/detail.
- Implement waypoint route editing and persistence.

Exit criteria:

- Imported and manually created routes survive restart.
- Route detail renders geometry and summary.
- GPX/domain/repository tests pass.

### Milestone 3: recording and navigation

- Add location permission and settings flows.
- Add injectable location stream and clock.
- Add recoverable activity state machine and incremental persistence.
- Add pure metric calculations.
- Add live route/track map and basic route progress/off-route logic.
- Configure and test platform background recording.

Exit criteria:

- Synthetic metric tests pass.
- Force-stop recovery works.
- Real-device screen-lock recording is documented and verified.

### Milestone 4: offline maps and storage

- Select and document an approved offline tile provider.
- Implement tile planner and safety limits.
- Implement durable bounded download queue with resume/cancel/retry.
- Implement local-first tile provider.
- Implement area list, actual byte accounting, overlap-safe deletion, and
  reconciliation.

Exit criteria:

- A selected area renders in airplane mode.
- Interrupted download resumes.
- Deletion does not break overlapping areas.
- Reported usage matches files on disk.

### Milestone 5: release hardening

- GPX activity export.
- Accessibility review.
- Battery and performance profiling.
- Permission denial and low-storage integration tests.
- Android release signing and final application ID.
- iOS bundle/signing configuration.
- Provider credentials through secure build configuration.

## 4. Engineering rules

### 4.1 Correctness

- Use pure, testable Dart for geo and metric calculations.
- Persist recording/download progress incrementally.
- Use database transactions for state transitions and related records.
- Preserve nullable sensor data; do not convert missing elevation to zero.
- Store UTC, format local time only in presentation.
- Surface invalid input and storage/network failures explicitly.

### 4.2 Offline behavior

- Test offline behavior by disabling network, not by assuming a cache hit.
- Never mark an area complete based only on attempted requests.
- Do not fall back silently to online tiles when the UI claims offline mode.
- Keep tile source identity in every cache key and offline area.
- Treat storage estimates and actual byte counts as different values.

### 4.3 Provider policy

- Do not implement bulk download against `tile.openstreetmap.org`.
- Verify provider offline terms before selecting a production default.
- Keep provider URLs, headers, attribution, rate limits, and zoom limits
  configurable.
- Do not commit provider secrets.

### 4.4 Location and privacy

- Request permissions progressively and only when needed.
- Background location must have a user-visible recording purpose.
- Never log full tracks or upload user location by default.
- Test denied, permanently denied, service-disabled, and no-fix states.
- Do not claim safety, rescue, or guaranteed navigation accuracy.

### 4.5 Type and error safety

- Avoid `dynamic`, `as any`, broad catches, and silent fallback values.
- Repositories must distinguish empty data from read failure.
- Use immutable state and exhaustive state transitions.
- Reuse shared geo/value types instead of passing loosely related primitives.
- Validate imported XML, coordinates, bounds, zoom levels, and filenames.

## 5. Change workflow

For each feature:

1. Identify requirement IDs being implemented.
2. Inspect existing code and search for reusable abstractions.
3. Add or update tests for domain and failure behavior.
4. Implement the smallest complete vertical slice.
5. Format changed Dart files.
6. Run targeted tests, full tests, and analyzer.
7. Run on a suitable emulator/device for UI or plugin changes.
8. Update `02-implementation-status.md` with evidence and an absolute date.
9. Update architecture only when the design changed.
10. Update `docs/wiki/INDEX.md` when project status, priorities, decisions,
    validation, or wiki contents changed.
11. Verify local Markdown links.
12. Report limitations honestly.

Do not update the status document to "implemented" before verification.

## 6. Validation commands

From the repository root on Windows:

```powershell
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter devices
flutter run -d <device-id>
```

For Android release readiness:

```powershell
flutter build apk
flutter build appbundle
```

iOS validation must run on macOS:

```bash
flutter build ios --no-codesign
flutter test
```

Only run tools already used by the repository unless a new tool is genuinely
required. Apply dependency changes with `flutter pub get` and include the
updated lockfile.

## 7. Test expectations by change type

| Change | Minimum verification |
| --- | --- |
| Pure domain calculation | Unit tests plus full `flutter test` |
| SQLite schema/repository | Migration and repository tests using a supported test database |
| Widget/screen | Widget tests plus emulator/device smoke test |
| Permission behavior | Widget/controller tests and real-device platform test |
| GPS recording | Synthetic stream tests and real-device background test |
| Tile planner | Boundary, high-latitude, antimeridian, and safety-limit unit tests |
| Downloader | Fake HTTP tests for success, retry, permanent failure, cancel, resume |
| Offline rendering | Integration test with network disabled |
| Storage deletion | Overlap, missing file, partial failure, and reconciliation tests |
| Documentation only | Verify links and factual consistency; code tests optional |

## 8. Documentation update format

When a feature becomes real, add to the implementation status:

- Requirement IDs.
- Exact source modules.
- Persistence or platform changes.
- Test files and scenarios.
- Commands run and results.
- Real-device validation details when relevant.
- Known limitations that still differ from requirements.
- Absolute validation date.

Avoid statements such as "offline maps complete" when only online caching
exists. State whether the user can select bounds, choose zooms, see estimates,
resume, use airplane mode, view usage, and delete data.

## 9. Known traps

- `flutter_map` rendering alone does not provide offline downloads.
- HTTP cache behavior is not an offline area manager.
- Adding `geolocator` does not configure Android/iOS permissions or background
  recording.
- Adding `sqflite` does not create a schema or migrations.
- A finished activity saved only on Finish is vulnerable to process death.
- Public OpenStreetMap data is open, but the public standard tile service is not
  a free bulk/offline tile API.
- File byte totals can diverge from metadata after crashes; reconciliation is
  required.
- Overlapping areas make naive recursive directory deletion unsafe.
- GPS altitude is noisy; summing every positive delta exaggerates elevation.
- A Windows host cannot validate iOS runtime behavior.

## 10. Definition of an honest completion report

A completion report must say:

- What behavior was implemented.
- Which requirement IDs it satisfies.
- What was tested and on which target.
- What remains unimplemented.
- Whether offline mode was tested with networking disabled.
- Whether background tracking was tested on a real device.
- Whether provider licensing/configuration is production-ready.

If verification could not be run, state that the work is unverified rather than
inferring success from code inspection.
