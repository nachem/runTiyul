# Implemented Details and Current Status

Snapshot date: 2026-07-17<br>
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
rasterized to PNG on the device and rendered by the existing raster layer. The
render theme extends the package's OSM Liberty style with trail/path emphasis
and mountain-peak labels for running use, and rewrites every place, road, water,
and POI label to English (preferring `name:en`, then `name:latin`, then
`name_en`, then the local `name`) so downloaded maps read in Latin script
regardless of region. Topography is implemented in two deliberately separate
ways: **CyclOSM** is an online raster base layer whose provider tiles already
contain terrain cartography, while converted-vector offline areas fetch free
Terrarium elevation only during conversion and bake pure-Dart contour lines,
elevation labels, and hillshade into their final PNG tiles. There is no runtime
terrain overlay, browsing elevation cache, or retained raw elevation package.
A native MapLibre renderer, source manifest, build pipeline, and production
hosting remain proposals only.

## 2. Verified feature matrix

| Product area | State | Evidence and limitations |
| --- | --- | --- |
| Flutter Android project | Implemented and emulator verified | Debug APK built and launched on Android 14 API 34. |
| Flutter iOS project | Configured, not runtime verified | Location descriptions and background location mode exist; no macOS/Xcode validation was available. |
| Material application shell | Implemented | Five primary destinations use Material 3 `NavigationBar`. |
| Online map display | Implemented; base-layer switch analyzer/test only | `flutter_map` tile layer, pan/zoom, provider configuration, and source-accurate attribution: a custom provider is no longer credited to OpenStreetMap, and offline previews credit each area's persisted provider. The base-layer picker offers configured **Streets**, **CyclOSM** (cycle/topographic raster with provider-baked contours/hillshade), and online-only **Esri World Imagery** satellite/orthophoto. The choice persists in `app_settings`. Viewing CyclOSM fetches only CyclOSM raster tiles, never separate elevation/Terrarium data; satellite remains view-only. |
| Map camera controls | Implemented; primary map emulator verified, other surfaces analyzer/test only | Zoom in/out, fit content, fresh-GPS recenter, and a show/hide toggle for the saved trail overlays now appear on every map surface (primary, route detail, manual editor, activity detail, and recording). The primary, route-detail, and activity-detail maps auto-fit their content when opened. A map opened without primary content or an explicit center (for example the primary Explore view or a free-run recording) instead opens centered on the runner's current location at a neighborhood zoom (`z15`), fetching a fix if none is cached and falling back to a wide region only when no location is available. |
| Map source choice | Implemented; auto layering analyzer/test only | Auto now draws the saved (offline) map as a base with the live online map layered on top, so connected users get the freshest, most detailed tiles and fall back to the saved map where there is no connectivity; Online bypasses files; Offline makes no network requests, is always selectable, and fits/displays downloaded-area bounds for discovery. Choice persists in `app_settings`. |
| Offline zoom limits | Implemented; overzoom analyzer/test only | Offline mode now uses the same zoom range as the online map: zoom-out is no longer locked at the downloaded minimum, and zooming in past the downloaded maximum scales (overzooms) the deepest saved tiles up to z19 instead of going blank. Where the current offline area lacks coverage (below the downloaded minimum), tiles render transparent in pure Offline mode; Auto fills them from the online layer. Auto-fit and the **Show on map** preview floor the camera at the downloaded minimum zoom (`offlineAwareFitZoom`), so previewing an area downloaded only at deep zoom levels no longer lands on a blank (gray) map below its coverage. Previewing an area that is still downloading now uses a download-progress-independent map key (`offlineAreaMapKey`), so the per-tile `updatedAt` bump no longer recreates the whole map and its controls on every downloaded tile (which had left the preview a flickering gray screen with no controls). |
| Current GPS location | Implemented, emulator permission verified | Location service and map marker exist; denied/settings flows are surfaced as errors but not comprehensively device-tested. |
| GPX import | Implemented, parser unit-tested | Uses the platform `file_selector`; the native picker was not exercised in the emulator verification. |
| Manual route creation | Implemented; move/delete + save-fix + edit + follow-trails analyzer/test only | Map taps add ordered waypoints; undo, name, save, and dashed straight-line display work. A new route opens centered on the runner's current location at a closer zoom. While editing, the map no longer auto-refits when points are added or moved, so the zoom the runner set is kept. The name field is pre-filled with "Route N" and required in the editor: Save is disabled and an inline "Enter a route name" prompt shows while the field is empty (the store-level save still auto-names an empty name as a safety net). The editor closes only after a successful save, so a drawn route always lands in the list. Long-pressing selects the nearest waypoint (highlighted) to move (tap to reposition) or delete. An existing route can be reopened for editing from its detail screen (Edit waypoints), loading its points to add/move/delete and saving in place. A **Follow trails** mode (toggled beside Checkpoints) loads the real trail network for the visible area and snaps each tap onto a trail *line*, then builds the route *along* real trails between anchors — the same trail's own geometry when two anchors share a trail, or a shortest path through junctions across connected trails; trail data auto-downloads for the viewed area (with a Reload action) and anchors can be undone or deleted. Switching between Checkpoints and Follow trails keeps the points already placed — anchors become free waypoints and free waypoints are snapped back onto the network — so toggling the mode changes only how the next point is added rather than resetting the route. |
| Route library/detail/management | Implemented | Routes persist in SQLite; detail, rename, edit-waypoints, duplicate, and delete actions are exposed. Rename/duplicate persistence is unit-tested. |
| Route map integration | Implemented; primary-map path emulator verified, dashed style/auto-fit analyzer/test only | All saved trails in/partly in the viewport render by default as dashed lines (map convention); tapping a route opens the primary Map tab, emphasizes it with the full controls, and fits the whole selected trail in view. |
| Route-editor and long-route performance | Implemented; analyzer/unit-tested, physical-device stress test pending | `RTE-003` Follow trails no longer derives its workload from a zoomed-out viewport: the first tap loads a bounded 3x3 z14 neighborhood around the tapped point, subsequent nearby areas merge into the graph, and explicit viewport reloads cap at 24 tiles centered on the screen instead of truncating from the northwest corner. A distant tap whose bounded neighborhood cannot overlap the preceding point is rejected immediately with an add-a-closer-point message. A closer tap is committed only when a connected, reasonable graph path exists, so Follow trails never silently inserts a straight waypoint leg. Existing anchors keep their stable graph indices; only the newest leg is routed, graph construction is lazy, and cross-trail shortest paths use a binary-heap frontier. Under `RTE-009`, saved/navigation geometry remains lossless while `TrailMap` reduces only its rendered point list at approximately one screen pixel for the current zoom. Very long routes still require profiling on a mid-range physical device. |
| Route progress/off-route alerts | Not implemented | Version 1 currently provides visual line-following only. |
| GPS activity tracking | Implemented and emulator verified | Start, permission request, pause, resume, finish, discard, timer, and persisted samples. |
| Live metrics | Implemented | Elapsed time, distance, average pace, and smoothed-threshold elevation gain are shown. Moving time is not calculated separately. |
| Background recording | Configured, not physical-device verified | Geolocator foreground notification/background settings and platform permissions exist. |
| Activity recovery | Implemented | Samples and summaries are written incrementally; interrupted active activities reload as paused. |
| Activity history/detail/delete | Implemented; list/detail emulator verified, detail-map controls analyzer/test only | Completed activity appears in history with summary; the detail track map now uses the full map controls and auto-fits the recorded track. |
| Activity GPX export | Implemented and serialization-tested | Activity samples export as a GPX 1.1 track through the native save dialog; the native dialog was not emulator-tested. |
| Offline area selection | Implemented; adjustable cap + source picker analyzer/test only | Two map corners and a zoom range; the panel shows live tile/storage/time estimates, adjustable 1.2k/2.5k/5k/10k caps, and confirmation. The first setting is an always-visible two-choice picker: **MBTiles / vector** or **Current map: _layer_**. Current-map raster follows the layer selected with the map-layer button. Debug public Streets/CyclOSM are immediately enabled and labeled `DEV`. Release starts locked; seven taps on the disabled public current-map chip within four seconds opens an explicit warning/confirmation, then persists `public_raster_dev_downloads_unlocked=true` on that device. Satellite stays view-only and cannot be unlocked. The chosen `sourceFormat` and provider id persist per area for correct resume/render/delete. |
| Offline map download | Implemented and emulator verified | Four bounded workers, timeout, transient retry, progress persistence, pause/cancel, and resume. |
| Background map downloads | Implemented (Android); analyzer/test/build pass, not device-verified | An Android foreground service (`DownloadService`, `dataSync` type) started over a `trail_runner/download_service` MethodChannel keeps the process alive while any download runs, so downloads continue with the app backgrounded; the download loop stays on the Flutter main isolate. On every platform, a download interrupted while backgrounded auto-resumes when the app returns to the foreground (`AppStore.resumeInterruptedDownloads`, wired to `AppLifecycleState.resumed`) and keeps completed tiles; iOS has no keep-alive service and relies on this resume. Service start/stop toggling and interrupted-resume are unit-tested, `flutter analyze` is clean, and the debug APK builds with the native service; on-device background behavior remains unverified. |
| Provider policy gate | Implemented | Raster authorization is independent from vector availability. Approved custom raster providers require `TRAIL_TILE_OFFLINE_ALLOWED=true`; public OSM standard and CyclOSM downloads are immediate only in debug (`ENABLE_DEV_OSM_DOWNLOADS`, default true). `ALLOW_PUBLIC_RASTER_DEV_UNLOCK` defaults true in this repository, so release includes the seven-tap developer capability but starts locked until the warning is confirmed; the unlock persists locally and promotes only OSM/CyclOSM, never Satellite/arbitrary providers. A future production build can compile it out with `ALLOW_PUBLIC_RASTER_DEV_UNLOCK=false`. DEV selections stay capped/labeled and remain non-production. |
| On-device vector→raster conversion | Implemented; analyzer/unit-tested, not device-verified | The app defaults to the free **OpenFreeMap** OpenMapTiles vector endpoint (`https://tiles.openfreemap.org/planet`), overridable in-app or via `TRAIL_VECTOR_MBTILES`. Each selected vector tile is rasterized with `vector_tile_renderer`; tiles above the source maximum (typically z14) use crisp parent over-rendering through z16, then map display pixel-overzooms to z19. `TerrariumVectorTerrainBaker` fetches elevation only during this conversion: no terrain request below z10, z10-z13 fetched directly, and deeper output crops/reuses the z13 parent from a 64-entry in-memory rendered-overlay cache. `TerrainContourService` traces 10 m contours (50 m labeled index contours) and hillshade, which are composited into the final PNG. Raw Terrarium and intermediate overlay bytes are never written to disk. Missing terrain (404) leaves the base vector tile usable; other terrain failures fail the conversion for retry. Vector source, overzoom, terrain composition/parent reuse, provider-format metadata, and PNG output are unit-tested. Visual quality/performance still need a device. |
| Trail-aware navigation | Implemented; analyzer/unit-tested, live behavior not device-verified | Saving a manual route optionally snaps it onto nearby real trails: the route is saved and listed immediately, then in the background the app fetches only the route's vector tiles, extracts the `transportation` network — trails (`path`, `track`) plus roads of any kind (`motorway`, `trunk`, `primary`, `secondary`, `tertiary`, `minor`, `service`; residential, unclassified, and living-street ways fall under `minor`) — and stitches the route to it (snapping joins a trail or road within 25 m and then stays on it with hysteresis until the route is more than 50 m away, so it does not flick on and off sparse ways), then a second pass rebuilds the stitched line as a path that follows the connected trail/road graph end-to-end (`RouteTrailBuilder.refineOntoNetwork` via `TrailRouter`), keeping the saved route entirely on real ways and bridging any stretch that left the network; a per-save toggle keeps the exact drawn line, and the saved route is only rewritten when snapping actually moves it (never to a degenerate under-two-point line), so a route is never lost or silently reshaped when no nearby trail exists. The same extraction feeds an interactive trail graph (`TrailRouter`, which snaps a tap onto the nearest trail *line* — or, when the tap is near both a trail and a road, onto the same category (trail vs road) as the previous waypoint so a route stays on one kind of way — and finds shortest paths along trails, capping an unreasonably long cross-trail detour with a straight bridge so a short crossing is never swapped for a long loop) and a viewport loader (`networkForBounds`) that power the editor's Follow-trails mode, so tapping to follow can route along roads as well as trails. While recording along a selected route, off-route and junction alerts fire with haptic feedback and a banner; distance, persistence (GPS fixes), and on/off are configurable (Record → Alerts). Junctions come from the trail network built along the route. Geometry, extraction, snapping, the route-trail builder, and the alert monitor are unit-tested; live GPS/haptic behavior needs a device. |
| Offline tile rendering | Implemented and offline verified | File-backed tiles are preferred; saved areas open on the primary Map tab with bounds, offline-only tiles, controls, and an edit-bounds action. Saved tiles render through `OrderedOfflineTileProvider`: for each tile it returns the tile from the top-most (user-ordered) area whose bounds and zoom cover it, so overlapping areas layer with the top area drawn over the ones beneath. Focused selections and other saved-area bounds keep their colored border strokes but use fully transparent polygon fills, so overlapping boxes never tint or obscure the map. Base-map tiles are stored per download format (`offlineTileNamespace` → `<provider>-vec`/`<provider>-ras`) so converted-vector and OSM-raster areas at the same coordinate no longer collide. |
| Render theme (trail emphasis) | Implemented; analyzer/unit-tested, not device-verified | On-device tiles are rasterized with a theme (`map_render_theme.dart`) that extends the package's built-in OSM Liberty OpenMapTiles style with two appended overlay groups: bold, high-contrast, dashed paths/tracks/footways with a light casing whose widths stay legible under overzoom, and mountain-peak name labels the base style omits. `preferEnglishLabels` rewrites every name-only `text-field` (place, road, water, POI, and peak) to the expression `coalesce(name:en, name:latin, name_en, name)`, so downloaded maps show English (Latin-script) labels where the OpenMapTiles data has them and fall back to the local name otherwise (never blank); road `{ref}` shields and other non-name tokens are left untouched. This applies to downloaded/offline tiles only — the online raster base map's labels are baked by the tile provider and stay in the local language. Rendering uses no remote sprites or glyphs, so it stays fully offline. |
| Topographic data handling | Implemented; analyzer/unit-tested, not device-verified | Online/raster maps never fetch separate height data: CyclOSM's topography is baked by its provider, while other raster maps remain unchanged. Only converted-vector offline maps call the Terrarium baker described above, and only the final composited PNG counts toward area storage. The old live contour overlay, `TerrainTileCache`, raw per-area terrain downloader, map toggle, and Elevation-data card were removed. A one-time `legacy_terrain_cleanup_v1` migration deletes old `aws-terrarium` DB references/files, the `aws-terrarium-cache` directory, and obsolete settings without deleting offline areas or final map tiles. Converted areas credit both their basemap and Terrain Tiles source. |
| Offline storage usage | Implemented | Actual file byte totals are persisted and shown per area and in aggregate. Each area card shows source and format chips and a Details popup listing source, format, zoom range, tiles, size, bounds, created/updated dates, and any last error. |
| Overlap-safe deletion | Implemented | Shared tile references prevent removal while another area references a tile. |
| Offline area ordering | Implemented; analyzer/unit-tested | The saved-areas list is drag-to-reorder (`ReorderableListView` with a drag handle); the order persists in `app_settings` (`offline_area_order`) and is restored on reload. Index 0 is the top area, which the ordered renderer draws over lower areas where they overlap. Reorder persistence and ordered tile resolution are unit-tested. |
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
|   |-- download_foreground_service.dart  Keep-alive service for background downloads
|   |-- gpx_service.dart            GPX route import and activity export
|   |-- location_service.dart       Permission and position stream adapter
|   |-- map_provider.dart           Compile-time provider configuration
|   |-- map_render_theme.dart       Trail-emphasis + peak-label render theme
|   |-- navigation_monitor.dart     Off-route and junction alert logic
|   |-- terrain_contour_service.dart  Terrarium decode + contour/hillshade renderer
|   |-- route_snapper.dart          Snaps a route onto nearby trails (hysteresis)
|   |-- route_trail_builder.dart    Route/viewport trail-network builder
|   |-- trail_extractor.dart        Extracts trail and road lines from vector tiles
|   |-- trail_network.dart          Trails, nearest, and junction detection
|   |-- trail_router.dart           Trail graph + shortest path (follow mode)
|   |-- offline_download_service.dart
|   |-- tile_store.dart             Deterministic files and map tile provider
|   |-- vector_area_conversion_service.dart  On-device vector-to-raster area conversion
|   |-- vector_terrain_baker.dart   Bake-time Terrarium fetch + PNG composition
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
offline_tiles/<provider-id>-<format>/<zoom>/<x>/<y>.png
```

The `<format>` suffix (`vec` for converted vector, `ras` for raster) keeps
different-format areas from overwriting each other at the same coordinate while
still deduplicating tiles that share a provider and format. It is produced by
`offlineTileNamespace` and used by both downloaders and the ordered renderer.

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
available. A focused area fits its bounds, but offline mode shares the online
map's zoom range: zoom-out is not locked at the downloaded minimum, and zoom-in
overzooms the deepest saved tiles past the downloaded maximum up to z19 (only
zoom-in disables, at z19). Areas below the downloaded minimum render transparent
in pure Offline mode; Auto fills them from the online layer. The selected mode is
stored in `app_settings` and restored after restart.

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
development display. CyclOSM is also available online and carries its own
attribution; its raster tiles already contain topographic cartography, so no
separate elevation request occurs while viewing it.

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

Small public-raster downloads are enabled by default in **debug builds only**.
`ENABLE_DEV_OSM_DOWNLOADS` defaults to true in debug and is forced off by
`kDebugMode` in profile/release; set it false to test the production gate:

```powershell
flutter run -d emulator-5554 `
  --dart-define=ENABLE_DEV_OSM_DOWNLOADS=false
```

