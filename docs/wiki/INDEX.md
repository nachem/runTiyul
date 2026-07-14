# RunTiyul Wiki Index

Last reviewed: 2026-07-14  
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
| 6 | [Offline map implementation](06-offline-map-packages.md) | Proposed legal offline-map design: client bbox extraction from a hosted PMTiles source, native MapLibre rendering, optional terrain, migration, validation, and rollout. | Offline source, format, renderer, terrain, licensing, hosting, or implementation plan changes. |
| 7 | [Wiki conventions](README.md) | Source-of-truth hierarchy and general documentation maintenance rules. | Wiki governance or document organization changes. |

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
| Online map | Implemented with provider abstraction and attribution |
| Map controls/source modes | Zoom, fit/reset, GPS recenter, always-available Offline discovery, and persisted source choice implemented |
| Trail map integration | All in-view trails render; route taps open the primary map with full controls |
| GPX route import | Implemented and parser tested; native picker not emulator verified |
| GPS activity recording | Implemented; emulator permission/timer/lifecycle verified |
| Visual route navigation | Implemented; progress and off-route alerts remain |
| Activity history | Implemented and emulator verified |
| Activity GPX export | Implemented and serialization-tested; native save dialog unverified |
| Offline map downloads | Implemented behind provider-policy gate; VS Code debug enables the capped development override |
| Offline tile rendering | Main-map bounds preview/edit and downloaded zoom constraints implemented |
| Offline storage management | Implemented for per-area/total bytes and overlap-safe delete |
| Long-term offline maps | Extraction-based PMTiles + MapLibre target guide documented; renderer, extractor, source, terrain, and hosting are not implemented or selected |
| Automated validation | Format/analyze pass; 14 tests pass; debug APK builds |

Detailed evidence belongs in
[Implemented Details and Current Status](02-implementation-status.md).

## Current implementation priority

1. Complete the MapLibre + client-extraction spike and select an auditable
   PMTiles source, optional terrain source, and range-capable host.
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
- Download tile/size safety limits.
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
