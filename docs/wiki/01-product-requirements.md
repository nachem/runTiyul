# Product Requirements

Status: approved product direction  
Target platforms: Android and iOS  
Product model: offline-first, local account not required for version 1

## 1. Product summary

RunTiyul is a mobile application for trail runners who need to:

- Discover or create a route before a run.
- Import routes from GPX files.
- Download a selected map area before losing connectivity.
- Follow a selected route while seeing their current position and progress.
- Record a GPS activity with useful running metrics.
- Review saved activities and control the device storage used by offline maps.

The application must remain useful in remote areas without mobile data. Core
route viewing, map rendering for downloaded areas, navigation, activity
recording, and local history must not depend on a network connection.

## 2. Goals

### 2.1 Version 1 goals

1. Provide reliable map and route access without connectivity.
2. Allow GPX import and simple manual route creation.
3. Record runs without losing data when the screen locks or connectivity drops.
4. Make offline map size and deletion understandable to non-technical users.
5. Keep personal location history on the device by default.
6. Provide clear attribution and use a map source that permits offline download.

### 2.2 Non-goals for version 1

- Social feeds, followers, comments, and leaderboards.
- Cloud account registration or cross-device synchronization.
- Training plans, coaching, or health recommendations.
- Live location sharing.
- Emergency rescue guarantees.
- Full voice-guided, turn-by-turn navigation.
- Automatic route discovery from a commercial route catalog.
- Offline pathfinding over the complete OpenStreetMap road/trail graph.
- Smartwatch applications.

These may be future features, but they must not block the offline-first core.

## 3. Users and primary scenarios

### 3.1 Primary user

A trail runner who plans in an area with connectivity, then runs in terrain
where connectivity may be slow or absent.

### 3.2 User scenarios

- Import a GPX route received from an event organizer.
- Tap map points to sketch a route and save it for later.
- Select a rectangle around a route and download map zoom levels for that area.
- Check the estimated download size before committing storage.
- Start a run, lock the phone, and continue recording GPS points.
- See position, route line, progress, distance, time, pace, and elevation gain.
- Finish the run and review its summary and recorded track.
- Find large offline areas and delete those no longer needed.

## 4. Functional requirements

Requirement IDs are stable references for issues, tests, and implementation
notes.

### 4.1 Application shell and onboarding

| ID | Requirement | Acceptance criteria |
| --- | --- | --- |
| APP-001 | The app shall use a clear mobile navigation structure for Map, Routes, Record, Activities, and Offline Maps. | Each primary area is reachable in at most two taps from the main shell. |
| APP-002 | The app shall explain why location permission is needed before requesting it. | Permission rationale distinguishes active use from background recording. |
| APP-003 | The app shall handle denied, permanently denied, and disabled-location states. | The user sees a specific recovery action; the app does not fail silently. |
| APP-004 | The app shall show OpenStreetMap data attribution on map screens. | Attribution remains visible or is available through the standard map attribution control. |
| APP-005 | The app shall expose units and key application settings. | Metric units are the version 1 default and are consistently displayed. |
| APP-006 | The app shall expose its installed version and recognize a successful app upgrade. | About shows package-derived version/build information. The first tracked install is quiet; a later build is announced once and acknowledged locally without a network request. |

### 4.2 Online and offline map

