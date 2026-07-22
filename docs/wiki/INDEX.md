# RunTiyul Wiki Index

Last reviewed: 2026-07-22<br>
Current milestone: MVP hardening and physical-device verification  
Overall implementation status: functional Android-verified MVP; production provider and iOS verification remain

This file is the entry point and current-status index for developers and AI
coding assistants. Read it before changing the project and update it before
completing any change that affects the wiki or project status.

## Required reading order

| Order | Document | Purpose | Update when |
| --- | --- | --- | --- |
| 1 | [Product requirements](01-product-requirements.md) | Product scope, requirement IDs, behavior, constraints, and release acceptance. | Product behavior, scope, acceptance criteria, or open product decisions change. |
| 2 | [Implementation status](02-implementation-status.md) | Dated, evidence-based inventory of code, platform configuration, tests, and gaps. | Code, dependencies, platform configuration, validation, or limitations change. |
| 3 | [Target architecture](03-target-architecture.md) | Intended modules, data entities, persistence, GPS, maps, downloads, and testing design. | Technical boundaries, schemas, algorithms, or architectural decisions change. |
| 4 | [AI assistant guide](04-ai-assistant-guide.md) | Implementation sequence, engineering rules, validation, and handoff protocol. | Agent workflow, implementation order, tooling, or known traps change. |
| 5 | [Local run and debug guide](05-local-debugging.md) | Toolchain setup, Android/iOS launch, VS Code debugging, GPS simulation, and offline verification. | Tooling, device IDs, launch commands, package IDs, or debug workflows change. |
| 6 | [Offline map implementation](06-offline-map-packages.md) | Legal offline-map design and status: implemented on-device vector→raster conversion, plus proposed native MapLibre rendering, optional terrain, migration, validation, and rollout. | Offline source, format, renderer, terrain, licensing, hosting, or implementation plan changes. |
| 7 | [Release & distribution](07-release-and-distribution.md) | Website, GitHub Pages deploy, release artifacts (APK/unsigned IPA), CI workflows, licensing, and the release runbook. | Website, release workflows, artifact names, distribution, or licensing change. |
| 8 | [Release notes](08-release-notes.md) | Per-version authored notes and the mandatory release-note contract. | A release is prepared, published, corrected, or superseded. |
| 9 | [Wiki conventions](README.md) | Source-of-truth hierarchy and general documentation maintenance rules. | Wiki governance or document organization changes. |

Repository-wide agent requirements are in
[`AGENTS.md`](../../AGENTS.md). GitHub Copilot also receives the same workflow
from its standard repository instruction file,
[`copilot-instructions.md`](../../.github/copilot-instructions.md). These
instructions are mandatory for all future agents.

## Current verified state

