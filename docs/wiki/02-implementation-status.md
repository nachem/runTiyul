# Implemented Details and Current Status

Snapshot date: 2026-09-22<br>
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
background recording have not been verified. Monotonic route-progress guidance
and forward-only mapped-way recovery are implemented; visual progress percentage
is not. Recording-map position following and north-up/course-up are implemented,
but camera behavior, tone, voice, heading quality, and locked-screen behavior
have not been verified on a physical device.

A long-term offline-map architecture is documented in
`06-offline-map-packages.md`. An on-device vector-to-raster conversion slice is
now implemented (see the feature matrix): free vector MBTiles tiles are
rasterized to PNG on the device and rendered by the existing raster layer. The
render theme extends the package's OSM Liberty style with trail/path emphasis
and mountain-peak labels for running use, and rewrites every place, road, water,
and POI label to English (preferring `name:en`, then `name:latin`, then
`name_en`, then the local `name`) so downloaded maps read in Latin script
regardless of region. Topography is implemented in two deliberately separate
ways: **OpenTopoMap** is a view-only online raster base layer whose provider
tiles already contain terrain cartography, while converted-vector offline areas fetch free
Terrarium elevation only during conversion and bake pure-Dart contour lines,
elevation labels, and hillshade into their final PNG tiles. There is no runtime
terrain overlay, browsing elevation cache, or retained raw elevation package.
A native MapLibre renderer, source manifest, build pipeline, and production
hosting remain proposals only.

## 2. Verified feature matrix

### 2026-09-22 center-view control separation (v1.4.3 preparation)

- **MAP-008:** the existing center-focus icon now invokes a distinct center-only
  action, labeled **Center view (keep zoom)**. It moves to the bounds center of
  the route, track, checkpoints, selection, and known location while preserving
  live zoom and rotation. Empty content leaves the camera unchanged.
- **Fit route and content (adjust zoom)** is a separate `zoom_out_map` action.
  Explicit Fit and automatic route/area previews retain the existing fitting
  behavior; GPS recenter remains zoom-preserving. Both toolbar actions cancel
  any delayed startup camera placement.
- Before the change, widget tests reproduced center-view changing z17.25 to
  z15 for a single location and z16 for a route. The new implementation passes
  both cases, including course-up orientation. Tests also cover selected-area
  centering, independent control callbacks, explicit and automatic route fit,
  and empty-content startup races.

Validation on 2026-09-22: all 28 focused map/control tests passed; the full
VS Code runner reported 312 passes after release-gate cleanup. Full formatting
checked 101 files without changes and full analysis passed. The first hosted
attempt exposed prior committed download-editor/test changes in `c55f53c`:
an empty test file and an unused local blocked validation. Release preparation
removed only those blockers, preserving that committed download behavior.
The corrected snapshot must pass hosted CI before tagging. No physical-device
validation or public v1.4.3 artifact verification has occurred yet.

### 2026-09-22 recenter zoom regression (released in v1.4.2)

- **MAP-008:** reproduced a remaining v1.4.1 race in `TrailMap`: the recenter
  callback preserved zoom, but an older startup `_locateAndCenter` request
  could finish afterward and force z15. Only map gestures set the interaction
  guard; toolbar zoom and recenter did not. A delayed-GPS widget regression
  failed with expected z17.25, actual z15 before the fix.
- Toolbar zoom now cancels pending initial camera placement immediately.
  Recenter does the same before awaiting its GPS fix and still uses the latest
  live zoom when that fix arrives. It therefore also preserves zoom adjustments
  made while the request is pending. Untouched startup neighborhood centering
  remains unchanged.
- The earlier course-up/recenter test zoomed from z14 to z15, accidentally
  matching the reset value. It now uses z16.25 to z17.25. Five added cases cover
  both startup/recenter response orders, each zoom button independently, and
  untouched startup, using deferred fixes and real store-driven map rebuilds
  in Offline mode.

Validation on 2026-09-22: all 13 tests in
`test/features/routes/route_map_regression_test.dart` passed; the full VS Code
Flutter runner reported 305 passed. Changed Dart files were formatted and
`flutter analyze --no-pub lib/features/map/trail_map.dart
test/features/routes/route_map_regression_test.dart` passed. Full-project
`flutter analyze --no-pub` reported an unrelated `unused_local_variable` warning
for `active` in the concurrently edited offline-download screen; that user edit
was left intact and excluded from the release, along with an unrelated local
test deletion. `flutter devices` listed only Windows and web targets.

The committed hotfix `11c83fc` subsequently passed full hosted formatting,
analysis, tests, and CodeQL, then published as [v1.4.2+12](releases/v1.4.2.md).
Both platform builds and independent public artifact verification passed.
The v1.4.1 tag remains unchanged; no physical-device smoke test or installation
was performed for this correction.

### 2026-09-22 battery-saver GPS and camera hardening

- **ACT-004:** sample jump validation now scales its plausible distance with
  elapsed fix time. A realistic delayed fix is accepted rather than compared
  against a fixed 200 m ceiling; after a five-minute outage, recording starts a
  new zero-distance segment instead of rejecting every later fix against the
  stale anchor or inventing distance across the gap.
- **ACT-007:** a location-stream error stops the timer, persists the activity as
  paused, and reports an explicit GPS error instead of leaving the UI in a false
  recording state. Android continues to request the geolocator foreground
  notification and partial wake lock while its stream is active.
- **NAV-005/MAP-008:** Running direction keeps using a quality-filtered moving
  course and normalized course-up rotation. Only a one-finger drag disables
  Follow position; pinch/double-tap zoom and rotation retain Follow. Tracking
  updates and fresh-GPS recenter both preserve the live camera zoom, so manual
  map scale remains effective.

Validation: all **282** tests passed in the full VS Code Flutter test runner and
`flutter analyze --no-pub` passed with no issues. Focused tests covered delayed
fixes through SQLite persistence, long-gap segmentation, stream-error pause,
course-up rotation, pan-only Follow cancellation, and zoom-preserving recenter.
No physical-device Battery Saver/background or outdoor motion test was
performed.

### 2026-09-06 routing and editing hardening

- **MAP-013:** the polyline toolbar button toggles an independent vector-way
  overlay on every `TrailMap`. Trails are dashed teal, roads blue, and explicitly
  restricted ways gray. Geometry comes from the same extractor used by matching;
  it is not reconstructed from raster images. The overlay hides below z14,
  simplifies rendered lines, debounces for 300 ms, caps each viewport at 24 z14
  tiles, and allows only one active request plus the latest queued viewport.
  Missing/loading/offline-cache states are explicit; source attribution is added.
- **RTE-011:** a regression reproduced false connections between separate ways
  about two metres apart, caused by the old six-metre node grid. Nodes now use
  0.01 m coordinate-rounding precision and grade metadata. Bridge/tunnel interiors
  do not connect to ground-level crossings; coincident feature endpoints can
  connect at structure transitions. Available `foot=no/private` and access
  restrictions are excluded from routing; motorway/trunk default to excluded
  unless explicit foot permission exists. Restricted geometry remains visible
  in the comparison overlay. Category preference only resolves near-ties.
