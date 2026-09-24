# Target Architecture

Status: target architecture; partially implemented by the current MVP

The MVP implements the documented domain/data boundaries, SQLite metadata,
filesystem tiles, location adapter, tile planner, provider gate, and
feature-oriented presentation directories. It currently uses one observable
`AppStore` for workflow coordination rather than separate feature controllers.
See `02-implementation-status.md` for exact evidence and remaining gaps.

## 1. Architectural objectives

The architecture must support:

- Offline-first behavior.
- Durable, recoverable activity recording.
- Replaceable map and tile providers.
- Testable GPS, clock, filesystem, network, and database boundaries.
- Bounded tile downloads with persistent progress.
- Independent evolution of route, recording, and offline map features.
- Android and iOS behavior without business logic in platform host files.

## 2. Recommended application layers

```text
Presentation
  Screens, widgets, controllers/notifiers, view state
       |
Application
  Use cases and workflow orchestration
       |
Domain
  Entities, value objects, repository contracts, metric calculations
       |
Data and platform
  SQLite, filesystem, HTTP tile client, GPS adapter, file picker
```

Rules:

- Domain code must not import Flutter widgets, SQLite, HTTP, or platform
  permission packages.
- Screens must not issue SQL, write files, or construct provider URLs.
- Repositories return explicit errors or typed results; storage failures must
  not become empty lists.
- External APIs are wrapped so unit tests can use deterministic fakes.
- Installed package metadata is read through `AppVersionService`; widgets and
  application state do not query platform package channels directly.

## 3. Recommended feature-oriented source layout

```text
lib/
|-- app/
|   |-- app.dart
|   |-- router.dart
|   `-- theme.dart
|-- core/
|   |-- errors/
|   |-- geo/
|   |-- persistence/
|   |-- time/
|   `-- units/
|-- features/
|   |-- routes/
|   |   |-- domain/
|   |   |-- application/
|   |   |-- data/
|   |   `-- presentation/
|   |-- recording/
|   |   |-- domain/
|   |   |-- application/
|   |   |-- data/
|   |   `-- presentation/
|   |-- activities/
|   |-- map/
|   `-- offline_maps/
`-- main.dart
```

Avoid a single global `services/`, `models/`, or `screens/` directory that
mixes unrelated features. Shared code belongs in `core/` only when at least two
features genuinely use the same abstraction.

## 4. State management

Riverpod is declared and is a reasonable choice for:

- Dependency injection of repositories and platform adapters.
- Async screen state.
- Long-lived recording and download controllers.
- Test overrides for GPS, clocks, HTTP, and storage.

Recommended state rules:

- Keep durable state in SQLite/files, not only in providers.
- Expose immutable UI state with explicit loading, data, and error variants.
- Controllers call application use cases rather than implementing SQL or tile
  arithmetic.
- Recording and download state machines must reject invalid transitions.
- Never use a broad catch that converts failure into a success-shaped state.

## 5. Domain model

### 5.1 Route

```text
Route
  id: RouteId
  name: String
  source: importedGpx | manual
  createdAtUtc: DateTime
  updatedAtUtc: DateTime
  distanceMeters: double
  minElevationMeters: double?
  maxElevationMeters: double?
  points: ordered RoutePoint collection
```

Summary queries should not load all route points. Store points separately with
a stable sequence.

### 5.2 Activity

```text
Activity
  id: ActivityId
  routeId: RouteId?
  state: recording | paused | completed | discarded | recoveryRequired
  startedAtUtc: DateTime
  endedAtUtc: DateTime?
  elapsedMilliseconds: int
  movingMilliseconds: int
  distanceMeters: double
  elevationGainMeters: double?
  sampleCount: int
```

`ActivitySample` stores raw sensor values and whether a sample was accepted for
metric calculations. Preserving rejected samples can support diagnostics, but
retention should be a deliberate privacy/storage decision.

### 5.3 Offline area and tile

```text
OfflineArea
  id: OfflineAreaId
  name: String
  bounds: north/east/south/west
  minZoom: int
  maxZoom: int
  providerId: String
  status: planned | downloading | paused | complete | failed | deleting
  totalTiles: int
  completedTiles: int
  failedTiles: int
  actualBytes: int
  createdAtUtc: DateTime
  updatedAtUtc: DateTime
  lastError: String?
```