| ID | Requirement | Acceptance criteria |
| --- | --- | --- |
| MAP-001 | The app shall render an interactive slippy map with pan, pinch zoom, and rotation-safe layout. | Map interaction remains responsive on a supported mid-range device. |
| MAP-002 | The map shall show the user's current location when permission and a location fix are available. | Accuracy state is visible; absence of a fix is not represented as a real position. |
| MAP-003 | The primary map shall render all saved trail polylines that intersect the viewport and emphasize the selected trail. | Fully or partially visible saved trails render by default; the selected trail remains visually distinct. |
| MAP-004 | Downloaded tiles shall be preferred when available. | A downloaded area can be viewed in airplane mode without network requests for covered tiles. |
| MAP-005 | Missing offline coverage shall be obvious. | The UI differentiates an unavailable tile from a blank or fully loaded tile. |
| MAP-006 | The tile source shall be configurable behind an application service. | UI and domain code do not hard-code a provider URL. |
| MAP-007 | Map rendering shall keep required provider attribution. | Attribution is correct for both online and downloaded content. |
| MAP-008 | The primary map shall provide one-tap zoom, current-location centering, and fit/reset controls. | The user can zoom in/out, center on a fresh location fix, and fit current location plus route/checkpoint content without gestures. When opened without a selected route or area, the map centers on the current location at a neighborhood zoom once a fix is available. |
| MAP-009 | The user shall be able to choose Auto, Online, or Offline map rendering. | Auto prefers downloaded tiles and falls back online; Online bypasses local tiles; Offline never requests the network and is always selectable so the user can find downloaded areas. The choice survives restart. |
| MAP-010 | Offline mode shall expose saved-area bounds and use the same zoom range as the online map. | Selecting Offline fits available areas when possible; the map can zoom out below the downloaded minimum and zoom in above the downloaded maximum (zoom-in overzooms saved tiles to z19), matching the online zoom range. Areas without coverage render transparent rather than blocking the zoom control. |
| MAP-011 | The user shall be able to switch the displayed base map between the configured provider and additional online-only layers (for example satellite/orthophoto imagery). | The active layer is credited correctly and the choice survives restart; online-only imagery layers are not bulk-downloaded, and offline coverage and downloads remain bound to the downloadable provider. |
| MAP-011 | Trail and offline-area previews shall use the primary Map destination. | Selecting a trail or saved offline area switches to the main map with all controls; an offline area shows its bounds and an action to edit and redownload changed bounds. |
| MAP-012 | The app shall offer a topographic online base map without downloading separate elevation data while browsing. | CyclOSM is selectable as a credited raster base layer; its provider-rendered contours/hillshade are part of the raster tiles, and selecting or viewing it does not request Terrarium/elevation tiles. |

### 4.3 Route import, creation, and management

| ID | Requirement | Acceptance criteria |
| --- | --- | --- |
| RTE-001 | The user shall be able to import a `.gpx` file from device storage. | Valid tracks and routes are converted to the internal route model. |
| RTE-002 | GPX import shall reject or report malformed and empty files. | Errors identify the problem and do not create a corrupt route. |
| RTE-003 | The user shall be able to create a route by placing, moving, undoing, and deleting map waypoints. | The draft polyline updates immediately and can be cancelled safely. |
| RTE-004 | Version 1 manual routes may connect waypoints as straight segments. | The UI never implies that straight segments are trail-aware routing. |
| RTE-005 | The user shall be able to name, save, rename, duplicate, and delete a route. | Changes persist after process restart. |
| RTE-006 | The route library shall show distance, elevation data when available, source, and offline coverage status. | Missing elevation is labeled as unavailable rather than zero. |
| RTE-007 | The route detail screen shall fit the route on a map and expose a Start activity action. | Starting passes the selected route into recording/navigation. |
| RTE-008 | Duplicate GPX imports shall not overwrite data silently. | The app asks the user to keep both, replace, or cancel. |
| RTE-009 | Long routes shall be stored without lossy coordinate rounding that harms navigation. | A saved/imported route reloads with equivalent geometry. |

### 4.4 On-route navigation

Version 1 navigation means following a visible route line, not guaranteed
turn-by-turn instructions.

| ID | Requirement | Acceptance criteria |
| --- | --- | --- |
| NAV-001 | The recording screen shall show the selected route, recorded track, and live location. | All three use distinct visual styles. |
| NAV-002 | The app shall show progress along the selected route. | Progress does not decrease substantially due only to GPS jitter. |
| NAV-003 | The app shall detect when the runner is meaningfully off route. | Threshold and persistence avoid alerts from a single inaccurate point. |
| NAV-004 | Off-route state shall use visual and optional haptic/audio feedback. | Each alert can be disabled. The runner can choose Tone + voice, Voice, Tones, or Haptics only and preview representative off-route and junction alerts before a run. Voice remains concise status/direction guidance, falls back to a tone when no offline system voice is available, and does not claim rescue-grade accuracy. |
| NAV-005 | The app shall allow north-up and course-up presentation. | The chosen mode is obvious and can be changed during a run. |
| NAV-006 | Navigation shall operate with downloaded map data and no network. | Route, track, metrics, and covered map tiles remain available in airplane mode. |

### 4.5 GPS activity recording