- Whole-route matching now scores up to six nearby candidates per observation
  using connected path length and input-shape fidelity. It checks all input
  geometry against a 40 m corridor, samples routed edges for deviation, and
  rejects excessive detours rather than dropping unmatched points. A failed
  full match returns the complete original geometry; stale background matches
  cannot overwrite edits or recreate deleted routes. Same-feature anchors can
  use shorter real connected alternatives. The legacy permissive `buildRoute`
  API remains for compatibility, but matching, editor changes, and recovery use
  strict connected methods.
- **RTE-012/RTE-009:** `RouteEditorDraft` keeps the full immutable polyline and
  separate sparse controls (up to 32 automatically derived at 12 m shape
  tolerance). Only in-view, spaced controls render, capped at 40 visible markers.
  Tap a control to select it; long-press a hidden section to insert/select a
  control, then Move or Delete. In Follow trails, only the affected neighboring
  section is rerouted; an unavailable connection leaves the draft intact.
  Switching modes never adopts a partial prefix or flattens the existing line.
  Undo restores a whole prior draft, with a bounded 30-edit history. Existing
  routes default to connected editing when a vector source exists and do not
  automatically resnap the entire route on save. Full coordinates and matching
  GPX altitude/timestamps are retained on untouched sections.
- **NAV-007:** one multi-target Dijkstra search chooses the shortest mapped
  forward connection among sampled ahead candidates instead of accepting the
  first rejoin. Search starts 30 m beyond last on-route progress, samples every
  30 m for at most 3 km ahead, and caps recovery path length at 6 km. A 75-degree
  initial-heading constraint is part of search; the runner's starting segment
  cannot be traversed backward after an artificial dead-end turn. Off-route
  projections no longer advance plan progress. The displayed recovery trims as
  the runner moves, replans at most every five seconds except alert transitions,
  and includes a direction arrow, compass guidance, and distance. Missing reliable
  heading suppresses stale recovery. Pause/resume of the same in-process run
  retains navigation progress.
- **NAV-006:** recording loads a bounded 3x3 z14 neighborhood rather than an
  entire route up front, refreshing after movement of 500 m (at least 15 seconds
  between attempts). `TrailNetworkCache` stores extracted source-keyed map ways,
  not runner tracks: 48 tiles in memory, at most 256 compressed disk tiles and
  64 MiB under application support `routing_network`. Overlay/editor/matching/
  recovery share this cache. Offline mode never opens HTTP sources; cached ways
  or local MBTiles are required. This opportunistic cache is not a guaranteed
  offline routing package, can evict old coverage, and is not included in the
  offline raster-area storage totals. Raster downloads alone do not establish
  routing coverage.

Validation: all **273** tests passed in the full VS Code Flutter test runner;
`flutter analyze --no-pub` passed; `flutter build apk --debug --no-pub` succeeded.
Tests include a 1,000-point editor at 390x844 logical pixels, vector toggle and
zoom hiding, stale viewport loads, filesystem cache persistence, parallel/bridge/
restricted-way routing, matched-route rejection, stale writes, shortest-forward
recovery, and a synthetic GPS recording/pause/resume flow with network forbidden.
`adb devices -l` listed no devices. No APK installation, outdoor route comparison,
long-route phone profiling, airplane-mode device run, background test, or iOS
validation occurred. Existing `flutter_tts` Kotlin migration warning remains.
All 88 local Markdown file targets resolve, and the CRLF-aware `git diff --check`
passed after these documentation updates.

Limitations: display-vector tiles omit some road/path geometry, OSM topology,
access rules, barriers, and pedestrian direction restrictions. There is no
inferred intersection between lines without a shared vertex; conservative
failures are preferable to invented connections. Matching is bounded/local,
not a full OSM routing engine; tight switchbacks, loops, tile-boundary topology,
and large regional routes still require device/data validation. Forward recovery
is shortest within the loaded graph and sampled search, not globally optimal
or rescue-grade guidance. Restoring monotonic progress after process death
remains unverified; in-process pause/resume is tested.

### 2026-09-06 stability review

Source-level fixes, not a confirmed diagnosis of the reported phone crash:

- **MAP-011/MAP-012:** restored CyclOSM beside Streets, Topographic, and
  Satellite, retaining persisted selection and independent, cacheable requests.
  OpenTopoMap uses native tiles through z17 and display overzoom to z19.
  Download permissions remain unchanged; this review grants no provider rights.
- **OFF-005/OFF-009/STO-004:** duplicate resumes share a job; area jobs and
  destructive storage mutations serialize through one queue. Edit/delete cancels
  and drains old writes before changing metadata/files. Queued areas are labeled
  and can be paused. Four raster workers operate within the single active area;
  vector conversion remains sequential. Existing confirmed plans above 1,200
  tiles resume within the supported 10,000-tile ceiling.
- Converted-vector resume now reuses existing nonempty final PNGs, avoiding
  repeated vector/terrain work. Old styles are not automatically regenerated;
  remove all areas sharing the affected tiles and redownload to refresh them.
  Full content-integrity reconciliation remains unimplemented.
- HTTP vector sources treat only 404/out-of-range tiles as missing. Other HTTP
  failures are explicit, with 15-second per-attempt timeouts and bounded
  transient retries (three attempts, 300/600 ms backoff). Failed MBTiles
  initialization closes its SQLite handle; source-close failure becomes a failed
  conversion rather than escaping final status persistence.
- Native pictures/images are disposed after PNG encoding, including drawing
  failures. Terrain codecs/images are covered from acquisition onward; contour
  label paragraphs and per-conversion terrain caches are released. This removes
  avoidable native resource retention but does not prove device OOM is resolved.
- **RTE-005/DAT-004:** route edits update the parent row rather than SQLite
  REPLACE (which detached existing activities through `ON DELETE SET NULL`).
  Concurrent initial database reads share one open future. Schema remains v2;
  no destructive reset, downgrade, or new migration was introduced.
- Startup failures before the application store exists now show a retry screen
  instead of leaving an unhandled initialization future. The screen never
  clears local data and warns against uninstalling to troubleshoot.
- Android `DownloadService` uses `START_NOT_STICKY`, handles foreground-service
  rejection, and stops on Android 15+ data-sync timeout instead of allowing the
  OS timeout to crash the process. Real-device timeout behavior is unverified.
- Signing configuration, package identity, release version, and permanent
  certificate pin were not changed. A signature mismatch normally blocks an
  update; there is no current evidence tying the reported runtime crash to it.

Validation and device limitations are recorded in section 9. No device was
connected, and no APK was installed, app data reset, or release published.