```text
TileRecord
  providerId: String
  zoom: int
  x: int
  y: int
  relativePath: String
  byteCount: int
  etag: String?
  downloadedAtUtc: DateTime
```

If areas overlap, use an area-to-tile reference table or compute references
transactionally before deletion.

## 6. Persistence design

SQLite should own metadata and structured user data. Tile binary content should
live in the application support directory.

Suggested tables:

- `schema_migrations`
- `routes`
- `route_points`
- `activities`
- `activity_samples`
- `offline_areas`
- `tiles`
- `offline_area_tiles`
- `app_settings`

`app_settings.last_acknowledged_app_version` stores the package-derived
`versionName+versionCode` identity last accepted by the user. Absence means the
first tracked install and is initialized silently; a different identity means
an upgrade notice is pending until acknowledgement. This check is entirely
local and does not determine whether a newer release exists online.

Required constraints:

- Foreign keys enabled.
- Unique point/sample sequence per parent.
- Unique tile key `(provider_id, zoom, x, y)`.
- Cascade behavior explicitly selected and tested.
- Schema changes use ordered, transactional migrations.

The implemented v2 database coalesces concurrent first-open requests. Updates
to route parents use update/insert rather than SQLite REPLACE, preserving
activity foreign keys; REPLACE's implicit delete is not an update operation.

Write an activity row before starting the GPS stream. Insert samples in small
transactions as recording proceeds. Final summary updates and state transition
must be transactional.

## 7. Location and recording pipeline

```text
Platform location stream
        |
Location adapter
        |
Sample validation/filter
        |----------------------> persisted raw/diagnostic sample
        |
Accepted sample
        |
Track accumulator
  distance, pace, moving time, elevation, route progress
        |
Persist checkpoint + emit immutable recording state
```

Use injected clock and location interfaces in calculations. Avoid calculating
distance from UI frame timing.

Sample jump validation is elapsed-time aware: the short-interval allowance
still rejects GPS teleports, delayed fixes may cover realistic running distance,
and gaps of five minutes or more start a new zero-distance segment so a stale
anchor cannot cause every subsequent fix to be rejected. A location-stream
error stops the timer and durably pauses the activity before surfacing the GPS
failure.

The recording state machine should allow:

```text
idle -> acquiringFix -> recording <-> paused -> finishing -> completed
                      \-> recoverableError
recording/paused -> discarding -> discarded
```

Every transition that changes durable state must be persisted.

Navigation alert detection remains pure Dart in `NavigationMonitor`. Platform
side effects belong to `NavigationAlertFeedback`, which receives a complete
`NavStatus` and the persisted output mode. Every fired alert attempts a
semantic haptic (heavy off-route, medium junction, light progress);
the selected mode then adds a bundled tone, concise system-TTS guidance, both in
sequence, or neither. Tone + voice plays the earcon before speech so the two do
not mask each other. Voice-only mode falls back to the corresponding offline
tone when no installed English voice can speak. Playback, speech, and haptic
failures are best-effort and must never pause or fail activity recording.
After the final cue or completed utterance, the adapter must explicitly abandon
transient audio focus. On iOS it must deactivate the shared session with
`notifyOthersOnDeactivation`; alert generations prevent a superseded prompt
from releasing focus owned by its replacement.

`NavStatus` carries the nearest route point, distance, compass bearing,
runner-relative direction when a usable heading exists, distance trend since
the previous reminder, monotonic completed/remaining route distance, exact
maneuver geometry, and an optional strict forward-recovery path.
`RouteManeuverPlanner` computes signed turn angles from geometry and mapped
junctions. `NavigationMonitor` owns configurable reminder/progress milestones,
advance/apex maneuver phases, consecutive-turn grouping, and overshoot grace so
GPS jitter, widget rebuilds, and audio completion cannot re-arm them
accidentally. Off-route and maneuver events take priority over progress on the
same GPS update.