The debug gate exposes OSM standard and CyclOSM as `DEV` raster choices with a
compact warning. Selections remain capped; this does not make either public tile
service suitable for a released offline-download feature.

Download behavior:

- Bounds-to-XYZ enumeration supports zooms 0-20 at the core layer; UI exposes
  zooms 8-17.
- Estimate uses 32 KiB per tile and is clearly approximate.
- Four concurrent workers download with 15-second timeout and up to three
  attempts.
- Responses require HTTP 200, non-empty content, and an image content type.
- Files are written to `.part` and atomically renamed.
- Progress and tile references are persisted.
- Each raster area's provider id is persisted and resolved on resume; provider
  plus format namespaces prevent OSM/CyclOSM/vector tile collisions.
- Interrupted downloads recover as paused.
- Saved areas open on the primary Map destination centered on their bounds.
- The primary preview shows the bounding box and offers bounds/zoom editing.
- Editing reconciles tile references, removes files no longer referenced, and
  redownloads the revised plan without changing the area identity.
- Offline mode is always available for finding downloaded areas and constrains
  focused previews to downloaded zoom levels.
- Actual bytes and tile counts are displayed.
- With `TRAIL_VECTOR_MBTILES` set, the same area workflow instead reads vector
  tiles from a local/downloaded MBTiles or HTTP vector source, rasterizes each
  to PNG, and bakes Terrarium-derived topography into the final image; the area
  records its `source_format`, and the offline manager shows a **Topographic
  vector** chip. No raw elevation tile is retained.