| Area | Status |
| --- | --- |
| Flutter Android app | Implemented; built and exercised on Android 14 emulator |
| Flutter iOS app | Configured; not built or runtime verified |
| Application navigation | Implemented with five Material 3 destinations |
| App version awareness | About displays package-derived version/build metadata; a changed build is detected from local SQLite state and announced once. Analyzer/unit/widget-tested; real two-APK upgrade remains device-unverified |
| Online map | Implemented with provider abstraction, source-accurate attribution, and a base-layer switch: streets, CyclOSM topographic/cycle raster (provider-baked contours/hillshade; no separate elevation request), and online-only Esri satellite/orthophoto; online raster labels stay in each provider's baked-in language |
| Map controls/source modes | Zoom, fit/reset, GPS recenter, show/hide saved trails, always-available Offline discovery, a persisted base-layer picker on every map surface, and auto-fit; route view/edit panels honor the bottom safe area; a content-less map opens centered on the current location at neighborhood zoom; Auto layers live online tiles on top of saved maps from any persisted provider, and offline mode shares the online zoom range (zoom-out below downloaded minimum; zoom-in overzooms to z19) |
| Trail map integration | All in-view trails render as dashed lines; route taps open the primary map with full controls and fit the whole trail; realtime recording receives all saved-route overlays, while the selected navigation route remains visible independently of the saved-trails toggle |
| GPX route import | Implemented and parser tested; native picker not emulator verified |
| GPS activity recording | Implemented; emulator permission/timer/lifecycle verified |
| Visual route navigation | Trail-follow route creation (tap real trails and roads; a new waypoint keeps the previous one's way type, trail vs road, when near both), route snapping to nearby trails and roads on save followed by a graph pass that keeps the route on connected ways and bridges gaps (toggle), and configurable live off-route/junction banners, haptics, CC0 tones, and concise system-voice guidance implemented. Tone + voice is the default; Voice, Tones, and Haptics only plus settings previews are available. Audio/background behavior is not device-verified; route progress % remains. |
| Route creation performance | Zoomed-out Follow trails taps load bounded local z14 data; distant non-overlapping taps are rejected immediately, and disconnected paths are never committed as straight legs. Nearby networks expand without re-snapping old anchors, graphs build lazily, only the newest leg is routed, shortest-path search uses a priority queue, and rendering simplifies a copy while preserving full saved geometry. Analyzer/unit-tested; long-route physical-device stress testing remains. |
| Activity history | Implemented and emulator verified |
| Activity GPX export | Implemented and serialization-tested; native save dialog unverified |
| Latest published release | `v1.2.2+7` published 2026-07-22 as the permanent Android signing baseline; Android APK and unsigned iOS IPA stable links return 200; iOS sideload/runtime remains unverified |
| Release workflow | Manual retry `29896994686` passed metadata, Android permanent-signature/identity verification, unsigned iOS build, and publication after fixing CRLF metadata and Linux certificate parsing. `v1.2.1` remains an unpublished tag with no artifacts |
| Android update compatibility | Future releases can update `v1.2.2` in place only when they retain the pinned permanent certificate and increase `versionCode`. Published builds through `v1.2.0` used incompatible ephemeral debug keys and require a one-time uninstall; the resulting local-data loss cannot be repaired retroactively |
| Offline map downloads | Implemented behind provider-policy gate. The top-level picker offers **MBTiles / vector** and **Current map: _layer_**. Debug immediately enables public Streets/CyclOSM as `DEV`; release starts locked but this repository compiles the developer capability on by default, so seven taps plus warning/confirmation permanently unlocks those two providers on that device. Satellite/arbitrary view-only layers cannot be unlocked. Provider id + format persist per area for correct resume/render/delete. Android foreground keep-alive and foreground resume remain device-unverified |
| Offline tile rendering | Main-map bounds preview/edit and downloaded zoom constraints implemented; zoom-in overzooms saved tiles past the downloaded maximum. Saved tiles use an ordered, area-aware renderer, and provider/format namespaces prevent collisions. Offline-area bounding boxes remain visible as colored outlines but have fully transparent fills, so overlapping areas do not tint the map. Preview/auto-fit floor at the downloaded minimum (`offlineAwareFitZoom`), and a progress-independent map key prevents in-progress downloads from recreating the map controls |
| Offline storage management | Implemented for per-area/total bytes and overlap-safe delete, with per-area source chips and a details popup; the saved-areas list is drag-to-reorder and the order both persists and drives which area renders on top |
| Long-term offline maps | On-device vector→raster conversion uses pure-Dart `vector_tile_renderer`, crisp parent over-rendering above source z14 through selectable z16, English-preferring labels, trail emphasis, and peak labels; native MapLibre rendering and a hosted production source remain unimplemented |
| Topographic offline maps | Implemented only for converted-vector areas: Terrarium is fetched during conversion at z10-z13, rendered in memory into labeled contours + hillshade (z13 parent reused for deeper output), and baked into the final PNG. Raw elevation and overlays are never stored; online/raster maps make no separate elevation requests. The removed runtime overlay/cache/downloader is cleaned up once on startup. Converted maps credit both sources. Not device-verified; visual quality, conversion speed, memory, battery, and storage need physical-device validation |
| Automated validation | Format/analyze pass; 141 tests pass; published `1.2.2+7` APK independently verifies with the expected package, build number, and pinned certificate; public APK/IPA digests and stable latest URLs verified |

Detailed evidence belongs in
[Implemented Details and Current Status](02-implementation-status.md).

## Current implementation priority

1. Verify topographic vector conversion with real regional data on a device:
  compare against CyclOSM, inspect contour labels/hillshade and z13 parent
  overzoom, and measure conversion speed, memory, battery, and final storage.
2. Verify CyclOSM online selection and small debug-only offline download on a
  device while confirming no separate Terrarium request occurs.
3. Verify background recording/downloads and off-route/junction tone + voice
  alerts on physical Android and iOS devices, including outdoor audibility,
  headphones, missing-language fallback, and locked-screen playback.
4. Stress-test zoomed-out and long Follow trails routes on a mid-range physical device, including memory, tap latency, and save/reload fidelity.
5. Add free-space checks, orphan cleanup, and explicit database migrations.
6. Secure an independent signing-key backup, then verify a data-preserving
  upgrade from `v1.2.2` to a later signed build on a physical Android device.

Do not implement production bulk download against the public
`tile.openstreetmap.org` standard tile service.

## Open decisions

The authoritative detail is in
[Product Requirements: Open product decisions](01-product-requirements.md#9-open-product-decisions)
and
[Target Architecture: Architecture decisions still required](03-target-architecture.md#13-architecture-decisions-still-required).

High-priority unresolved decisions:

- Client bbox extraction from a hosted PMTiles with native MapLibre is the
  proposed offline-map design; the production basemap/terrain source, offline
  style assets, and range-capable host remain unresolved.
- Download tile/size safety cap is now adjustable (presets) with a storage/time
  estimate and a pre-download confirmation; the production default/ceiling and a
  real free-space check remain to finalize.
- Background recording device verification, and background download behavior on
  iOS (an Android keep-alive foreground service is implemented; device
  verification pending).
- Supported minimum Android and iOS versions.
- Elevation smoothing and off-route thresholds.

## Index maintenance contract

Every future agent must update this index when any of these changes:

- Wiki files, titles, links, reading order, or purpose.
- Overall feature status or current milestone.
- Immediate implementation priorities.
- High-priority open decisions.
- Latest validation evidence.
- Last-reviewed date.

Keep detailed requirements and engineering information in their dedicated
documents. This index should remain a concise, accurate map of those documents
and the current project state.

When updating this file:

1. Compare the feature summary against source code and tests.
2. Update the absolute `Last reviewed` date.
3. Update all affected wiki pages in the same change.
4. Check that all local Markdown links resolve.
5. Never describe planned or dependency-only work as implemented.