`ForwardRouteRecovery` accepts a reliable moving course and a locally loaded
recognized trail/road network. One multi-target Dijkstra search chooses the
shortest mapped path to sampled ahead contacts; the initial forward cone is a
search constraint, not a post-hoc rejection of an unconstrained shortest path.
The starting segment is split at the runner so an apparent forward start cannot
turn around and traverse back through that position. Search is bounded to 3 km
ahead in the plan (30 m samples) and 6 km of recovery path. It starts 30 m beyond
last on-route progress; off-route projections do not advance that progress.
The result trims as the runner moves and replans on a five-second cadence or
alert transition. No reliable course means no stale recovery direction.

Recording loads a bounded 3x3 z14 neighborhood and refreshes after moving 500 m,
with at least 15 seconds between network attempts. The same source-keyed cache
serves overlay, editing, matching, and navigation. Cached/local reads remain
available in Offline mode without HTTP requests. In-process pause/resume retains
navigation progress; durable progress restoration after process death remains
a separate requirement. No prompt translates a nearest-route projection behind
the runner into a backtracking instruction, and guidance is not rescue-grade.

The two bundled earcons are immutable CC0 OGG assets with source provenance and
hashes beside the files. System TTS uses installed platform voices rather than a
network service, preserving offline behavior and location privacy. Warning-tone
cadence communicates route recovery without speech: slow pairs mean approaching
the route and fast triples mean moving away. A single rising cue identifies a
maneuver; a relaxed pair identifies progress. Spoken/visual maneuver prompts
include rounded angles, intentional U-turns, advance/apex timing, and an
immediate following instruction. Off-route speech either follows the rendered
mapped recovery forward or tells the runner to remain on a recognized path
while searching ahead; it never instructs a return to the deviation point.

`TrailMap` alone owns recording camera movement. It atomically applies current
position and map rotation from a quality-filtered course, persists Follow
position and north-up/course-up choices through `AppStore`, and treats a
single-finger pan as an explicit request to stop position following without
changing orientation. Pinch/double-tap zoom and rotation retain following; all
tracking and explicit current-location recenter moves preserve the live camera
zoom so the runner controls map scale.

Manual **Center view (keep zoom)** uses the same content-point collection as
fitting but only moves to its bounds center at the live zoom, without rotating.
Empty content is a no-op. Explicit **Fit route and content (adjust zoom)** uses
the existing camera-fit rules, separately from both centering actions and from
automatic route/area previews.

Startup location centering must yield to explicit map interaction. Both map
gestures and toolbar zoom/center/fit invalidate the pending startup camera move;
recenter invalidates it before awaiting GPS. Its eventual move reads the live
zoom, retaining any further zoom adjustment made while the fix is pending.

## 8. Metric calculation boundaries

- Distance: geodesic distance between accepted sequential points.
- Elapsed time: wall duration from start excluding no period.
- Moving time: accepted moving intervals, with a documented movement threshold.
- Current pace: smoothed recent distance/time window, not one noisy speed
  sample.
- Average pace: moving time divided by accepted distance.
- Elevation gain: positive changes after accuracy checks and smoothing; missing
  altitude yields unavailable, not zero.
- Route progress: nearest plausible route segment with monotonic forward bias;
  configurable distance/time milestones fire only while on route.
- Off-route: distance to route exceeds threshold for a sustained duration and
  location accuracy is adequate.

Each calculation belongs in pure Dart and needs synthetic unit tests.

## 9. Map and tile architecture

`flutter_map` should depend on a composite tile provider:

1. Resolve the deterministic tile key.
2. Return a valid local tile when present.
3. If network use is allowed, request through the configured provider client.
4. Cache according to provider terms and application policy.
5. Return an explicit missing/error tile when unavailable.

Online rendering resolves tiles from the user's selected base layer. Saved
tiles resolve from each area's persisted provider id plus source format, so
areas from different raster providers and vector conversion can coexist.
Provider policy decides whether a layer is view-only, development-downloadable,
or production-downloadable; widgets only present those decisions.

Do not bury download policy in a widget. Define:

- `MapTileProviderConfig`
- `TileCoordinate`
- `TileStore`
- `VectorTerrainBaker` (transient Terrarium fetch/render/composite step used
  only by converted-vector offline generation; no raw elevation persistence)