| ID | Requirement | Acceptance criteria |
| --- | --- | --- |
| ACT-001 | The user shall be able to start, pause, resume, finish, and discard an activity. | Destructive discard requires confirmation. |
| ACT-002 | Recording shall capture timestamp, latitude, longitude, horizontal accuracy, altitude when available, speed when available, and heading when available. | Stored samples preserve nullable sensor values correctly. |
| ACT-003 | Live metrics shall include elapsed time, moving time, distance, current pace, average pace, and elevation gain. | Each metric has a documented calculation and handles unavailable data. |
| ACT-004 | Implausible or very inaccurate samples shall be filtered without hiding recording state. | Rejected samples do not add distance; diagnostics can explain filtering. |
| ACT-005 | Recording shall continue during screen lock/background execution when the platform permits and the user granted permission. | A real-device test demonstrates continued samples with the screen locked. |
| ACT-006 | In-progress activity data shall be checkpointed incrementally. | Force-closing after recorded samples offers recovery rather than losing the run. |
| ACT-007 | The app shall clearly indicate GPS acquisition, recording, paused, and error states. | The user is never shown "recording" when the location stream has failed unnoticed. |
| ACT-008 | The app shall prevent two simultaneous active activities. | A second start redirects to or resolves the existing activity. |
| ACT-009 | Finished activities shall persist locally with summary and track. | Activity history survives app and device restart. |
| ACT-010 | The user shall be able to delete an activity. | Deletion is confirmed and related track samples are removed transactionally. |

### 4.6 Activity history

| ID | Requirement | Acceptance criteria |
| --- | --- | --- |
| HIS-001 | Activity history shall be sorted newest first by default. | Date, duration, distance, pace, and elevation gain are shown. |
| HIS-002 | Activity details shall show the recorded track and summary. | The map fits the complete recorded track. |
| HIS-003 | Empty, loading, and storage-error states shall be explicit. | Storage errors are surfaced and are not replaced with an empty success state. |

### 4.7 Offline map download

Offline map download is a core requirement, not an optional enhancement. Version
1 keeps exact rectangular area selection. The converted-vector offline type is
topographic: Terrarium elevation is fetched only while converting the selected
area, then contours and hillshade are baked into the final PNG tiles; raw
elevation tiles are not retained. Raster offline types use only their provider's
already-rendered tiles and never request separate elevation data. See the
[offline map implementation guide](06-offline-map-packages.md).

| ID | Requirement | Acceptance criteria |
| --- | --- | --- |
| OFF-001 | The user shall be able to define a rectangular download area on the map. | Bounds can be adjusted before download and are visible on the map. |
| OFF-002 | The user shall select a minimum and maximum zoom within provider and application limits. | Invalid ranges cannot start a download. |
| OFF-003 | Before download, the app shall estimate tile count and storage size. | Estimate updates when bounds or zoom range changes. |
| OFF-004 | Large downloads shall require explicit confirmation and enforce a configurable safety limit. | Tile count, estimated size, and available storage are shown before confirmation. |
| OFF-005 | The user shall name an offline area and start, pause/cancel, retry, and resume its download. | Interrupted downloads retain completed tiles and resume missing work. |
| OFF-006 | Download progress shall show completed tiles, total tiles, percentage, and failures. | Progress is based on persisted work, not only the current process session. |
| OFF-007 | Offline map content shall use deterministic source, style, version, and package-or-tile storage keys. | Different sources and versions cannot collide; repeated downloads reuse compatible verified content. |
| OFF-008 | Download metadata shall include area bounds, zoom range, source, content format and version, status, byte count, integrity metadata, license notices, created date, updated date, and failure details. | Metadata survives restart, proves which content is installed, and reconciles with files on disk. |
| OFF-009 | Download requests shall use bounded concurrency, retry with backoff for transient failures, and honor cancellation. | The app does not launch unbounded requests or retry permanent errors forever. |
| OFF-010 | Downloads shall check available device storage and handle out-of-space errors. | Partial data remains manageable; the area is not incorrectly marked complete. |
| OFF-011 | Completed downloaded areas shall work in airplane mode. | A device test confirms map rendering at all selected zoom levels inside the bounds. |
| OFF-012 | The production tile provider shall explicitly permit bulk/offline use. | Release starts with public OSM/CyclOSM downloads locked. This repository's internal developer capability may be unlocked only by seven taps plus an explicit warning/confirmation, persists on that device, and is labeled development-only; it does not make those public services production-approved. |
| OFF-013 | Downloads should continue while the app is backgrounded where the platform permits, and interrupted downloads should resume when the app returns to the foreground. | On Android a foreground service keeps the process alive while a download runs; on any platform a download interrupted in the background resumes automatically on the next foreground and never loses completed tiles. |
| OFF-014 | Converted-vector offline maps shall include topographic contours and hillshade without retaining a parallel elevation dataset. | Terrarium tiles are requested only during vector conversion at z10-z13 (z13 is reused for deeper output), rendered in memory, composited into the final PNG, and discarded; online maps and raster offline downloads make no separate elevation requests. |

