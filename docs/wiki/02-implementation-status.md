# Implemented Details and Current Status

Snapshot date: 2026-07-14  
Overall status: functional Flutter MVP verified on an Android 14 emulator

## 1. Executive summary

RunTiyul now provides a local-first mobile MVP with:

- Material 3 navigation for Map, Routes, Record, Activities, and Offline Maps.
- Online OpenStreetMap-compatible map display with attribution.
- Manual waypoint route creation and GPX import.
- SQLite persistence for routes, activities, samples, offline areas, and tile
  references.
- GPS activity recording with live metrics and recovery-safe incremental sample
  writes.
- Rectangular offline map selection, tile estimates, gated downloads, progress,
  resume, deletion, actual byte usage, and primary-map offline preview/editing.
- Android and iOS location/background configuration.

The MVP is not production-ready. A production map provider that explicitly
permits offline downloads has not been selected. iOS and physical-device
background recording have not been verified. Route-progress and off-route
guidance are not implemented.

A PMTiles-first long-term architecture is documented in
`06-offline-map-packages.md`. It is a proposal only: no MapLibre renderer,
client tile extractor, terrain layer, source manifest, build pipeline, or
production hosting has been implemented or selected.

## 2. Verified feature matrix

| Product area | State | Evidence and limitations |
| --- | --- | --- |
| Flutter Android project | Implemented and emulator verified | Debug APK built and launched on Android 14 API 34. |
| Flutter iOS project | Configured, not runtime verified | Location descriptions and background location mode exist; no macOS/Xcode validation was available. |
| Material application shell | Implemented | Five primary destinations use Material 3 `NavigationBar`. |
| Online map display | Implemented | `flutter_map` tile layer, pan/zoom, provider configuration, and attribution. |
| Map camera controls | Implemented and emulator verified | Primary map exposes zoom in/out, fit current location plus route/checkpoints, and fresh-GPS recenter controls. |
| Map source choice | Implemented and emulator verified | Auto is offline-first with network fallback; Online bypasses files; Offline makes no network requests, is always selectable, and fits/displays downloaded-area bounds for discovery. Choice persists in `app_settings`. |
| Offline zoom limits | Implemented and emulator verified | Focused offline areas constrain gestures and buttons to their downloaded minimum/maximum zoom; controls disable at each boundary. |
| Current GPS location | Implemented, emulator permission verified | Location service and map marker exist; denied/settings flows are surfaced as errors but not comprehensively device-tested. |
| GPX import | Implemented, parser unit-tested | Uses the platform `file_selector`; the native picker was not exercised in the emulator verification. |
| Manual route creation | Implemented and emulator verified | Map taps add ordered waypoints; undo, name, save, and straight-line display work. |
| Route library/detail/management | Implemented | Routes persist in SQLite; detail, rename, duplicate, and delete actions are exposed. Rename/duplicate persistence is unit-tested. |
| Route map integration | Implemented and emulator verified | All saved trails in/partly in the viewport render by default; tapping a route opens the primary Map tab and emphasizes it with the full map controls. |
| Route progress/off-route alerts | Not implemented | Version 1 currently provides visual line-following only. |
| GPS activity tracking | Implemented and emulator verified | Start, permission request, pause, resume, finish, discard, timer, and persisted samples. |
| Live metrics | Implemented | Elapsed time, distance, average pace, and smoothed-threshold elevation gain are shown. Moving time is not calculated separately. |
| Background recording | Configured, not physical-device verified | Geolocator foreground notification/background settings and platform permissions exist. |
| Activity recovery | Implemented | Samples and summaries are written incrementally; interrupted active activities reload as paused. |
| Activity history/detail/delete | Implemented and emulator verified | Completed activity appears in history with summary and track map. |
| Activity GPX export | Implemented and serialization-tested | Activity samples export as a GPX 1.1 track through the native save dialog; the native dialog was not emulator-tested. |
| Offline area selection | Implemented and emulator verified | Two map corners, zoom range, estimate, and 1,200-tile safety limit. |
| Offline map download | Implemented and emulator verified | Four bounded workers, timeout, transient retry, progress persistence, pause/cancel, and resume. |
| Provider policy gate | Implemented | Downloads require an approved provider flag or explicit development-only OSM override. The standard VS Code debug launch supplies the development override; profile and release remain gated. |
| Offline tile rendering | Implemented and offline verified | File-backed tiles are preferred; saved areas open on the primary Map tab with bounds, offline-only tiles, controls, and an edit-bounds action. |
| Offline storage usage | Implemented | Actual file byte totals are persisted and shown per area and in aggregate. |
| Overlap-safe deletion | Implemented | Shared tile references prevent removal while another area references a tile. |
| Download crash recovery | Implemented and unit-tested | Areas left `downloading` after restart become `paused` and resumable. |
| Free-space check/orphan cleanup | Not implemented | The app does not yet show available device bytes or reconcile orphaned files. |
| Product documentation | Implemented | Requirements, architecture, AI instructions, local debugging, and current status are indexed. |