- `TileClient`
- `TileDownloadPlanner`
- `TileDownloadQueue`
- `OfflineAreaRepository`
- `StorageReconciler`

### 9.1 Route editing and rendering performance

Follow-trails editing uses z14 vector data independent of camera zoom. A tap
that is outside the loaded graph fetches only the surrounding 3x3 tile
neighborhood. If that bounded neighborhood cannot connect to the preceding
point, planning retains a direct connection and reports it as unmapped. It does
not fetch an unbounded corridor between distant taps. Panning and nearby taps merge
de-duplicated networks without changing existing anchor indices. Explicit
viewport loads are capped and centered on the viewport.

The strict graph API rejects disconnected or unreasonable detours; navigation
recovery continues to use it. `TrailRouter.planWaypoints` is the planning layer:
it compares up to six nearby candidates, prefers fewer direct legs before
distance/shape cost, snaps within 40 m, and retains unsnappable points in place.
Its explicit direct fallback preserves original intermediate geometry for saved
routes and never changes graph connectivity. The shared router searches
connected alternatives even when both anchors
belong to the same feature. Coincident nodes use a 0.01 m rounding grid, not a
multi-metre proximity merge. Grade metadata separates bridge/tunnel interiors;
coincident endpoints permit structure transitions. Available pedestrian/access
restrictions exclude ways from the routing graph; motorway/trunk requires
explicit pedestrian permission. Same-level branch endpoints lying on a segment
within coordinate precision split that segment; a latitude-sorted endpoint index
and bounds filtering limit candidate checks. Anchors attach to the neighboring
split nodes. Category preference is only a 6 m near-tie breaker. Missing metadata
and tile-boundary quantization can still prevent mapped connections. Do not infer
arbitrary interior intersections solely from crossing lines.

Curved-feature candidate selection (RTE-011, workspace update 2026-09-24)
projects onto each segment and retains local distance minima along the feature,
rather than one nearest point for the whole polyline. This preserves alternate
nearby hairpin arms while excluding non-minimal dense straight vertices.
Adjacent coincident projections are deduplicated; global six/16 candidate caps
and maximum snap distances remain. This does not add graph junctions or change
grade/access policy.

The shared candidate-plan comparison keeps connectivity first (fewer wholly
direct legs, then mapped-only versus unmapped), then minimizes missed existing
snaps within 2 m, before comparing route cost. This preserves deliberate trail
or road taps instead of moving them to a nearby shorter way. Exact candidates
that cannot participate in a connected plan do not forbid useful alternatives.
The priority is used by Checkpoints, local Follow-trails edits, and matching;
strict recovery still follows its mapped graph and heading constraints.

Checkpoint planning is a separate mode of `planWaypoints` (RTE-003/RTE-011,
released in v1.4.5 on 2026-09-23), not a relaxation of strict recovery topology.
It evaluates all ordered inputs with up to 16 candidates in a 150 m radius.
Candidates within 40 m may move the checkpoint; more distant candidates keep
the input location and use explicit unmapped approach segments. A distinct input
more than 5 m from its neighbor cannot collapse into a negligible projected leg.
After the shared connectivity and near-exact-snap priorities, candidate costs
account for route length, snap distance, and unmapped distance;
fully mapped paths take priority over gap-assisted or whole-leg direct fallback.
Each previous candidate performs one multi-target search for the next set.
Mapped search bounds are 10 km minimum, eight times checkpoint separation, and
100 km maximum; checkpoint chords are not treated as recorded route geometry.

If a target has no mapped path, a separate planning adjacency may bridge an
at-most-12 m gap from a dangling endpoint to another routable way at the same
level. Direction must remain within 60 degrees of the endpoint's continuation;
reciprocal continuation is checked when the target is also dangling. Candidates
come from a 50 m spatial segment index. Projected split nodes are linked in
segment order; gap edges carry a 25-times distance penalty and retain explicit
direct-segment indices through path reconstruction. Strict pathfinding does not
read planning adjacency. These are planning guesses, not verified topology or
permission to cross a barrier; no arbitrary intersection or grade transition is
invented by this gap heuristic.