### 4.8 Offline storage management

| ID | Requirement | Acceptance criteria |
| --- | --- | --- |
| STO-001 | The offline map screen shall list all areas with status, zoom range, actual size, and updated date. | Incomplete and failed areas are distinguishable. |
| STO-002 | The app shall display total offline-map storage use and available device space when accessible. | Values are refreshed after download and deletion. |
| STO-003 | The user shall be able to delete one offline area. | Its unshared tiles and metadata are removed; errors are surfaced. |
| STO-004 | Shared tiles shall not be deleted while referenced by another area. | Reference tracking or reconciliation prevents breaking another area. |
| STO-005 | The user shall be able to remove all offline maps with confirmation. | Routes and activities remain intact. |
| STO-006 | The app shall detect and offer cleanup for orphaned or corrupt tile data. | Cleanup reports reclaimed bytes and does not delete valid referenced tiles. |
| STO-007 | Storage numbers shall come from files on disk or a reconciled index. | The UI does not present an estimate as actual usage. |

### 4.9 Data portability and privacy

| ID | Requirement | Acceptance criteria |
| --- | --- | --- |
| DAT-001 | Routes, activities, and map metadata shall be stored locally by default. | Core use requires no account and no telemetry consent. |
| DAT-002 | Location history shall not be uploaded unless a future explicit feature and consent flow is added. | Network inspection shows no activity/route upload in version 1. |
| DAT-003 | The user shall be able to export a recorded activity as GPX. | Exported coordinates and timestamps can be read by a common GPX application. |
| DAT-004 | Persistence migrations shall be versioned and tested. | Upgrading from each supported schema version preserves user data. |

## 5. Non-functional requirements

### 5.1 Reliability

- Activity samples must be persisted incrementally, not only when Finish is
  tapped.
- Database writes for an activity and its samples must preserve referential
  integrity.
- Failed tile downloads must remain retryable.
- Invalid persisted data must surface a recoverable error; it must not be
  silently replaced with empty data.
- UTC timestamps must be stored; local time is only a presentation concern.

### 5.2 Performance

- Map gestures should remain smooth while route and track layers are visible.
- Large polylines should be simplified only for rendering; original points
  remain available for storage and export.
- Tile download concurrency must be bounded and configurable.
- Lists of routes, activities, and offline areas must avoid loading every track
  point or tile record into memory for summary rows.

### 5.3 Battery and location accuracy

- Location settings must be appropriate for running rather than maximum-rate
  polling without justification.
- The recording service should adapt distance filters and update intervals
  without compromising useful track accuracy.
- The UI must show location accuracy so the user can judge poor GPS conditions.
- Metric calculations must be deterministic and unit tested with synthetic
  tracks, pauses, GPS jumps, missing altitude, and elevation noise.

### 5.4 Accessibility and usability

- Touch targets, contrast, text scaling, and screen reader labels must follow
  platform accessibility guidance.
- Recording controls must be usable with wet hands and while moving: large,
  separated, and resistant to accidental destructive taps.
- State must not be communicated by color alone.
- Download size and map coverage must be described in plain language.

### 5.5 Security and privacy

- The app requests only permissions needed for visible functionality.
- Background location is requested only when the user starts or enables
  background activity recording.
- Logs must not contain complete GPS tracks in production.
- Imported filenames and XML content must be treated as untrusted input.
- Exported files must use platform-safe sharing and scoped storage APIs.