Limitations:

- No available-device-space preflight.
- Pause waits for current requests to return before final paused state.
- No remove-all, orphan reconciliation, checksum, ETag, or provider key UI.
- Download execution is process-local rather than an OS background job.

## 8. Platform configuration

### Android

- Application ID: `com.bernoulli.trailrunner.trail_runner`.
- Label: `RunTiyul`.
- Launcher icon: generated from the tightly framed, square,
  aspect-preserving `assets/branding/app_icon.png` derivative of the
  repository's `RunTiyul.png` source image. Transparent source margins are
  cropped before fitting so the artwork remains prominent on the launcher.
  Android 8+ uses a full-size adaptive foreground over a branded blue
  background rather than allowing launchers to wrap the legacy bitmap in a
  white compatibility plate.
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

Latest validation on 2026-07-17 with Flutter 3.44.6 stable:

| Command | Result |
| --- | --- |
| Dart formatter on changed Dart files | Passed. |
| `flutter analyze` | Passed; no issues found. |
| `flutter test` | Passed; 126 tests. |
| `flutter build apk --debug` | Passed; produced `build/app/outputs/flutter-apk/app-debug.apk`. |

Automated coverage includes:

- Bounded point-local and centered capped viewport trail tile selection.
- Strict connected trail routing, distant-leg rejection, lazy graph creation,
  and zoom-aware rendering-only polyline simplification.
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
- Offline preview polygons remain present but use fully transparent fills.
- Map provider OpenStreetMap-standard detection for attribution accuracy.
- CyclOSM URL/attribution/debug policy, per-area CyclOSM download routing, and
  separation of vector authorization from raster authorization.