## 3. Source architecture

```text
lib/
|-- app/
|   |-- app.dart                    Material application and navigation shell
|   `-- app_store.dart              Application workflows and observable state
|-- core/
|   |-- errors/                     Typed failure primitives
|   |-- geo/                        Distance, bounds, and XYZ tile planning
|   |-- time/                       Injectable clock
|   `-- units/                      Duration, pace, byte, distance formatting
|-- data/
|   |-- app_database.dart           SQLite initialization and version 1 schema
|   `-- app_repository.dart         Route/activity/offline persistence
|-- features/
|   |-- activities/                 History and detail UI
|   |-- map/                        Shared map and main map UI
|   |-- offline_maps/               Area selection, management, preview
|   |-- recording/                  Live activity UI
|   `-- routes/                     Library, detail, and manual editor
|-- models/                         Route, activity, and offline area entities
|-- services/
|   |-- gpx_service.dart            GPX route import and activity export
|   |-- location_service.dart       Permission and position stream adapter
|   |-- map_provider.dart           Compile-time provider configuration
|   |-- offline_download_service.dart
|   `-- tile_store.dart             Deterministic files and map tile provider
`-- main.dart
```

The current `AppStore` is intentionally small enough for an MVP but combines
several workflows. Future growth should split route, recording, and download
controllers according to the target architecture.

## 4. Persistence

SQLite schema version 1 creates:

- `routes`
- `route_points`
- `activities`
- `activity_samples`
- `offline_areas`
- `tiles`
- `offline_area_tiles`
- `app_settings`

Foreign keys and cascades are enabled. Route points and activity samples use
stable per-parent sequence keys. Tile identity includes provider, zoom, x, and
y. Offline area updates use a non-destructive upsert so progress writes preserve
tile references. Bounds edits transactionally remove obsolete references while
retaining tiles still in the new plan; deletion queries reference counts before
removing shared files.

Tile image files are stored under the application support directory:

```text
offline_tiles/<provider-id>/<zoom>/<x>/<y>.png
```

Database migration infrastructure beyond initial schema creation is not yet
implemented. A version 2 change must add an explicit migration rather than
altering version 1 creation only.

### 4.1 Map interaction and source modes

The primary map has explicit controls for zoom in/out, fitting current location
with route/checkpoint content, and obtaining then centering on a current GPS
fix. Its source menu offers:

- **Auto:** use a downloaded tile when present, otherwise request it online.
- **Online:** always request tiles from the configured provider.
- **Offline:** use downloaded files only, render missing tiles transparently,
  and show completed-area bounds so downloads can be found.

Offline is always selectable. Selecting it fits completed downloaded areas when
available. A focused area restricts pan/pinch and zoom buttons to its configured
downloaded zoom range; zoom buttons disable at the minimum and maximum. The
selected mode is stored in `app_settings` and restored after restart.