`networkForCheckpoints` reuses source-keyed cached corridor tiles. When the
initial plan still has wholly unrouted legs it expands once from a one-tile to
two-tile ring, staying inside the 256-tile workload budget. Offline mode never
opens HTTP sources. Map gaps outside that budget retain explicit fallback rather
than forcing unbounded downloads. This cannot guarantee a globally best route
or complete access/barrier coverage from display-vector data.

`RouteEditorDraft` owns immutable full geometry plus sparse control indices.
Opening a dense route derives at most 32 controls from endpoints and significant
shape changes; those controls are not substituted for the stored track. Map
markers are viewport/spacing culled (at most 40 visible). Long-press may insert
a control without changing the line. Move/delete replaces only the span between
neighboring controls, preferring connected routing and reporting direct fallback
in Follow trails while preserving
all geometry outside the span. Mode changes do not modify geometry. Undo keeps
up to 30 complete draft states. Editor saves bypass post-routing cleanup and
whole-route auto-snap by default for existing routes, preserving matching GPX
metadata and preventing unrequested changes to untouched sections. Direct segment
indices are transient draft diagnostics carried through append, insert, local
replacement, and Undo; they are not new persisted route metadata.

For new Checkpoints routes with snapping enabled, the draft also retains the
raw checkpoint inputs separately from generated points. Edits re-plan the full
checkpoint sequence and preview it before saving; Undo restores the prior raw
inputs, geometry, and diagnostics. Inserting a control preserves the other raw
inputs. Saving sends this exact geometry with background snapping disabled.
Reopening a route keeps its full geometry but does not reconstruct raw checkpoints.
Existing dense routes are not automatically reduced to sparse checkpoint input.

The vector overlay is independent of saved-route visibility and base-layer
selection. It uses the configured `transportation` extractor, hides below z14,
debounces 300 ms, caps each load at 24 source tiles, and has one active request
plus the newest pending viewport. Stale requests stop between tiles. Rendering
simplifies a copy of each line; it never changes graph or saved route geometry.
Loading, absent source, unavailable network, and missing offline cache have
explicit states and the visible source receives attribution.

`TrailNetworkCache` keeps 48 extracted tiles in memory and at most 256 compressed
JSON tiles / 64 MiB in application support `routing_network`. Keys include a
version, source identity, extractor classes, and XYZ; source URLs are hashed in
filenames. Only map features are stored, not activity samples. Offline queries
read this cache or local MBTiles without opening HTTP sources. This bounded,
opportunistic cache is not a downloaded routing package; coverage can evict,
raster downloads do not populate it, and cache bytes are separate from raster
area accounting. A guaranteed offline routing package needs additional design.

`RouteGeometryCleaner` may prepare raw manual/imported geometry, but must not
rewrite a connected graph result or geometry opened for navigation. Whole-route
**Snap to trails** on imported GPX uses the shared candidate planner over observations sampled
at 20 m of original travel. Observed geometry must remain within 40 m of a mapped
replacement; candidate routes respect the length bound. Sparse gaps over 80 m
do not force the mapped bend to remain near the unobserved straight chord, while
dense spans retain the reverse corridor check. Unmatched observations and input
spans remain explicit direct connections; no partial prefix replaces the whole
route. Strict `matchOnNetwork` remains available for all-mapped callers. Graph
results are not cleaned afterward.
Saved manual routes instead select checkpoint routing explicitly and retain all
input points without GPX observation sampling or chord-based rejection.
The caller checks that the route is still current before persisting an async
result. Route identity/source are stable, and optional GPX metadata is retained
for points that remain within one meter.

### 9.2 Download planning

The planner converts geographic bounds and inclusive zoom levels to unique XYZ
tile coordinates. It must handle:

- Web Mercator latitude limits.
- Longitude normalization and antimeridian crossing.
- Provider zoom limits.
- Integer overflow and excessive tile count.
- Existing valid local tiles.

Estimate bytes from provider-specific historical averages when available and
label the result as an estimate.

### 9.3 Download execution