### 5.6 Map licensing and provider policy

- OpenStreetMap contributors must be credited as required by the ODbL and tile
  provider terms.
- `https://tile.openstreetmap.org` may be suitable for light interactive
  development use under its policy, but it must not be used for production
  bulk/offline downloads.
- The public CyclOSM raster service may be used for credited interactive display,
  but public-service bulk/offline downloads are development-only, must stay
  small, and must not ship as a production download source without explicit
  permission or an approved provider arrangement.
- Production must use a provider plan that explicitly allows offline tile
  download, or infrastructure operated by the application owner.
- Additional online-only display layers (for example Esri World Imagery
  satellite/orthophoto tiles) may be offered for interactive viewing where the
  source's terms permit display with attribution. They must be credited to their
  own source and must not be bulk-downloaded or cached for offline use.
- Provider headers, API keys, rate limits, tile retention, and attribution must
  be configurable and honored.

## 6. Target data entities

The logical entities are:

- `Route`: identity, name, source, timestamps, distance, optional elevation
  summary, and ordered route points.
- `RoutePoint`: sequence, coordinate, optional altitude, and optional source
  timestamp.
- `Activity`: identity, optional route reference, state, start/end timestamps,
  summaries, and recovery metadata.
- `ActivitySample`: sequence, timestamp, coordinate, accuracy, optional
  altitude/speed/heading, and sample acceptance status.
- `OfflineArea`: identity, name, bounds, zoom range, provider, progress, status,
  byte count, dates, and last error.
- `Tile`: provider, zoom, x, y, path, byte count, validation metadata, and
  reference information.
- `AppSetting`: typed user and provider settings.

Exact storage schemas are defined by architecture and migrations, not by UI
models.

## 7. Key user journeys

### 7.1 Prepare a route for offline use

1. User imports GPX or creates a waypoint route.
2. User reviews distance and route geometry.
3. User opens offline download from the route or Offline Maps.
4. App proposes bounds around the route with padding.
5. User adjusts bounds and zoom range.
6. App displays tile count, estimated bytes, and available storage.
7. User confirms and monitors resumable download progress.
8. App verifies completion and marks the route as covered.
9. User can preview the area in offline mode.

### 7.2 Record a routed run

1. User selects a route and taps Start.
2. App obtains permission and a usable location fix.
3. App starts a recoverable activity and persists samples incrementally.
4. User sees the route, track, position, progress, and live metrics.
5. App notifies the user of a persistent off-route condition.
6. User pauses/resumes if needed, then finishes.
7. App commits summaries and opens activity details.

### 7.3 Reclaim storage

1. User opens Offline Maps.
2. App displays total actual tile use and areas sorted by size or date.
3. User selects an old area and confirms deletion.
4. App removes only tiles no other area needs.
5. Usage is reconciled and refreshed.

## 8. Version 1 release acceptance

Version 1 is not complete until all of the following are demonstrated:

- GPX import and manual route creation persist after restart.
- A selected route is visible during recording.
- A 60-minute real-device recording survives screen lock and app backgrounding.
- Forced process termination during a run offers activity recovery.
- Live and saved distance/pace calculations pass synthetic-track tests.
- A selected area downloads from an approved source and distribution endpoint
  with resume and deletion.
- The downloaded area renders in airplane mode.
- Storage reporting matches files on disk within documented filesystem
  tolerances.
- Android and iOS permission denial/recovery paths are tested.
- `flutter analyze` and all automated tests pass.
- Release builds use non-debug signing/configuration and approved provider
  credentials.
- Android releases retain one application ID and signing certificate, use a
  strictly increasing `versionCode`, and pass an in-place upgrade test without
  deleting local app data.

## 9. Open product decisions

These require an explicit product decision before their implementation is
considered final:

1. Production offline package source, style, distribution host, and licensing
  terms.
2. Maximum default tile count, download size, and zoom range.
3. Background download behavior on iOS. Android keeps the process alive with a
  foreground service during downloads; iOS currently relies on foreground
  auto-resume.
4. Exact default off-route threshold and persistence duration.
5. Elevation source and smoothing algorithm.
6. Whether manual waypoint routes remain straight-line only in version 1.
7. Supported minimum Android and iOS versions.
8. Metric-only versus user-selectable imperial units for version 1.