## 5. Routes and GPX

Implemented:

- Native GPX file selection using `file_selector`.
- GPX track parsing, route fallback, coordinate validation, name fallback, and
  empty-file rejection.
- Duplicate route names receive a suffix rather than silently overwriting.
- Manual map waypoint placement and undo.
- Straight-line route geometry with calculated geodesic distance.
- Route library, detail map, selection, rename, duplicate, and confirmed
  deletion.
- All saved routes render on the primary map when fully or partially in view.
- Tapping a route selects it and switches to the primary map with all controls.

Limitations:

- Duplicate imports do not yet offer replace/cancel choices.
- Manual routing does not snap to paths or trails.
- GPX native picker integration was not emulator-tested.

## 6. Recording and activities

Implemented:

- Progressive location permission request.
- Platform-specific high-accuracy streams.
- Android foreground recording notification configuration.
- Start, pause, resume, finish, and confirmed discard.
- Accuracy rejection above 60 meters and implausible jump rejection above 200
  meters.
- Incremental activity sample and summary transactions.
- Elapsed time, geodesic distance, pace, and threshold-filtered elevation gain.
- Active activity recovery as paused after process restart.
- Route, recorded track, and current position map layers.
- Activity history, detail summary/map, and confirmed deletion.
- GPX 1.1 activity export through the platform save dialog.

Limitations:

- A real physical-device screen-lock/background test has not been performed.
- Emulator movement produced one persisted sample but did not emit enough
  sequential fixes to verify distance changes live.
- Moving time is not distinct from elapsed time.
- Current pace uses the full activity average, not a rolling window.
- Route progress, course-up mode, off-route detection, and alerts are absent.
- The native GPX save dialog was not emulator-tested.

## 7. Offline maps and provider configuration

The default map is the public OpenStreetMap standard service for interactive
development display. Offline download is disabled by default.

Approved provider configuration:

```powershell
flutter run -d emulator-5554 `
  --dart-define=TRAIL_TILE_PROVIDER_ID=my-provider `
  --dart-define=TRAIL_TILE_URL=https://example.com/{z}/{x}/{y}.png `
  --dart-define=TRAIL_TILE_ATTRIBUTION="Provider attribution" `
  --dart-define=TRAIL_TILE_OFFLINE_ALLOWED=true
```

Small development-only override:

```powershell
flutter run -d emulator-5554 `
  --dart-define=ENABLE_DEV_OSM_DOWNLOADS=true
