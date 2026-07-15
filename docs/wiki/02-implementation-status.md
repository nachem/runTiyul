# Implemented Details and Current Status

Snapshot date: 2026-07-15  
Overall status: functional Flutter MVP verified on an Android 14 emulator

## 1. Executive summary

RunTiyul now provides a local-first mobile MVP with:

- Material 3 navigation for Map, Routes, Record, Activities, and Offline Maps.
- Online OpenStreetMap-compatible map display with attribution and selectable
  online base layers (streets plus an online-only satellite/orthophoto layer).
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

A long-term offline-map architecture is documented in
`06-offline-map-packages.md`. An on-device vector-to-raster conversion slice is
now implemented (see the feature matrix): free vector MBTiles tiles are
rasterized to PNG on the device and rendered by the existing raster layer. A
native MapLibre renderer, terrain layer, source manifest, build pipeline, and
production hosting remain proposals only.

## 2. Verified feature matrix

| Product area | State | Evidence and limitations |
| --- | --- | --- |
| Flutter Android project | Implemented and emulator verified | Debug APK built and launched on Android 14 API 34. |
| Flutter iOS project | Configured, not runtime verified | Location descriptions and background location mode exist; no macOS/Xcode validation was available. |
| Material application shell | Implemented | Five primary destinations use Material 3 `NavigationBar`. |
| Online map display | Implemented; base-layer switch analyzer/test only | `flutter_map` tile layer, pan/zoom, provider configuration, and source-accurate attribution: a custom provider is no longer credited to OpenStreetMap, and offline previews credit the downloaded area's provider. A base-layer picker on every map surface switches the online tiles between the configured (downloadable) provider ("Streets") and additional online-only layers — currently **Esri World Imagery** satellite/orthophoto ("Satellite") — crediting the active layer, and both sources when Auto layers imagery over the saved base. The choice persists in `app_settings`. Online-only imagery is never downloaded: offline coverage, previews, and downloads stay bound to `mapProvider`. |
| Map camera controls | Implemented; primary map emulator verified, other surfaces analyzer/test only | Zoom in/out, fit content, fresh-GPS recenter, and a show/hide toggle for the saved trail overlays now appear on every map surface (primary, route detail, manual editor, activity detail, and recording). The primary, route-detail, and activity-detail maps auto-fit their content when opened. A map opened without primary content or an explicit center (for example the primary Explore view or a free-run recording) instead opens centered on the runner's current location at a neighborhood zoom (`z15`), fetching a fix if none is cached and falling back to a wide region only when no location is available. |
| Map source choice | Implemented; auto layering analyzer/test only | Auto now draws the saved (offline) map as a base with the live online map layered on top, so connected users get the freshest, most detailed tiles and fall back to the saved map where there is no connectivity; Online bypasses files; Offline makes no network requests, is always selectable, and fits/displays downloaded-area bounds for discovery. Choice persists in `app_settings`. |
| Offline zoom limits | Implemented; overzoom analyzer/test only | Offline areas constrain zoom-out to their downloaded minimum, but zooming in past the downloaded maximum now scales (overzooms) the deepest saved tiles up to z19 instead of going blank, so the map keeps zooming; only zoom-out at the minimum is disabled. |
| Current GPS location | Implemented, emulator permission verified | Location service and map marker exist; denied/settings flows are surfaced as errors but not comprehensively device-tested. |
| GPX import | Implemented, parser unit-tested | Uses the platform `file_selector`; the native picker was not exercised in the emulator verification. |
| Manual route creation | Implemented; move/delete + save-fix + edit + follow-trails analyzer/test only | Map taps add ordered waypoints; undo, name, save, and dashed straight-line display work. A new route opens centered on the runner's current location at a closer zoom. The name field is pre-filled and no longer required (empty saves auto-name "Route N"), and the editor now closes only after a successful save, so a drawn route always lands in the list. Long-pressing selects the nearest waypoint (highlighted) to move (tap to reposition) or delete. An existing route can be reopened for editing from its detail screen (Edit waypoints), loading its points to add/move/delete and saving in place. A **Follow trails** mode (toggled beside Checkpoints) loads the real trail network for the visible area and snaps each tap onto a trail *line*, then builds the route *along* real trails between anchors — the same trail's own geometry when two anchors share a trail, or a shortest path through junctions across connected trails; trail data auto-downloads for the viewed area (with a Reload action) and anchors can be undone or deleted. |
| Route library/detail/management | Implemented | Routes persist in SQLite; detail, rename, edit-waypoints, duplicate, and delete actions are exposed. Rename/duplicate persistence is unit-tested. |
| Route map integration | Implemented; primary-map path emulator verified, dashed style/auto-fit analyzer/test only | All saved trails in/partly in the viewport render by default as dashed lines (map convention); tapping a route opens the primary Map tab, emphasizes it with the full controls, and fits the whole selected trail in view. |
| Route progress/off-route alerts | Not implemented | Version 1 currently provides visual line-following only. |
| GPS activity tracking | Implemented and emulator verified | Start, permission request, pause, resume, finish, discard, timer, and persisted samples. |
| Live metrics | Implemented | Elapsed time, distance, average pace, and smoothed-threshold elevation gain are shown. Moving time is not calculated separately. |
| Background recording | Configured, not physical-device verified | Geolocator foreground notification/background settings and platform permissions exist. |
| Activity recovery | Implemented | Samples and summaries are written incrementally; interrupted active activities reload as paused. |
| Activity history/detail/delete | Implemented; list/detail emulator verified, detail-map controls analyzer/test only | Completed activity appears in history with summary; the detail track map now uses the full map controls and auto-fits the recorded track. |
| Activity GPX export | Implemented and serialization-tested | Activity samples export as a GPX 1.1 track through the native save dialog; the native dialog was not emulator-tested. |
| Offline area selection | Implemented; adjustable cap + confirm + source picker analyzer/test only | Two map corners and a zoom range; the panel shows a live tiles / estimated storage / estimated time summary. The tile safety cap is adjustable (1.2k/2.5k/5k/10k presets, default 1,200), and starting a download opens a confirmation dialog summarizing area, zoom, tiles, storage, time, and source (with a large-download caution) before it begins. A Download source picker lists all base layers: downloadable ones (the OpenFreeMap vector provider) are selectable, and view-only layers (Esri satellite) are shown disabled with the licensing reason, so a download always targets a permitted source. |
| Offline map download | Implemented and emulator verified | Four bounded workers, timeout, transient retry, progress persistence, pause/cancel, and resume. |
| Provider policy gate | Implemented | Raster downloads require an approved provider flag or the development-only OSM override; a configured vector source (the OpenFreeMap default) also enables downloads via on-device conversion. The standard VS Code debug launch supplies the development override; profile and release remain gated. |
| On-device vector→raster conversion | Implemented; analyzer/unit-tested, not device-verified | The app defaults to the free **OpenFreeMap** OpenMapTiles vector endpoint (`https://tiles.openfreemap.org/planet`), overridable in-app (Offline maps → Download area → Set source) or via the `TRAIL_VECTOR_MBTILES` build flag. Downloading an area fetches its vector tiles per `z/x/y` from that endpoint (or reads a local/downloaded MBTiles) and rasterizes each to PNG on the device with `vector_tile_renderer`, then stores and renders them through the existing raster layer. Offline zoom past the vector maximum is supported by overzoom: vector sources are downloaded up to their z14 OpenMapTiles maximum, and zooming in past that scales (overzooms) the deepest saved tiles rather than going blank, while out-of-range/missing tiles are skipped. The rasterizer, MBTiles source (TMS/gzip), HTTP/TileJSON source, conversion, in-app setting, and default config are unit-tested. Full visual fidelity (labels, fonts, styling) still needs a real device. The `pmtiles` package was removed (protobuf 6 vs the vector renderer's protobuf 3). |
| Trail-aware navigation | Implemented; analyzer/unit-tested, live behavior not device-verified | Saving a manual route optionally snaps it onto nearby real trails: the route is saved and listed immediately, then in the background the app fetches only the route's vector tiles, extracts the `transportation` path/track network, and stitches the route to it (snapping joins a trail within 25 m and then stays on it with hysteresis until the route is more than 50 m away, so it does not flick on and off sparse trails); a per-save toggle keeps the exact drawn line, and the saved route is only rewritten when snapping actually moves it (never to a degenerate under-two-point line), so a route is never lost or silently reshaped when no nearby trail exists. The same extraction feeds an interactive trail graph (`TrailRouter`, which snaps a tap onto the nearest trail *line* and finds shortest paths along trails) and a viewport loader (`networkForBounds`) that power the editor's Follow-trails mode. While recording along a selected route, off-route and junction alerts fire with haptic feedback and a banner; distance, persistence (GPS fixes), and on/off are configurable (Record → Alerts). Junctions come from the trail network built along the route. Geometry, extraction, snapping, the route-trail builder, and the alert monitor are unit-tested; live GPS/haptic behavior needs a device. |
| Offline tile rendering | Implemented and offline verified | File-backed tiles are preferred; saved areas open on the primary Map tab with bounds, offline-only tiles, controls, and an edit-bounds action. |
| Offline storage usage | Implemented | Actual file byte totals are persisted and shown per area and in aggregate. Each area card shows source and format chips and a Details popup listing source, format, zoom range, tiles, size, bounds, created/updated dates, and any last error. |
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
|   |-- navigation_monitor.dart     Off-route and junction alert logic
|   |-- route_snapper.dart          Snaps a route onto nearby trails (hysteresis)
|   |-- route_trail_builder.dart    Route/viewport trail-network builder
|   |-- trail_extractor.dart        Extracts path/track trails from vector tiles
|   |-- trail_network.dart          Trails, nearest, and junction detection
|   |-- trail_router.dart           Trail graph + shortest path (follow mode)
|   |-- offline_download_service.dart
|   |-- tile_store.dart             Deterministic files and map tile provider
|   |-- vector_area_conversion_service.dart  On-device vector-to-raster area conversion
|   |-- vector_tile_rasterizer.dart On-device MVT-to-PNG rasterizer
|   `-- vector_tile_source.dart     MBTiles vector source and one-time downloader
`-- main.dart
```

The current `AppStore` is intentionally small enough for an MVP but combines
several workflows. Future growth should split route, recording, and download
controllers according to the target architecture.

## 4. Persistence

SQLite schema version 2 creates:

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

Schema version 2 adds a nullable `source_format` column to `offline_areas`
through an explicit `onUpgrade` migration (`ALTER TABLE ... ADD COLUMN`); rows
written before the upgrade default to `rasterTiles` when read. A migration test
creates a version-1 database and verifies the upgrade preserves existing areas.
`OfflineArea.sourceFormat` records whether an area was produced by the per-tile
raster downloader or by on-device vector-to-raster conversion.

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

A separate base-layer picker (present on every map surface) selects which online
base map is shown: the configured downloadable provider ("Streets") or an
online-only layer such as Esri World Imagery ("Satellite"). Saved/offline tiles
always come from the downloadable provider, so switching layers changes only the
online tiles and their attribution; when Auto layers a different online layer
over the saved base, both sources are credited. The chosen layer is stored in
`app_settings`, and online-only layers are never targeted by the downloader.

When the map opens without a selected route, activity, download area, or explicit
center, it centers on the runner's current location at a neighborhood zoom
(`z15`), obtaining a fix first if none is cached, and only falls back to a wide
region when no location is available. The initial auto-center does not override a
deliberate pan or zoom the user makes while the fix is being obtained.

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

On-device vector-to-raster conversion (the free offline-map option). By default
the app uses the free **OpenFreeMap** OpenMapTiles vector endpoint
(`https://tiles.openfreemap.org/planet`), so offline downloads work with no
configuration: each selected tile is fetched per `z/x/y` and rasterized to PNG
on the device. Override the source in-app (Offline maps → Download area → Set
source) or at build time with a vector TileJSON/MBTiles URL or local path:

```powershell
flutter run -d emulator-5554 `
  --dart-define=TRAIL_VECTOR_MBTILES=https://maps.example.org/region.mbtiles
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
- With `TRAIL_VECTOR_MBTILES` set, the same area workflow instead reads vector
  tiles from a local or downloaded MBTiles and rasterizes each to PNG on the
  device; the area records its `source_format` and the offline manager shows a
  converted-vector chip.

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
| All Flutter test files | Passed; 60 tests. |
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
- Map provider OpenStreetMap-standard detection for attribution accuracy.
- On-device vector-to-raster rasterization to a valid PNG, MBTiles source reads
  (TMS flip and gzip), conversion into the tile store, and skipping of
  missing/out-of-range tiles.
- HTTP/TileJSON vector source resolution and per-tile fetch (null on 404 or
  beyond the source max zoom).
- In-app vector source setting persists, enables offline downloads, and selects
  the on-device conversion path.
- Default configuration selects the OpenFreeMap vector source and allows
  downloads.
- Nearest-point-on-polyline projection; trail extraction from a synthetic
  OpenMapTiles tile (class filter and lat/lng order); trail-network nearest and
  junction queries; and route-to-trail snapping.
- Route-trail builder tile coverage and empty-source handling; navigation
  monitor off-route persistence, junction re-arm, and disabled states; and the
  snap/alert settings persistence.
- Offline-area schema v1-to-v2 migration and `source_format` default.

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
- The offline-area Details popup, the unified map controls and auto-fit on the
  activity/route/editor/recording maps, and source-accurate attribution (added
  2026-07-14; verified only by `flutter analyze` and the test suite, not on a
  device or emulator).
- On-device vector-to-raster conversion (added 2026-07-14): the rasterizer,
  MBTiles source, and conversion service are unit-tested, but not exercised
  against real regional data or on a device, so visual fidelity (labels, fonts,
  styling) is unverified. Native MapLibre rendering and terrain remain
  unimplemented.

## 11. Immediate next priorities

1. Verify the on-device vector-to-raster conversion on a device with real
   regional MBTiles data, then decide between refining it (styles, labels,
   fonts) and adding a native MapLibre renderer with terrain.
2. Verify Android and iOS background recording on physical devices.
3. Add route progress, off-route detection, and optional alerts.
4. Add device free-space checks and orphaned tile reconciliation.
5. Add database migration tests before changing schema version.
6. Configure production package identity and release signing.
