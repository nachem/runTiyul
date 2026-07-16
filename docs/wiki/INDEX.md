# RunTiyul Wiki Index

Last reviewed: 2026-07-16  
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
| 8 | [Wiki conventions](README.md) | Source-of-truth hierarchy and general documentation maintenance rules. | Wiki governance or document organization changes. |

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
| Online map | Implemented with provider abstraction, source-accurate attribution, and a base-layer switch (streets plus an online-only Esri satellite/orthophoto layer) |
| Map controls/source modes | Zoom, fit/reset, GPS recenter, show/hide saved trails, always-available Offline discovery, a base-layer picker switching online tiles between the downloadable provider and online-only satellite imagery, and persisted source and layer choices on every map surface with auto-fit; a content-less map opens centered on the current location at a neighborhood zoom; Auto layers live online tiles on top of the saved map, and zoom-in overzooms saved tiles past the downloaded maximum |
| Trail map integration | All in-view trails render as dashed lines; route taps open the primary map with full controls and fit the whole trail |
| GPX route import | Implemented and parser tested; native picker not emulator verified |
| GPS activity recording | Implemented; emulator permission/timer/lifecycle verified |
| Visual route navigation | Trail-follow route creation (tap real trails), route snapping to trails on save (toggle), and live off-route/junction alerts (configurable) implemented; not device-verified; route progress % remains |
| Activity history | Implemented and emulator verified |
| Activity GPX export | Implemented and serialization-tested; native save dialog unverified |
| Offline map downloads | Implemented behind provider-policy gate; per-tile raster or on-device vector→raster conversion (defaults to the free OpenFreeMap OpenMapTiles endpoint; overridable in-app via Offline maps → Download area → Set source or `TRAIL_VECTOR_MBTILES`); VS Code debug enables the capped development override |
| Offline tile rendering | Main-map bounds preview/edit and downloaded zoom constraints implemented; zoom-in overzooms saved tiles past the downloaded maximum |
| Offline storage management | Implemented for per-area/total bytes and overlap-safe delete, with per-area source chips and a details popup |
| Long-term offline maps | On-device vector→raster conversion implemented behind `TRAIL_VECTOR_MBTILES` (pure-Dart `vector_tile_renderer`, reuses the raster renderer); native MapLibre rendering, terrain, and a hosted source remain unimplemented |
| Automated validation | Format/analyze pass; 60 tests pass; debug APK builds |
| Website & distribution | Landing site (`site/`) **deployed live** at https://nachem.github.io/runTiyul/, `v1.0.0` release published with APK + unsigned IPA (both download links verified 200), MIT license, public repo (see [Release & distribution](07-release-and-distribution.md)) |

Detailed evidence belongs in
[Implemented Details and Current Status](02-implementation-status.md).

## Current implementation priority

1. Verify the implemented on-device vector→raster conversion with real regional
   MBTiles data on a device, then decide between refining it (styles, labels,
   fonts) or adding a native MapLibre renderer and terrain.
2. Verify background recording on physical Android and iOS devices.
3. Add route progress, off-route detection, and alerts.
4. Add free-space checks, orphan cleanup, and explicit database migrations.
5. Configure production IDs, signing, and release builds.

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
- Background recording and background download behavior.
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