Implemented stability ownership (2026-09-06): `AppStore` serializes area jobs
and offline edit/delete mutations through one asynchronous storage queue.
Duplicate resume calls share the same completion future. Edit/delete cancels
the affected job before queueing and waits for outstanding writes to settle.
Only one area downloads at once (up to four raster workers inside it), limiting
native rendering memory and preventing overlapping areas sharing temporary
tile paths concurrently. Queued jobs are visible and cancellable. Disposal
cancels jobs and drains this queue before closing download resources.

Converted-vector resume reuses existing nonempty final PNGs; a style refresh is
explicit removal/redownload, not implicit regeneration on every resume. The
shared `renderPng` boundary owns native pictures and images through encoding,
including failure; terrain codecs and contour-label paragraphs also have
explicit ownership. HTTP vector requests distinguish missing 404s from errors,
with bounded retries and per-attempt timeouts. MBTiles initialization failure
must close the just-opened database.

- Persist the area and planned tile references before network work.
- Use bounded worker concurrency.
- Apply timeout and retry only to transient failures.
- Honor provider status codes and rate limits.
- Write each response to a temporary file, then atomically rename.
- Validate response status, content type, and non-empty bytes.
- Persist progress in batches without losing completed work.
- Cancellation stops new requests and leaves a resumable state.
- Keep the process alive during downloads with a platform foreground service
  where available (Android `dataSync` service via a MethodChannel), and resume
  downloads interrupted in the background when the app next returns to the
  foreground; the download loop stays on the main isolate and never loses
  completed tiles.
- Completion requires every required tile to be valid or explicitly reconciled.

Raster scheduling (OFF-005/OFF-009, implemented 2026-09-22) lives in
`OfflineDownloadService`, with provider-specific `RasterDownloadPolicy` values
owned by `MapProviderConfig`. Every attempt passes the same provider gate for
request spacing, periodic batch breaks, and the latest shared cooldown. Default
development requests use one worker, 500 ms spacing, and a 10-second break every
20 requests; approved-provider defaults use four workers, 250 ms spacing, and a
five-second break every 40 requests. These defaults do not confer permission.

Transient retry is bounded to three attempts. Numeric or HTTP-date
`Retry-After` extends exponential fallback deadlines; concurrent responses
cannot shorten an active deadline. Server cooldowns are serialized into the
existing `app_settings` table and loaded before resumed network work. Waits
longer than the configured automatic-wait threshold, exhausted 429 retries,
and HTTP 401/403 produce a resumable `paused` area with an explicit reason, not
an automatic foreground retry loop. Per-job cancellation wakes timers and
stops new requests; in-flight responses may finish and persist. Already-sent
HTTP requests are not actively aborted. The same policy supplies minimum pacing
time to the UI's approximate raster duration band.

This gate covers raster download jobs, not interactive map browsing or
vector/terrain source requests. Persisted deadlines use the injected wall clock;
device clock changes and real background behavior remain validation concerns.

Topographic data rules for the implemented raster renderer:

- Online and raster-offline maps never request a separate elevation source.
  The view-only OpenTopoMap layer carries its cartography in the provider tile
  itself and overzooms beyond native z17. CyclOSM remains an independent
  selectable layer. Do not configure a per-tile fallback between them, because
  it disables in-memory tile caching and delays every tile during an outage.
- Converted-vector areas may fetch Terrarium only inside the conversion
  workflow. Decode, contour/hillshade rendering, and parent-tile reuse remain
  in memory; only the final composited PNG enters `TileStore` and SQLite.
- Terrain attribution is retained alongside basemap attribution even though raw
  terrain files are discarded.

### 9.4 Long-term extraction architecture

The per-XYZ-file raster design above describes the implemented MVP. The
preferred long-term direction downloads exactly the user's selected rectangle by
range-reading tiles from a hosted, immutable PMTiles source into a local
container, renders them with native MapLibre, and offers optional terrain
(hillshade and contours) from a separate elevation source. This direction is
proposed and requires a physical-device renderer and extraction spike, an
approved data, style, and terrain license chain, and a project-controlled source
build and range-capable host before adoption.