| Product area | State | Evidence and limitations |
| --- | --- | --- |
| Flutter Android project | Implemented and emulator verified | Debug APK built and launched on Android 14 API 34. |
| Flutter iOS project | Configured, not runtime verified | Location descriptions and background location mode exist; no macOS/Xcode validation was available. |
| Material application shell (`APP-001`, `APP-007`) | Implemented; unit/widget-tested | Five primary destinations use Material 3 `NavigationBar`. `PrimaryDestinationHistory` records destination transitions; system Back returns through pushed screens and destination history, while only root Map allows app exit. |
| Installed-version awareness (`APP-006`) | Implemented; analyzer/unit/widget-tested | `package_info_plus` supplies package-derived version/build metadata. About exposes the installed version, and `AppStore` persists `last_acknowledged_app_version`: a first tracked install is quiet, while a later build produces one local update dialog and is acknowledged after dismissal. No network request is involved. A real two-APK upgrade remains device-unverified. |
| Online map display | Implemented; restored picker analyzer/test only | Independent Streets, CyclOSM, Topographic (OpenTopoMap), and Satellite choices persist in `app_settings`. There is no per-tile fallback between providers. Topographic is view-only by default, overzooms native z17 through z19, and never requests separate terrain. Existing raster policy gates remain. No device verification for this revision. |
| Map camera controls | Implemented; primary map emulator verified, other surfaces analyzer/test only | Zoom in/out, fit content, zoom-preserving fresh-GPS recenter, and a show/hide toggle for the saved trail overlays now appear on every map surface (primary, route detail, manual editor, activity detail, and recording). Route detail and manual editor bodies reserve the device bottom safe area, so their action panels are not covered by edge-to-edge system navigation. The primary, route-detail, and activity-detail maps auto-fit their content when opened. A map opened without primary content or an explicit center (for example the primary Explore view or a free-run recording) instead opens centered on the runner's current location at a neighborhood zoom (`z15`), fetching a fix if none is cached and falling back to a wide region only when no location is available. |
| Map source choice | Implemented; auto layering analyzer/test only | Auto now draws the saved (offline) map as a base with the live online map layered on top, so connected users get the freshest, most detailed tiles and fall back to the saved map where there is no connectivity; Online bypasses files; Offline makes no network requests, is always selectable, and fits/displays downloaded-area bounds for discovery. Explicit source choices persist in `app_settings`; opening **Show on map** for a downloaded area switches to Offline only for that preview and restores the prior source when the preview closes instead of persisting Offline globally. |
| Offline zoom limits | Implemented; overzoom analyzer/test only | Offline mode now uses the same zoom range as the online map: zoom-out is no longer locked at the downloaded minimum, and zooming in past the downloaded maximum scales (overzooms) the deepest saved tiles up to z19 instead of going blank. Where the current offline area lacks coverage (below the downloaded minimum), tiles render transparent in pure Offline mode; Auto fills them from the online layer. Auto-fit and the **Show on map** preview floor the camera at the downloaded minimum zoom (`offlineAwareFitZoom`), so previewing an area downloaded only at deep zoom levels no longer lands on a blank (gray) map below its coverage. Previewing an area that is still downloading now uses a download-progress-independent map key (`offlineAreaMapKey`), so the per-tile `updatedAt` bump no longer recreates the whole map and its controls on every downloaded tile (which had left the preview a flickering gray screen with no controls). |
| Current GPS location | Implemented, emulator permission verified | Location service and map marker exist; denied/settings flows are surfaced as errors but not comprehensively device-tested. |
| GPX import | Implemented, parser unit-tested | Uses the platform `file_selector`; the native picker was not exercised in the emulator verification. |
| Manual route creation/editing (`RTE-003`, `RTE-012`) | Implemented; analyzer/unit/widget-tested | Sparse controls preserve full geometry, mode switching is lossless, and Move/Delete reroutes only adjacent sections in Follow trails. Failed edits preserve the draft; whole-edit Undo, direct control selection, and insertion by long-press are available. The map keeps the user's camera while editing, Save requires a name and valid geometry, and existing-route saves preserve matching GPX metadata. See routing hardening above for limits and device gaps. |
| Route library/detail/management | Implemented | Routes persist in SQLite; detail, rename, edit-waypoints, duplicate, and delete actions are exposed. Rename/duplicate persistence is unit-tested. |
| Route cleanup and whole-route matching (`RTE-010`, `RTE-011`) | Implemented; analyzer/unit/widget-tested, real GPX/device use unverified | Raw imported/manual geometry can receive bounded artifact cleanup. Connected editor geometry and matched graph paths are not cleaned afterward, avoiding accidental off-network shortcuts. Matching scores connected nearby candidates, rejects incomplete/corridor-violating routes, and preserves saved geometry on failure or stale results. Identity/source and matching GPX metadata remain intact. |
| Route map integration | Implemented; primary-map path emulator verified, dashed style/auto-fit analyzer/test only | All saved trails in/partly in the viewport render by default as dashed lines (map convention); tapping a route opens the primary Map tab, emphasizes it with the full controls, and fits the whole selected trail in view. Under `NAV-001`, realtime recording receives all saved routes for the layers toggle, while the selected navigation route is primary content and remains visible when saved overlays are hidden. |
| Route-editor and long-route performance | Implemented; analyzer/unit-tested, physical-device stress test pending | `RTE-003` Follow trails no longer derives its workload from a zoomed-out viewport: the first tap loads a bounded 3x3 z14 neighborhood around the tapped point, subsequent nearby areas merge into the graph, and explicit viewport reloads cap at 24 tiles centered on the screen instead of truncating from the northwest corner. A distant tap whose bounded neighborhood cannot overlap the preceding point is rejected immediately with an add-a-closer-point message. A closer tap is committed only when a connected, reasonable graph path exists, so Follow trails never silently inserts a straight waypoint leg. Existing anchors keep their stable graph indices; only the newest leg is routed, graph construction is lazy, and cross-trail shortest paths use a binary-heap frontier. Under `RTE-009`, saved/navigation geometry remains lossless while `TrailMap` reduces only its rendered point list at approximately one screen pixel for the current zoom. Very long routes still require profiling on a mid-range physical device. |
| Route progress/off-route alerts (`NAV-002`, `NAV-004`) | Partially implemented; analyzer/unit/widget-tested, live audio not device-verified | While recording a selected route, progress is the monotonic maximum nearest projection along the route; configurable distance (0.5-5 km) or elapsed-time (5-60 minute) intervals trigger completed/remaining guidance only while on route. Sustained off-route state stores the nearest route point, distance, compass bearing, and runner-relative direction when GPS heading exists. Guidance repeats every configurable 10-60 seconds and compares distance with the previous cue: two slow warning cues mean approaching the route, while three fast cues mean moving away; the banner and voice state where the route lies. Junction uses one rising cue and progress uses two relaxed rising cues. The persisted output mode defaults to **Tone + voice** and also offers **Voice**, **Tones**, and **Haptics only**; all four cue types can be previewed with unsaved settings. Voice uses an installed offline English system voice and matching tone-pattern fallback. Completed cues explicitly release transient audio focus; iOS deactivates its shared session with `notifyOthersOnDeactivation`, and a generation guard prevents an older cue from releasing a newer alert's audio. Visual route-progress percentage remains unimplemented. Physical-device heading quality, audibility in wind, media/silent-mode behavior and recovery, Bluetooth/open-ear routing, background/locked-screen playback, and iOS remain unverified. |
| Forward recovery and maneuver guidance (`NAV-007`-`NAV-010`) | Implemented; analyzer/unit/widget/synthetic-GPS-tested, live trail use unverified | Forward-constrained multi-target search chooses the shortest sampled connection in loaded mapped ways. Off-route progress is frozen; recovery advances with motion, shows an arrow and rejoin distance, and replans on a bounded cadence. Existing exact-angle/apex/consecutive/overshoot maneuver behavior remains. See routing hardening for search bounds and offline-data limits. |
| Recording map tracking (`NAV-005`, `MAP-008`) | Implemented; analyzer/unit/widget-tested, physical-device motion unverified | Recording exposes persisted Follow position and **North up** / **Running direction** controls. Course-up uses the same quality-filtered moving course as navigation (speed/heading accuracy, then movement-bearing fallback), updates center and rotation atomically, and falls back north until a course exists. A one-finger drag disables only Follow position; pinch/double-tap zoom and rotation retain following. Follow updates and fresh-GPS recenter preserve the current camera zoom, so manual zoom remains effective. |
| GPS activity tracking (`ACT-004`, `ACT-007`) | Implemented and emulator verified; Battery Saver device run pending | Start, permission request, pause, resume, finish, discard, timer, and persisted samples. Android uses a foreground location notification with a partial wake lock. Sample jump filtering now scales its plausibility window with elapsed fix time, accepts realistic delayed movement, and starts a zero-distance segment after a five-minute outage instead of rejecting all later positions against a stale anchor. A location-stream error persists a paused activity and shows an explicit GPS error rather than continuing to display recording. |
| Live metrics | Implemented | Elapsed time, distance, average pace, and smoothed-threshold elevation gain are shown. Moving time is not calculated separately. |
| Background recording | Configured, not physical-device verified | Geolocator foreground notification/background settings and platform permissions exist. |
| Activity recovery | Implemented | Samples and summaries are written incrementally; interrupted active activities reload as paused. |
| Activity history/detail/delete | Implemented; list/detail emulator verified, detail-map controls analyzer/test only | Completed activity appears in history with summary; the detail track map now uses the full map controls and auto-fits the recorded track. |
| Activity GPX export | Implemented and serialization-tested | Activity samples export as a GPX 1.1 track through the native save dialog; the native dialog was not emulator-tested. |
| Offline area selection | Implemented; adjustable cap + source picker analyzer/test only | Two map corners and a zoom range; the panel shows live tile/storage/time estimates, adjustable 1.2k/2.5k/5k/10k caps, and confirmation. The first setting is an always-visible two-choice picker: **MBTiles / vector** or **Current map: _layer_**. Current-map raster follows the layer selected with the map-layer button. Debug public Streets/CyclOSM are immediately enabled and labeled `DEV`. Release starts locked; seven taps on an eligible disabled current-map chip within four seconds opens an explicit warning/confirmation, then persists `public_raster_dev_downloads_unlocked=true` on that device. Topographic/Satellite remain view-only in ordinary builds and become eligible only in a special build compiled with `ALLOW_AUTHORIZED_VIEW_RASTER_DEV_DOWNLOADS=true`, which represents separate provider permission. The chosen `sourceFormat` and provider id persist per area for correct resume/render/delete. |
| Offline map download | Implemented; raster pacing analyzer/unit-tested, not device-verified | Provider-specific worker limits, request spacing, batch breaks, shared persisted `Retry-After` cooldowns, bounded transient retry, interruptible waits, progress persistence, and resume. Development raster uses one worker; approved-provider defaults allow four. See the 2026-09-22 hardening details below. Earlier basic download behavior was emulator-verified. |
| Background map downloads | Implemented (Android); analyzer/test/build pass, not device-verified | An Android foreground service (`DownloadService`, `dataSync` type) started over a `trail_runner/download_service` MethodChannel keeps the process alive while any download runs, so downloads continue with the app backgrounded; the download loop stays on the Flutter main isolate. On every platform, a download interrupted while backgrounded auto-resumes when the app returns to the foreground (`AppStore.resumeInterruptedDownloads`, wired to `AppLifecycleState.resumed`) and keeps completed tiles; iOS has no keep-alive service and relies on this resume. Service start/stop toggling and interrupted-resume are unit-tested, `flutter analyze` is clean, and the debug APK builds with the native service; on-device background behavior remains unverified. |
| Provider policy gate | Implemented | Raster authorization is independent from vector availability. Approved custom raster providers require `TRAIL_TILE_OFFLINE_ALLOWED=true`; public OSM standard and CyclOSM downloads are immediate only in debug (`ENABLE_DEV_OSM_DOWNLOADS`, default true). `ALLOW_PUBLIC_RASTER_DEV_UNLOCK` defaults true in this repository, so release includes the seven-tap developer capability but starts locked until the warning is confirmed. Topographic/Satellite promotion additionally requires the explicit `ALLOW_AUTHORIZED_VIEW_RASTER_DEV_DOWNLOADS=true` build flag, disabled by default and intended only for a separately authorized internal build. The persisted unlock promotes only providers eligible under the compiled capabilities; arbitrary providers remain excluded. DEV selections stay capped/labeled and remain non-production. |
| On-device vector→raster conversion | Implemented; analyzer/unit-tested, not device-verified | The app defaults to the free **OpenFreeMap** OpenMapTiles vector endpoint (`https://tiles.openfreemap.org/planet`), overridable in-app or via `TRAIL_VECTOR_MBTILES`. Each selected vector tile is rasterized with `vector_tile_renderer`; tiles above the source maximum (typically z14) use crisp parent over-rendering through z16, then map display pixel-overzooms to z19. `TerrariumVectorTerrainBaker` fetches elevation only during this conversion: no terrain request below z10, z10-z13 fetched directly, and deeper output crops/reuses the z13 parent from a 64-entry in-memory rendered-overlay cache. `TerrainContourService` traces 10 m contours (50 m labeled index contours) and hillshade, which are composited into the final PNG. Raw Terrarium and intermediate overlay bytes are never written to disk. Missing terrain (404) leaves the base vector tile usable; other terrain failures fail the conversion for retry. Vector source, overzoom, terrain composition/parent reuse, provider-format metadata, and PNG output are unit-tested. Visual quality/performance still need a device. |
| Trail network and comparison overlay | Implemented; analyzer/unit/widget-tested | `TrailExtractor` retains transportation geometry, grade, and available foot/access policy; strict routing excludes prohibited ways. `RouteTrailBuilder` and `TrailNetworkCache` share bounded source-keyed data for matching, sparse editing, the z14+ overlay, and local recording recovery. Raster downloads do not establish routing coverage. Display-vector topology/access omissions remain explicit limitations. |
| Offline tile rendering | Implemented and offline verified | File-backed tiles are preferred; saved areas open on the primary Map tab with bounds, offline-only tiles, controls, and an edit-bounds action. Saved tiles render through `OrderedOfflineTileProvider`: for each tile it returns the tile from the top-most (user-ordered) area whose bounds and zoom cover it, so overlapping areas layer with the top area drawn over the ones beneath. Focused selections and other saved-area bounds keep their colored border strokes but use fully transparent polygon fills, so overlapping boxes never tint or obscure the map. Base-map tiles are stored per download format (`offlineTileNamespace` → `<provider>-vec`/`<provider>-ras`) so converted-vector and OSM-raster areas at the same coordinate no longer collide. |
| Render theme (trail emphasis) | Implemented; analyzer/unit-tested, not device-verified | On-device tiles are rasterized with a theme (`map_render_theme.dart`) that extends the package's built-in OSM Liberty OpenMapTiles style with two appended overlay groups: bold, high-contrast, dashed paths/tracks/footways with a light casing whose widths stay legible under overzoom, and mountain-peak name labels the base style omits. `preferEnglishLabels` rewrites every name-only `text-field` (place, road, water, POI, and peak) to the expression `coalesce(name:en, name:latin, name_en, name)`, so downloaded maps show English (Latin-script) labels where the OpenMapTiles data has them and fall back to the local name otherwise (never blank); road `{ref}` shields and other non-name tokens are left untouched. This applies to downloaded/offline tiles only — the online raster base map's labels are baked by the tile provider and stay in the local language. Rendering uses no remote sprites or glyphs, so it stays fully offline. |
| Topographic data handling | Implemented; analyzer/unit-tested, not device-verified | Online/raster maps never fetch separate height data: OpenTopoMap's topography is baked by its provider, while other raster maps remain unchanged. Only converted-vector offline maps call the Terrarium baker described above, and only the final composited PNG counts toward area storage. Baked hillshade and contour strokes are deliberately subdued, and z13 parent overlays fade progressively when enlarged at z14-z16 so terrain does not overpower roads, labels, or route overlays. The old live contour overlay, `TerrainTileCache`, raw per-area terrain downloader, map toggle, and Elevation-data card were removed. A one-time `legacy_terrain_cleanup_v1` migration deletes old `aws-terrarium` DB references/files, the `aws-terrarium-cache` directory, and obsolete settings without deleting offline areas or final map tiles. Converted areas credit both their basemap and Terrain Tiles source. On 2026-09-04, the changed files were formatted, `flutter analyze --no-pub` passed, and all 175 tests passed. Existing downloaded tiles must be redownloaded to receive the new baked appearance. |
| Offline storage usage | Implemented | Actual file byte totals are persisted and shown per area and in aggregate. Each area card shows source and format chips and a Details popup listing source, format, zoom range, tiles, size, bounds, created/updated dates, and any last error. |
| Overlap-safe deletion | Implemented | Shared tile references prevent removal while another area references a tile. |
| Offline area ordering | Implemented; analyzer/unit-tested | The saved-areas list is drag-to-reorder (`ReorderableListView` with a drag handle); the order persists in `app_settings` (`offline_area_order`) and is restored on reload. Index 0 is the top area, which the ordered renderer draws over lower areas where they overlap. Reorder persistence and ordered tile resolution are unit-tested. |
| Download crash recovery | Implemented and unit-tested | Areas left `downloading` after restart become `paused` and resumable. |
| Free-space check/orphan cleanup | Not implemented | The app does not yet show available device bytes or reconcile orphaned files. |
| Product documentation | Implemented | Requirements, architecture, AI instructions, local debugging, current status, privacy, security, support, and contribution expectations are documented and linked from the README. |
| Open-source project health | Implemented; hosted push CI verified | The repository has a Code of Conduct with a usable confidential contact, `SECURITY.md`, `PRIVACY.md`, `CONTRIBUTING.md`, `SUPPORT.md`, CODEOWNERS, structured bug/feature forms, a pull-request template, weekly Dependabot coverage, and pull-request CI for format/analyze/test plus dependency review. External Actions are SHA-pinned, checkout credentials are not persisted, and release builds pin Flutter 3.44.6 and are configured to publish checksums plus GitHub provenance attestations. GitHub private vulnerability reporting, Dependabot alerts/security updates, secret scanning, and secret push protection are enabled. Push CI and Pages passed for commit `87290ca`; PR dependency review and release provenance remain unexercised. No branch protection/ruleset or published release SBOM exists. |

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
|   |-- about/                      Installed-version and update dialogs
|   |-- activities/                 History and detail UI
|   |-- map/                        Shared map and main map UI
|   |-- offline_maps/               Area selection, management, preview
|   |-- recording/                  Live activity UI
|   `-- routes/                     Library, detail, and manual editor
|-- models/                         Route, activity, and offline area entities
|-- services/
|   |-- app_version_service.dart    Package-derived version/build metadata
|   |-- download_foreground_service.dart  Keep-alive service for background downloads
|   |-- gpx_service.dart            GPX route import and activity export
|   |-- location_service.dart       Permission and position stream adapter
|   |-- map_provider.dart           Compile-time provider configuration
|   |-- map_render_theme.dart       Trail-emphasis + peak-label render theme
|   |-- forward_route_recovery.dart Strict mapped-way reconnection ahead
|   |-- navigation_alert_feedback.dart  Haptic, CC0 tone, system-TTS, and fallback adapter
|   |-- navigation_monitor.dart     Off-route, progress, and junction alert logic
|   |-- route_geometry_cleaner.dart Mini out-and-back artifact cleanup
|   |-- route_maneuver_planner.dart Exact-angle and consecutive maneuver planning
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

Route updates preserve parent-row identity and activity links. Concurrent first
access shares a pending database open; failed opens remain retryable. Existing
v1-to-v2 migration coverage remains part of the full test suite.

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

A separate base-layer picker on every map surface selects Streets, CyclOSM,
Topographic, or Satellite. Saved tiles retain each area's provider/format;
switching the online layer does not rewrite them. Both sources are credited
when Auto overlays a different live layer. Selection persists in `app_settings`.
Topographic/Satellite remain view-only except under the separately authorized
internal-build policy described above.

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
- Conservative route-artifact cleanup and explicit whole-route snapping for
  both manual and GPX routes.
- All saved routes render on the primary map when fully or partially in view.
- Tapping a route selects it and switches to the primary map with all controls.

Limitations:

- Duplicate imports do not yet offer replace/cancel choices.
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
- Sustained off-route and upcoming-junction detection with a visual banner,
  semantic haptics (heavy warning, medium junction, light progress),
  configurable thresholds, reminder cadence, nearest-route compass/relative
  direction, and per-alert enable switches.
- Monotonic along-route progress with optional completed/remaining announcements
  at configurable distance or elapsed-time intervals while on route.
- Persisted **Tone + voice**, **Voice**, **Tones**, and **Haptics only** output
  modes, with in-settings previews for initial off-route, route-finder trend,
  progress, and left-turn junction alerts. Missing system speech falls back to
  the corresponding bundled-tone cadence.
- Two offline Kenney Interface Sounds cues bundled under CC0 1.0; system TTS
  uses an installed English voice and platform navigation audio focus.
- Explicit transient-focus release after the final cue or spoken prompt. Android
  low-latency tones are stopped after their known duration; iOS deactivates the
  shared audio session while notifying interrupted audio apps so music can
  resume. Superseded alerts cannot release a newer alert's audio ownership.
- Activity history, detail summary/map, and confirmed deletion.
- GPX 1.1 activity export through the platform save dialog.

Limitations:

- A real physical-device screen-lock/background test has not been performed.
- Emulator movement produced one persisted sample but did not emit enough
  sequential fixes to verify distance changes live.
- Moving time is not distinct from elapsed time.
- Current pace uses the full activity average, not a rolling window.
- Visual route-progress percentage is absent.
- Recording Follow position, north-up/course-up rotation, forward recovery,
  exact-angle prompts, and overshoot behavior are not physical-device verified.
- Alert tones, system voice availability, outdoor audibility, headphone routing,
  interrupted-music resumption, and background/locked-screen playback have not
  been exercised on a physical Android or iOS device.
- The native GPX save dialog was not emulator-tested.

## 7. Offline maps and provider configuration

The default map is the public OpenStreetMap standard service for interactive
development display. CyclOSM is independently available online with its own
attribution; Topographic uses OpenTopoMap. Neither browsing choice requests
separate elevation data.

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
- Raster requests have a 15-second timeout and at most three attempts. Provider
  policy controls concurrency, spacing, and batch breaks: development defaults
  use one worker, at least 500 ms between starts, and a 10-second break after
  each 20 requests; approved-provider defaults use four workers, 250 ms spacing,
  and a five-second break after each 40 requests.
- Shared provider cooldowns honor `Retry-After` and survive pause/resume and
  process restart. Pacing is included in the approximate raster time estimate;
  provider cooldowns and real network conditions can take longer.
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
- Pause immediately interrupts pacing/backoff waits and prevents new retries.
  Already-sent HTTP operations are not actively aborted; their response/timeout
  is drained before final paused state, retaining any completed tiles.
- No remove-all, orphan reconciliation, checksum, ETag, or provider key UI.
- Download execution is process-local rather than an OS background job.

### 2026-09-22 development raster-download hardening

The initial source review found unpaced workers, ignored `Retry-After`, and
retries continuing after Pause. Those raster-path gaps are now addressed in
`OfflineDownloadService` and `MapProviderConfig`, without changing provider
eligibility or the application download queue.

- **OFF-009:** `RasterDownloadPolicy` configures bounded workers, minimum
  request spacing, batch size/break, retry delays, and maximum automatic wait.
  The development defaults above apply to debug and hidden-unlock providers;
  an explicitly supplied provider policy survives developer promotion. These
  are conservative application defaults, not provider-approved quotas.
- Every HTTP attempt, including retries, passes through shared per-provider
  scheduling. HTTP 408/5xx and network failures retry at most three times,
  with one/two-second default exponential backoff. HTTP 429 applies a shared
  30-second base cooldown that doubles on repeated rate limits, capped at a
  four-minute fallback. Numeric and HTTP-date `Retry-After` can extend, never
  shorten, the deadline. Invalid/past headers use the fallback. There is no
  unnecessary sleep after the last exhausted attempt.
- Server cooldown deadlines are stored in `app_settings` under
  `raster_download_cooldown_v1:<provider-id>` and reloaded after restart, without
  a schema change. Workers recheck an extended deadline before issuing a
  request; a concurrent success does not clear an active cooldown.
- Waits up to two minutes resume automatically while the job stays active.
  Longer waits or three exhausted 429 attempts leave the area paused with a
  UTC retry deadline. Resume cannot bypass that deadline; completed local tiles
  are reused. HTTP 401/403 pauses with a permission error, rather than repeatedly
  retrying a provider refusal. Other permanent responses fail without retry.
- **OFF-005:** Pause and disposal wake pending timers immediately and stop new
  requests/retries. Requests already in flight can finish and save their tiles.
  A terminal failure also stops queued workers. Provider-paused areas are not
  automatically retried by `AppStore` on foreground; explicit Resume remains
  subject to the saved deadline.
- **OFF-003:** the existing raster time band includes the selected policy's
  spacing, batch breaks, and worker count. Cache reuse, server cooldowns, and
  real network latency can still move completion outside the estimate.
- **OFF-012:** provider-policy gates and attribution are unchanged. Pacing does
  not grant production/offline permission or guarantee against blocking.

Validation on 2026-09-22: all **305** tests passed in the full VS Code Flutter
runner, `flutter analyze --no-pub` passed with no issues, and changed Dart files
were formatted. New fake-HTTP coverage includes spacing/batch boundaries,
concurrency, numeric/date/malformed `Retry-After`, shared and extended cooldowns,
restart persistence, provider isolation, pause during waits/retries, cache reuse,
bounded transient retry, permanent errors, and foreground/manual-resume
protection. No live tile-server requests, APK build/install, device
background/download test, or iOS validation was run as part of this change.

Scope and limitations: scheduling is shared by raster download jobs in this
service, not by online interactive map browsing, vector source fetches, or
terrain conversion. Wall-clock deadlines depend on the device clock. Already
sent HTTP operations are not actively aborted. Device behavior, actual provider
limits, and production licensing still require independent verification.

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
- Text-to-speech service discovery is declared, voice prompts request navigation
  audio attributes/focus, and low-latency tone playback is explicitly stopped
  after its final cue to abandon transient focus.
- Release builds require the permanent secret-backed RSA key and fail closed
  when any signing value is absent. GitHub Actions holds four encrypted signing
  secrets; the workflow pins certificate SHA-256
  `d9f8b0d77eddcddd436d945eec37d66513f9a8f1488b5807b5bf50acf32139e5`,
  rejects non-increasing build numbers, and verifies package/version/certificate
  metadata before upload. The private key has an access-controlled local
  recovery copy outside the repository; an independent off-machine backup is
  still an operational requirement.
- `v1.2.1` (`versionCode` 6) was signed locally but its tag workflow stopped at
  metadata validation because CRLF was not normalized; no artifact or GitHub
  Release was published. `v1.2.2` (`versionCode` 7) supersedes it as the first
  publishable permanent-signing baseline. APKs through `v1.2.0` used different
  ephemeral debug certificates, so their users must uninstall once (normally
  losing local app data) before installing this baseline. On 2026-09-04, the
  protected local recovery key was validated against the installed permanent
  certificate, and a locally rebuilt `1.4.0+10` APK replaced the installed
  `1.4.0+10` app on a Pixel 10 with `pm install -r`. Android retained the
  original first-install timestamp and recorded a new update timestamp. This
  verifies same-version replacement without clearing app data; a true
  cross-version upgrade and manual inspection of retained routes, activities,
  and maps remain unverified.

### iOS

- Display name: `RunTiyul`.
- When-in-use and always/background location descriptions are present.
- Location and audio background modes are enabled. Guidance uses a shared
  playback session in `voicePrompt` mode that ducks other audio, then deactivates
  it with `notifyOthersOnDeactivation` so the interrupted app can resume.
- iOS has not been built or run in this Windows environment.

## 9. Automated validation

Latest local code and hosted `v1.4.2` release validation completed on 2026-09-22.
Earlier dated entries below remain historical evidence:

| Command | Result |
| --- | --- |
| Public `v1.4.2+12` recenter hotfix (2026-09-22) | Tagged commit `11c83fc` is pushed to `main`. CI `35745309481` passed formatting, clean analysis, and the complete committed-source test suite; CodeQL `35745308024` passed. [Release run 35745585108](https://github.com/nachem/runTiyul/actions/runs/35745585108) passed signed Android identity/build, unsigned iOS packaging, checksums, provenance, and publication. Independent APK (62,741,224 bytes) and IPA (16,035,861 bytes) downloads match public hashes, both tagged-workflow/source-commit attestations verify, and latest URLs return HTTP 200 with matching sizes. Android SDK inspection confirms the permanent certificate and `1.4.2+12`; hashes are in the [release notes](releases/v1.4.2.md). Unrelated local download edits were excluded and left untouched. No physical-device validation occurred. |
| Public `v1.4.1+11` release (2026-09-22) | Tagged commit `fcf721f` is committed and pushed to `main`. [Release run 35740728459](https://github.com/nachem/runTiyul/actions/runs/35740728459) passed metadata, permanent-signed Android build/identity, unsigned iOS packaging, checksums, provenance, and publication. Independently downloaded APK (62,741,220 bytes) and IPA (16,035,792 bytes) match both published checksums and GitHub digests. Public APK identity/signature and both tagged-workflow/source-commit attestations verify; both stable latest URLs return HTTP 200. Hashes are recorded in the [release notes](releases/v1.4.1.md). No physical-device installation, background/Battery Saver test, or iOS runtime test was performed. |
| Raster pacing and cooldown hardening (2026-09-22) | All 305 tests passed in the full VS Code Flutter runner after changed Dart files were formatted; `flutter analyze --no-pub` passed with no issues. Fake HTTP verifies shared `Retry-After`, persisted deadlines, interruptible waits, bounded retry, cache reuse, unchanged permission gates, and foreground-resume protection. No live provider requests or device validation occurred for this change. |
| Local signed `1.4.1+11` build (2026-09-22) | All 303 tests passed; the read-only Dart format check covered 102 files with no changes, and `flutter analyze --no-pub` passed. `flutter build apk --release --no-pub` succeeded; Android SDK `apksigner` and `aapt` verified the permanent certificate, application ID, and version `1.4.1+11`. The APK is 62,724,952 bytes; checksum and local path are in the [release notes](releases/v1.4.1.md). No commit/tag/push, publication, device install, or iOS build occurred. The existing `flutter_tts` Kotlin warning remains non-fatal. |
| Battery-saver GPS and map-camera hardening (2026-09-22) | All 282 tests passed in the full VS Code Flutter test runner; `flutter analyze --no-pub` passed with no issues. Focused tests covered elapsed-time-aware delayed fixes through SQLite persistence, long-gap segmentation, GPS-stream failure pausing, course-up rotation, pan-only Follow cancellation, and fresh-location recenter preserving manual zoom. No physical-device Battery Saver/background or outdoor motion test was performed. |
| Route/overlay/recovery hardening (2026-09-06) | All 273 tests passed after final formatting/style fixes. `flutter analyze --no-pub` passed with no issues; `flutter build apk --debug --no-pub` built successfully. Synthetic GPS, 390x844 dense-editor layout, actual vector-toggle/zoom hiding, cache persistence, and disconnected/grade/restricted-way regressions passed. No connected device was available. |
| Stability review (2026-09-06) | All 242 tests passed in the full VS Code Flutter runner. Changed Dart files were formatted; `flutter analyze --no-pub` passed with no issues; `flutter build apk --debug --no-pub` built successfully, including Android timeout handling and queued-download UI. The existing `flutter_tts` Kotlin-plugin migration warning remains non-fatal. `git -c core.whitespace=cr-at-eol diff --check` passed. |
| Device/signing scope (2026-09-06) | `adb devices -l` returned no connected devices. No install, in-place upgrade, live provider probe, airplane-mode check, background recording/download, native timeout reproduction, or iOS validation was performed. Release signing configuration and certificate pin were inspected and left unchanged; the debug APK is not a permanent-signed update for the installed release. |
| Dart formatter on changed Dart source/test files | Passed. |
| `flutter analyze --no-pub` | Passed; no issues found. |
| VS Code Flutter test runner (full suite) | Passed all 173 tests on 2026-09-04. |
| GitHub configuration and documentation checks | Seven YAML files parsed; checksum-verified `actionlint` 1.7.12 passed; issue-form labels and private-reporting availability were verified; all external Actions use immutable SHAs; Flutter 3.44.6, non-persisted checkout credentials, checksums, and provenance steps are present; every local Markdown file target resolves. |
| GitHub repository security settings | Authenticated API checks confirmed private vulnerability reporting, Dependabot alerts/security updates, secret scanning, and secret push protection enabled. There are zero open Dependabot alerts and zero open secret-scanning alerts; the dependency graph inventories 161 packages and can return an SPDX SBOM. No branch protection or ruleset exists. |
| GitHub Actions `Continuous integration` | Run [`35745309481`](https://github.com/nachem/runTiyul/actions/runs/35745309481) passed setup, dependency install, format, analyze, and the complete test suite for release commit `11c83fc` on 2026-09-22. The dependency-review job correctly skipped on a push and still requires pull-request verification. |
| GitHub Actions CodeQL | Run [`35745308024`](https://github.com/nachem/runTiyul/actions/runs/35745308024) passed for release commit `11c83fc` on 2026-09-22. |
| GitHub Actions `Deploy website` | Run [`30808751792`](https://github.com/nachem/runTiyul/actions/runs/30808751792) passed for commit `87290ca` on 2026-08-03. |
| `flutter build apk --debug --no-pub` | Passed for `1.4.0+10`; Android SDK inspection reports package `com.bernoulli.trailrunner.trail_runner`, `versionName=1.4.0`, `versionCode=10`, and label `RunTiyul`. The 166,344,270-byte local debug APK SHA-256 is `e4a076f89c8b6d221ce947620c58e1ae71d841dd86446f030aa158fdbcb2f4aa`. |
| Map-source regression validation (2026-09-04) | `flutter test test/persistence_test.dart test/app_shell_test.dart test/features/map/tmp_offline_preview_repro_test.dart` passed all 15 focused tests. The subsequent full VS Code Flutter test run passed all 173 tests, including restart and deletion regressions proving that downloaded-area preview does not persist Offline mode. `flutter analyze --no-pub` passed with no issues. No emulator or mobile device was connected. During diagnosis, a direct OSM Standard tile request returned HTTP 200 while the configured CyclOSM `a` endpoint returned HTTP 504; independent requests to CyclOSM `a`, `b`, and `c` endpoints returned HTTP 502, confirming a simultaneous upstream CyclOSM outage rather than loss of local map data. |
| Online-map stability validation (2026-09-04) | Live requests returned a valid image for OSM Standard, OpenTopoMap, and Esri, while CyclOSM still returned HTTP 502. Package-source inspection confirmed that `flutter_map` disables in-memory image caching whenever `fallbackUrl` is configured. The online topographic choice now requests OpenTopoMap directly and remains view-only; CyclOSM remains isolated to the explicit development raster-download path. Four focused provider/download/widget files passed all 20 tests, the full suite passed all 175 tests, and `flutter analyze --no-pub` reported no issues. A matching-signed release APK then installed in place on the Pixel 10; Android reported `lastUpdateTime=2026-09-05 01:40:40` in the phone's timezone and a 667 ms successful cold launch. Device screenshots visually confirmed Online Streets rendering and, after selection and tile settling, sharp Online Topographic contour tiles. The next 500 buffered log lines contained no `FATAL EXCEPTION` or `E/flutter`. |
| Authorized raster-debug capability (2026-09-04) | Added an opt-in `ALLOW_AUTHORIZED_VIEW_RASTER_DEV_DOWNLOADS` compile flag, disabled by default. When compiled together with the existing hidden unlock, Topographic and Satellite become eligible for bounded current-map raster downloads after seven taps and confirmation; ordinary builds keep both view-only. Focused provider, unlock, format, and picker tests passed all 18 tests; the full suite passed all 177 tests and `flutter analyze --no-pub` reported no issues. A matching-signed release APK compiled with the flag built successfully, installed in place on the Pixel 10, and launched; Android reported `lastUpdateTime=2026-09-05 01:51:19` in the phone's timezone. The phone then required biometric unlock, so the hidden UI flow and actual Topographic/Satellite downloads remain device-unverified. The user's claimed provider permission was not independently reviewed. |
| Pixel 10 signed install and launch (2026-09-04) | The current source built as a 62,118,636-byte release APK using the DPAPI-protected local recovery key. `aapt` verified package `com.bernoulli.trailrunner.trail_runner` and version `1.4.0+10`; `apksigner` verified permanent certificate SHA-256 `d9f8b0d77eddcddd436d945eec37d66513f9a8f1488b5807b5bf50acf32139e5`, matching the installed APK. After transfer, `pm install -r` returned `Success`; `firstInstallTime` remained `2026-07-22 14:13:04`, while Android reported a new `lastUpdateTime` of `2026-09-05 00:53:38` in the phone's timezone. A cold `MainActivity` launch returned `Status: ok` in 273 ms, the process remained alive, and the next 500 buffered log lines contained no fatal exception or `E/flutter`. Stored content and map rendering were not manually inspected. |
| GitHub Actions `flutter build apk --release` with protected signing | Passed for `1.4.0+10` in run `32322574702`; published a 62,118,520-byte APK. |
| Public Android SDK `apksigner verify --print-certs` and `aapt dump badging` | Passed; package `com.bernoulli.trailrunner.trail_runner`, `versionName=1.4.0`, `versionCode=10`, label `RunTiyul`, and pinned certificate SHA-256 `d9f8b0d77eddcddd436d945eec37d66513f9a8f1488b5807b5bf50acf32139e5`. APK SHA-256 is `b33d2d81a7dd30966052e210dc820fff2314774ff52e29cbc4da6e9d86e40e12`. |
| Release workflow/site/repository checks | Run `32322574702` passed metadata, Android, iOS, checksums, APK+IPA provenance, and publication; signing secrets are build-step scoped. Independent checksum, identity/certificate, provenance, and stable-link checks passed. Local wiki links and the CRLF-aware `git diff --check` passed. The current `actionlint` result is recorded above. |

Release run
[`32322574702`](https://github.com/nachem/runTiyul/actions/runs/32322574702)
published `v1.4.0+10` from commit `ecdbd0a`. Both the Android and unsigned iOS
jobs passed. Independent downloads matched `SHA256SUMS.txt`: APK
`b33d2d81a7dd30966052e210dc820fff2314774ff52e29cbc4da6e9d86e40e12`
(62,118,520 bytes) and IPA
`0fde120ff9bc435dc362eb24d0f8cb2dcc8138466cb3fcafe3ad2478a7ee721c`
(15,947,212 bytes). Both provenance attestations verified and both stable
latest-download URLs returned 200.

The first `v1.2.2` tag run (`29896550967`) built the signed Android APK and
unsigned iOS IPA, but its Android post-build gate could not parse the
certificate digest from Linux `apksigner` output. Publication remained blocked
and no release assets were created. The parser now reads combined output with a
case-insensitive field match and rejects an empty digest. Manual retry
`29896994686` passed all jobs and published both assets. Independent inspection
of the downloaded public APK confirmed package
`com.bernoulli.trailrunner.trail_runner`, `versionName=1.2.2`, `versionCode=7`,
and the pinned permanent certificate. GitHub reports public SHA-256 digests APK
`eebf3b4c24c19552365148b5fa1d578f84226d6d59d864e7abc73493c1c50a70`
and IPA
`a536a6076eee24daa2be33940a3d15da1dacbfd9e76f2fe1131d1eb50085d6a2`;
both stable latest-download URLs returned 200.

The Android build emits a forward-looking Flutter warning that `flutter_tts`
4.2.5 still applies the Kotlin Gradle plugin. It does not fail the current
build; track a plugin release that adopts Flutter's Built-in Kotlin migration.

Automated coverage includes:

- Primary-destination Back history and root-only app-exit state.
- Persisted recording Follow position and north-up/course-up controls, course
  rotation normalization, recording-map wiring, and precise recovery/maneuver
  banners.
- Bounded mini out-and-back cleanup that preserves intentional double-backs;
  whole-route manual/GPX snapping outcomes and GPX metadata preservation.
- Strict forward recovery on connected mapped ways, first-ahead-contact
  trimming, forward-cone enforcement, and rejection of backtracking,
  disconnected, and open-terrain routes.
- Exact signed 45/90/180-degree maneuver classification, intentional U-turns,
  advance/apex alert phases, 25 m overshoot grace, and consecutive instructions.
- Forward-only voice wording that never exposes a nearest-route "behind"
  direction as recovery guidance.
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
  navigation monitor off-route persistence, nearest-route bearing and relative
  direction, repeated trend cues, monotonic distance/time progress milestones,
  junction re-arm, disabled states, and snap/alert settings persistence.
- Navigation feedback mode persistence; slow/fast off-route and relaxed
  progress tone patterns; compass/relative voice phrases; completed/remaining
  guidance; speech-unavailable matching-tone fallback; valid bundled OGG
  assets; final-cue focus release; stale-alert ownership protection; four
  unsaved-setting previews; and alert-settings layout.
- Route detail/editor bottom-safe-area ownership; realtime recording route-list
  wiring; and independent visibility of the selected navigation route versus
  hideable saved-route overlays.
- Offline-area schema v1-to-v2 migration and `source_format` default.
- First-install versus changed-build detection, one-time version
  acknowledgement persistence, update-dialog content, and About version
  display.

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

First: reproduce the reported crash on the affected phone without uninstalling
or clearing data, capture targeted crash evidence, and validate these fixes with
a permanent-signed in-place update. No connected device was available during
the 2026-09-06 review. Test download cancellation/edit/delete, queue behavior,
memory under sustained conversion, and Android data-sync timeout explicitly.

1. Verify topographic vector-to-raster conversion on a device with real
  regional data: CyclOSM visual comparison, contour labels/hillshade, z13
  overzoom, conversion speed, memory, battery, and final storage size.
2. Verify Android and iOS background recording on physical devices.
3. Verify navigation tones and system voice on physical Android and iOS:
  off-route slow/fast trend cadence, compass/relative heading quality,
  junction/progress distinction, outdoor audibility, Bluetooth/open-ear
  headphones, interrupted-music resumption, background/locked-screen playback,
  and missing-language fallback.
4. Add device free-space checks and orphaned tile reconciliation.
5. Add database migration tests before changing schema version.
6. Secure an independent signing backup, then verify a data-preserving Android
  upgrade from `v1.2.2` to `v1.4.0` on a physical device.
7. Protect `main` with the now-verified CI check, verify dependency review on a
  pull request, and decide whether to publish an SBOM/dependency-license
  inventory.
