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

As of 2026-09-22:

- v1.4.3 separates manual **Center view (keep zoom)** from explicit **Fit route
  and content (adjust zoom)**. Center view preserves both scale and rotation;
  empty content is a no-op. Keep automatic route previews fitting as before,
  and keep all toolbar camera actions guarded against delayed startup GPS.
  All 28 focused map/control and 312 local full-suite tests passed.
- v1.4.2 fixes the remaining recenter race: toolbar zoom/recenter now invalidate
  pending startup GPS camera placement before it can force z15. Recenter uses
  the latest live zoom after its fix arrives. Preserve the non-default
  fractional-zoom and both-completion-order regressions; testing only at z15
  hides the failure. All 13 focused camera tests and committed-source hosted CI
  passed; field verification remains pending.
- Battery-saver GPS hardening accepts plausible delayed fixes with a
  time-scaled jump limit, starts a zero-distance segment after five-minute
  outages, and durably pauses on stream failure. Recording map Follow survives
  pinch/double-tap zoom and rotation, one-finger pan disables it, and both
  Follow updates and current-location recenter preserve manual zoom. All 282
  tests and `flutter analyze --no-pub` passed; physical-device Battery Saver
  and outdoor motion behavior remain unverified.

- The 2026-09-06 routing pass: 273 tests, clean `flutter analyze --no-pub`, and a
  successful debug APK build. A synthetic GPS recording exercises forward
  recovery; no physical device was connected.
- Preserve the new independent z14+ vector overlay, bounded/cancellable loads,
  and Offline cache-only behavior. Raster tiles do not prove routing coverage.
- Dense editing uses `RouteEditorDraft` sparse controls over lossless geometry.
  Never flatten a route when switching modes, adopt a partially matched prefix,
  or rerun whole-route snapping merely because an existing edit was saved.
- Matching must retain all input geometry on failure, honor available access/
  grade metadata, and never connect nearby ways through a coarse grid. Forward
  recovery searches shortest within a bounded graph with the initial direction
  constrained during search; off-route fixes must not advance route progress.
- The functional MVP exists under feature-oriented `lib/` directories.
- Android builds and was exercised on an Android 14/API 34 emulator.
- Manual routes, GPX parsing/import, visual route selection, GPS recording,
  activity history, and offline map management are implemented.
- Offline downloads are disabled unless an approved provider or explicit
  development-only override is configured.
- Network-disabled primary-map preview rendered downloaded tiles in Offline
  mode.
- Downloaded-area **Show on map** temporarily previews in Offline mode and
  restores the user's prior source when closed or deleted; it no longer
  persists Offline globally.
- See the current validation counts in `02-implementation-status.md`.
- CyclOSM is restored as an independent choice alongside Streets, Topographic,
  and Satellite. Topographic requests OpenTopoMap directly and overzooms above
  z17; do not add per-tile fallback because it disables memory caching.
- Download jobs and offline mutations share a queue; cancel/drain before
  edit/delete, deduplicate resume, and preserve completed converted tiles.
  Native rendering resources are explicitly disposed. HTTP vector failures
  other than 404 are errors, not missing coverage. Database route updates must
  preserve activity links, and startup failures remain retryable without reset.
- No device was connected for the stability review. The debug APK is not an
  update for the permanent-signed installed app; do not uninstall or clear data
  to work around signature mismatch. Runtime crash attribution remains pending
  targeted device logs/reproduction.
- A separately authorized internal build may compile
  `ALLOW_AUTHORIZED_VIEW_RASTER_DEV_DOWNLOADS=true`; only then can the hidden
  seven-tap unlock promote Topographic and Satellite. Keep the flag disabled by
  default and do not infer provider permission for ordinary builds.
- Pull-request CI, dependency review, Dependabot, SHA-pinned Actions, a fixed
  Flutter 3.44.6 release toolchain, checksums, and provenance are configured.
  Push CI run `35750005333` passed format, analyze, and tests; CodeQL run
  `35750004979` passed; Pages run `30808751792` passed. `v1.4.3` exercised
  the release checksums and both provenance attestations. PR dependency review
  has not been exercised yet.
- Contribution, conduct, support, privacy, and security policies plus issue/PR
  templates and CODEOWNERS are present. GitHub private vulnerability reporting,
  Dependabot security updates, secret scanning, and push protection are enabled;
  `main` remains unprotected.
- `v1.4.3+13` is published from `f32b565` on `main` with center-view zoom
  preservation and separate Fit. Earlier committed download-editor changes in
  `c55f53c` were retained; only an empty test file and unused local were removed
  to unblock validation. Full hosted formatting, analysis, tests, and CodeQL
  passed. Workflow `35750301499`, public hashes and sizes, latest download URLs,
  APK identity/signature, and APK+IPA provenance checks passed on 2026-09-22.
  The tag is immutable; documentation evidence updates must not move it.
  Device testing remains pending.
- Monotonic route-progress announcements and directional off-route route-finder
  alerts are implemented and unit/widget-tested. `v1.4.0+10` adds strict
  connected mapped-way recovery ahead, exact-angle advance/apex and consecutive
  maneuver prompts, bounded route-artifact cleanup, whole-route **Snap to
  trails**, primary-destination Back history, and persisted recording Follow
  position plus north-up/course-up. Completed prompts explicitly release
  transient audio focus, iOS notifies interrupted audio apps on session
  deactivation, and overlapping-alert ownership is tested. Recovery geometry,
  camera behavior, media resumption, heading quality, audio, and locked-screen
  behavior remain physical-device unverified.
- iOS runtime, physical-device background tracking, native GPX picking, free-space
  checks, and production provider configuration remain unverified or
  unimplemented.

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
- Preserve the configured Android application ID and permanent release signing;
  verify an in-place, data-preserving update once two permanent-key builds
  exist.
- iOS bundle/signing configuration.
- Provider credentials through secure build configuration.

## 4. Engineering rules

### 4.1 Correctness

- Use pure, testable Dart for geo and metric calculations.
- Keep off-route recovery on strict connected mapped ways, reconnect beyond
  monotonic progress, and never convert a nearest-route point behind the runner
  into a backtracking instruction.
- Preserve intentional U-turns while cleaning only bounded return-to-junction
  artifacts; route snapping must not introduce straight off-network bridges.
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

For a release, also follow the mandatory
[release-note contract](08-release-notes.md#release-note-contract): bump the app
version/build, add the matching per-tag wiki note, update the release indexes,
and validate before creating or pushing the tag.

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
- Android `audioplayers` low-latency mode uses SoundPool without a completion
  callback. A short cue that requests focus must be explicitly stopped after
  its known duration or other media may remain paused or ducked.
- A Windows host cannot validate iOS runtime behavior.
- OpenMapTiles display geometry is not a complete pedestrian-routing graph.
  Missing topology/access rules require explicit limitations, not invented links.
- SQLite/FFI setup inside widget tests must run through `tester.runAsync`; fake
  time can otherwise deadlock on I/O before the first widget is pumped.
- Editor quick fixes may remain in unsaved buffers. Format/save changed files
  with the Dart tool and rerun the actual analyzer before claiming a clean build.

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