```

The repository's `Running App` VS Code debug launch configuration supplies this
override automatically. Profile and release launch configurations intentionally
do not enable it.

The override is visibly labeled as non-production and selections are capped at
1,200 tiles. It does not make the public OSM tile service suitable for a
released offline-download feature.

Download behavior:

- Bounds-to-XYZ enumeration supports zooms 0-20 at the core layer; UI exposes
  zooms 8-17.
- Estimate uses 32 KiB per tile and is clearly approximate.
- Four concurrent workers download with 15-second timeout and up to three
  attempts.
- Responses require HTTP 200, non-empty content, and an image content type.
- Files are written to `.part` and atomically renamed.
- Progress and tile references are persisted.
- Interrupted downloads recover as paused.
- Saved areas open on the primary Map destination centered on their bounds.
- The primary preview shows the bounding box and offers bounds/zoom editing.
- Editing reconciles tile references, removes files no longer referenced, and
  redownloads the revised plan without changing the area identity.
- Offline mode is always available for finding downloaded areas and constrains
  focused previews to downloaded zoom levels.
- Actual bytes and tile counts are displayed.

Limitations:

- No available-device-space preflight.
- Pause waits for current requests to return before final paused state.
- No remove-all, orphan reconciliation, checksum, ETag, or provider key UI.
- Download execution is process-local rather than an OS background job.

## 8. Platform configuration

### Android

- Application ID: `com.bernoulli.trailrunner.trail_runner`.
- Label: `RunTiyul`.
- Launcher icon: generated from the repository's `RunTiyul.png` source image.
- Java/Kotlin target: 17.
- Fine, coarse, background location, foreground service, foreground location
  service, notification, wake-lock, and internet permissions are declared.
- Release signing still uses the debug key and is not production-ready.

### iOS

- Display name: `RunTiyul`.
- When-in-use and always/background location descriptions are present.
- Location background mode is enabled.
- iOS has not been built or run in this Windows environment.

## 9. Automated validation

Validation on 2026-07-14 with Flutter 3.44.6 stable:

| Command | Result |
| --- | --- |
| `flutter pub get` | Passed; restored the launcher-icon generator dependency. |
| `dart run flutter_launcher_icons` | Passed; generated Android and iOS launcher icons from `RunTiyul.png` with alpha removed for iOS. |
| `dart format lib test` | Passed; source formatted. |
| `flutter analyze` | Passed; no issues found. |
| All three Flutter test files | Passed. |
| `flutter build apk --debug` | Passed; produced `build/app/outputs/flutter-apk/app-debug.apk`. |
| Branding metadata and iOS AppIcon manifest check | Passed; Android label and iOS display name are `RunTiyul`, all referenced iOS icon files exist, and iOS icons are alpha-free. |

Automated coverage includes:

- Tile enumeration, uniqueness, estimate, and safety limit.
- Distance, pace, duration, and byte formatting.
- Valid and empty GPX parsing.
- Activity GPX export serialization and parse round-trip.
- SQLite route/point persistence and cascade deletion.
- Route rename/duplicate persistence.
- Interrupted offline download recovery.
- Primary navigation destinations and selection.
- Map control actions, source menu states, and source-choice persistence.
- Disabled offline zoom-bound controls and safe bounds-edit reconciliation.

## 10. Android emulator verification

Target:

- Android emulator `emulator-5554`
- Android 14, API 34, x86_64

Verified on 2026-07-14:

- App install, startup, and five-destination navigation.
- Online map and OpenStreetMap attribution.
- Zoom, fit/reset, and current-location controls rendered on the primary map.
- Auto/Online/Offline source menu rendered with Offline always selectable.
- Route-list selection opened the trail on the primary Map tab with all
  controls; all three saved trails intersecting the viewport rendered.
- Saved offline area selection opened the primary Map tab with its bounding box
  and edit action.
- Offline zoom 12-15 preview disabled zoom-out at 12 and zoom-in at 15.
- Manual route name/waypoints/save and SQLite persistence after restart.
- Route library, detail map, selection, and Record handoff.
- Android location permission prompt.
- Recording timer, pause stability, finish, and activity history.
- At least one GPS sample persisted with 5-meter reported accuracy.
- Offline manager tile counts, statuses, actual byte usage, and estimates.
- Network-disabled process restart without Flutter exceptions.
- Completed-area primary-map preview visibly rendered local tiles in Offline
  mode.
- No `FATAL EXCEPTION`, `E/flutter`, or unhandled Flutter exception in the
  inspected runtime logs.

Not verified:

- GPX native picker and save workflows.
- Sequential emulator GPS distance/elevation changes.
- Physical-device background/screen-lock recording.
- iOS.
- Production provider credentials or licensing.
- Download deletion with two intentionally overlapping areas.

## 11. Immediate next priorities

1. Complete the MapLibre + client-extraction spike and select an auditable
   PMTiles source, optional terrain source, style assets, and range-capable host.
2. Verify Android and iOS background recording on physical devices.
3. Add route progress, off-route detection, and optional alerts.
4. Add device free-space checks and orphaned tile reconciliation.
5. Add database migration tests before changing schema version.
6. Configure production package identity and release signing.
