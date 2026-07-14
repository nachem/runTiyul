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

Required constraints:

- Foreign keys enabled.
- Unique point/sample sequence per parent.
- Unique tile key `(provider_id, zoom, x, y)`.
- Cascade behavior explicitly selected and tested.
- Schema changes use ordered, transactional migrations.

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

The recording state machine should allow:

```text
idle -> acquiringFix -> recording <-> paused -> finishing -> completed
                      \-> recoverableError
recording/paused -> discarding -> discarded
```

Every transition that changes durable state must be persisted.

## 8. Metric calculation boundaries

- Distance: geodesic distance between accepted sequential points.
- Elapsed time: wall duration from start excluding no period.
- Moving time: accepted moving intervals, with a documented movement threshold.
- Current pace: smoothed recent distance/time window, not one noisy speed
  sample.
- Average pace: moving time divided by accepted distance.
- Elevation gain: positive changes after accuracy checks and smoothing; missing
  altitude yields unavailable, not zero.
- Route progress: nearest plausible route segment with forward-bias and jitter
  tolerance.
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

Do not bury download policy in a widget. Define:

- `MapTileProviderConfig`
- `TileCoordinate`
- `TileStore`
- `TileClient`
- `TileDownloadPlanner`
- `TileDownloadQueue`
- `OfflineAreaRepository`
- `StorageReconciler`

### 9.1 Download planning

The planner converts geographic bounds and inclusive zoom levels to unique XYZ
tile coordinates. It must handle:

- Web Mercator latitude limits.
- Longitude normalization and antimeridian crossing.
- Provider zoom limits.
- Integer overflow and excessive tile count.
- Existing valid local tiles.

Estimate bytes from provider-specific historical averages when available and
label the result as an estimate.

### 9.2 Download execution

- Persist the area and planned tile references before network work.
- Use bounded worker concurrency.
- Apply timeout and retry only to transient failures.
- Honor provider status codes and rate limits.
- Write each response to a temporary file, then atomically rename.
- Validate response status, content type, and non-empty bytes.
- Persist progress in batches without losing completed work.
- Cancellation stops new requests and leaves a resumable state.
- Completion requires every required tile to be valid or explicitly reconciled.

### 9.3 Long-term extraction architecture

The per-XYZ-file raster design above describes the implemented MVP. The
preferred long-term direction downloads exactly the user's selected rectangle by
range-reading tiles from a hosted, immutable PMTiles source into a local
container, renders them with native MapLibre, and offers optional terrain
(hillshade and contours) from a separate elevation source. This direction is
proposed and requires a physical-device renderer and extraction spike, an
approved data, style, and terrain license chain, and a project-controlled source
build and range-capable host before adoption.

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

- Fine/coarse location permission.
- Background location only when the supported recording design needs it.
- Foreground service and persistent notification for active background
  recording.
- Android 13+ notification permission where applicable.
- Scoped storage compatible GPX import/export.

### iOS

- When-in-use location description.
- Background/always location only when recording requirements justify it.
- Location background mode and correct Core Location behavior.
- File importer/exporter integration.

Permissions must be requested progressively, with platform-specific recovery
instructions.

## 12. Testing strategy

### Unit tests

- GPX parsing and malformed files.
- Geodesic distance and metric accumulation.
- GPS accuracy/jump filters.
- Route progress and off-route persistence.
- Bounds-to-tile enumeration at zoom boundaries and antimeridian.
- Storage estimates and byte formatting.
- Download retry/cancel/resume state machines.
- Database migrations and repository behavior.

### Widget tests

- Empty/loading/error/data states.
- Permission rationale and denial recovery.
- Route import/create workflows.
- Recording controls and state transitions.
- Download confirmation, progress, failure, and deletion.

### Integration and real-device tests

- SQLite and filesystem tile persistence.
- Airplane-mode map rendering.
- Process restart during download and recording.
- Screen lock/background GPS recording on Android and iOS.
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
- Route line simplification algorithm.
- Elevation smoothing.
- Error/result representation.
- App navigation package or Navigator API.