As a first, fully-on-device step, a pure-Dart vector-to-raster conversion is now
implemented: free vector MBTiles/HTTP tiles are rasterized to PNG with
`vector_tile_renderer`, then Terrarium-derived contours and hillshade are baked
into that PNG before storage (see `02-implementation-status.md`). This
deliberately avoids the `pmtiles` package, whose protobuf 6 requirement
conflicts with the vector renderer's protobuf 3. Native MapLibre rendering
remains a longer-term direction; it must preserve the same provider-policy,
attribution, and no-unnecessary-raw-terrain-retention rules unless a future
approved architecture explicitly changes them.

The complete migration design, integrity model, supply chain, tests, and rollout
gates are in
[Long-Term Offline Map Implementation (client extraction + PMTiles)](06-offline-map-packages.md).
Until those gates pass, the current raster implementation remains authoritative
for implemented behavior.

## 10. Storage accounting and deletion

Actual usage must be derived from file sizes and reconciled metadata. Deleting
an area:

1. Marks it `deleting`.
2. Finds tiles not referenced by another area.
3. Deletes files with explicit error collection.
4. Deletes unshared tile rows and area references transactionally.
5. Deletes the area row only after successful reconciliation.
6. Refreshes actual byte totals.

A failed deletion remains visible and retryable.

## 11. Platform responsibilities

### Android

- Stable application ID, monotonically increasing `versionCode`, and the pinned
  permanent release certificate form the update identity. Release CI must fail
  before publication if any of those values drift.
- Fine/coarse location permission.
- Background location only when the supported recording design needs it.
- Foreground service and persistent notification for active background
  recording.
- TTS-service package discovery and navigation audio attributes/focus for short
  guidance prompts; bundled tones remain the offline fallback. Low-latency
  SoundPool tones require an explicit stop after their known final-cue duration
  because that backend has no playback-completion callback.
- Android 13+ notification permission where applicable.
- Scoped storage compatible GPX import/export.
- The download keep-alive service is non-sticky: after process death there is
  no native download worker to restart. Android 15+ data-sync timeout stops the
  service promptly; foreground-promotion rejection must not crash the host.

### iOS

- When-in-use location description.
- Background/always location only when recording requirements justify it.
- Location and audio background modes. Guidance uses a shared playback session,
  `voicePrompt` mode, Bluetooth routes, and duck/interruption options suitable
  for occasional navigation speech. Prompt completion deactivates the session
  with `notifyOthersOnDeactivation` so interrupted media can resume.
- File importer/exporter integration.

Permissions must be requested progressively, with platform-specific recovery
instructions.

## 12. Testing strategy

### Unit tests

- GPX parsing and malformed files.
- Geodesic distance and metric accumulation.
- GPS accuracy/jump filters.
- Route progress and off-route persistence.
- Navigation output-mode routing, off-route trend cadence, relative/compass
  voice guidance, progress milestones, matching missing-TTS tone fallback, and
  bundled-audio validation, final-cue focus release, and overlapping-alert
  ownership.
- Bounds-to-tile enumeration at zoom boundaries and antimeridian.
- Storage estimates and byte formatting.
- Download retry/cancel/resume state machines.
- Database migrations and repository behavior.

### Widget tests

- Empty/loading/error/data states.
- Permission rationale and denial recovery.
- Route import/create workflows.
- Recording controls and state transitions.
- Alert output selection; reminder/progress controls; and off-route,
  route-finder, progress, and junction preview actions.
- Download confirmation, progress, failure, and deletion.

### Integration and real-device tests

- SQLite and filesystem tile persistence.
- Airplane-mode map rendering.
- Process restart during download and recording.
- Screen lock/background GPS recording on Android and iOS.
- Physical-device tone/TTS audibility, media/silent-mode behavior,
  interrupted-media resumption, Bluetooth/open-ear routing, and locked-screen
  alert playback.
- Low-storage failure and recovery.
- GPX import/export through platform pickers.

## 13. Architecture decisions still required

Create durable decision records in this wiki when resolved:

- PMTiles basemap/terrain source, client extraction vs optional regional
  packages, native MapLibre renderer, offline style assets, local tile
  container, range-capable hosting, and the offline license chain.
- SQLite access style and migration ownership.
- Background recording plugin/service design.
- Background tile download expectations.
- Elevation smoothing.
- Error/result representation.
- App navigation package or Navigator API.