- Release developer-unlock capability default, locked-chip tap routing,
  persisted unlock across reload, compile-out behavior, and exclusion of
  Satellite from the promoted provider set.
- On-device vector-to-raster rasterization to a valid PNG, MBTiles source reads
  (TMS flip and gzip), conversion into the tile store, and skipping of
  missing/out-of-range tiles.
- HTTP/TileJSON vector source resolution and per-tile fetch (null on 404 or
  beyond the source max zoom).
- In-app vector source setting persists, enables offline downloads, and selects
  the on-device conversion path.
- Default configuration selects the OpenFreeMap vector source and allows
  downloads.
- Bake-time Terrarium composition, no requests below z10, z13 parent reuse for
  deeper tiles, missing-terrain fallback, converted provider-format metadata,
  and one-time cleanup of legacy raw terrain/cache storage.
- Nearest-point-on-polyline projection; trail extraction from a synthetic
  OpenMapTiles tile (class filter including roads, and lat/lng order); trail-network nearest and
  junction queries; and route-to-trail snapping.
- Route-trail builder tile coverage, empty-source handling, and on-network
  graph refinement (bridging an off-network gap along connected ways);
  navigation
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
- On-device topographic vector conversion: rasterizer, MBTiles/HTTP sources,
  terrain baker, and conversion service are unit-tested, but not exercised
  against real regional data on a device; visual fidelity (labels, contours,
  hillshade), speed, memory, and battery remain unverified. Native MapLibre
  rendering remains unimplemented.

## 11. Immediate next priorities

1. Verify topographic vector-to-raster conversion on a device with real
  regional data: CyclOSM visual comparison, contour labels/hillshade, z13
  overzoom, conversion speed, memory, battery, and final storage size.
2. Verify Android and iOS background recording on physical devices.
3. Add route progress, off-route detection, and optional alerts.
4. Add device free-space checks and orphaned tile reconciliation.
5. Add database migration tests before changing schema version.
6. Configure production package identity and release signing.
