# RunTiyul Wiki Index

Last reviewed: 2026-09-22<br>
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
| 7 | [Release & distribution](07-release-and-distribution.md) | Website, release artifacts, CI, supply-chain controls, community health, licensing, and the release runbook. | Website, automation, repository security, community policies, artifact names, distribution, or licensing change. |
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
| Flutter Android app | Implemented; `1.4.3+13` permanently signed, published, and independently artifact-verified on 2026-09-22, not device-installed. Earlier `1.4.0+10` was installed in place and cold-launched on a Pixel 10; Android 14 emulator verification also exists. |
| Flutter iOS app | Unsigned `1.4.3+13` IPA built and published by macOS CI; checksum and provenance verified, runtime and sideloading unverified |
| Application navigation | Implemented with five Material 3 destinations; Back returns through pushed screens and destination history, and only root Map allows app exit |
| App version awareness | About displays package-derived version/build metadata; a changed build is detected from local SQLite state and announced once. Analyzer/unit/widget-tested; real two-APK upgrade remains device-unverified |
| Online map | Streets, CyclOSM, Topographic (OpenTopoMap), and Satellite are independent persisted choices. Topographic remains view-only by default, overzooms native z17 through z19, and makes no separate elevation requests. No per-tile fallback; current provider availability was not probed. |
| Vector comparison overlay | Independent polyline toggle on every map; configured vector roads/trails and restricted ways, z14+ only, bounded/debounced/cancellable loads with source attribution. Offline is cache/local-only. Analyzer/unit/widget-tested; real raster/vector comparison remains device-unverified. |
| Dense route editing and matching | v1.4.4 preparation fixes sparse bends and same-level endpoint-to-segment T-junctions. Nearby points snap, distant points remain as reported direct connections, and whole-route snapping retains off-map stops. Local Move/Delete, sparse controls, Undo, GPX metadata, access/grade separation, and stale-result protection remain. Navigation recovery stays strictly mapped. Synthetic/unit/widget-tested, not field-verified. |
| Forward recovery | Bounded multi-target shortest-path search with initial forward constraint; off-route progress stays fixed, recovery trims/replans with movement and shows a direction arrow. Shared bounded map-way cache supports local/offline data. Synthetic-GPS-tested; outdoor direction/access, device performance, and guaranteed offline routing coverage remain unverified. |
| Stability review (2026-09-06) | Serialized area downloads/storage mutations, duplicate-resume protection, cancel/drain before edit/delete, queued-pause controls, larger-plan resume, converted-tile reuse, explicit vector HTTP errors/retries, native graphics cleanup, preserved route/activity links, coalesced database open, startup retry, and Android data-sync timeout stop are implemented and regression-tested. Reported phone crash remains unreproduced; no device was connected. Signing identity and schema v2 are unchanged. |
| Map controls/source modes | Published v1.4.3 separates Center view (keep zoom) from Fit route and content (adjust zoom); center-view and GPS recenter preserve zoom, and center-view preserves rotation. Delayed startup camera placement is cancelled by toolbar actions. Untouched startup and automatic route previews retain their fitting behavior. Source controls, safe-area panels, offline preview restoration, and z19 overzoom remain. |
| Trail map integration | All in-view trails render as dashed lines; route taps open the primary map with full controls and fit the whole trail; realtime recording receives all saved-route overlays, while the selected navigation route remains visible independently of the saved-trails toggle |
| GPX route import | Implemented and parser tested; native picker not emulator verified |
| GPS activity recording | Delayed fixes use elapsed-time-aware plausibility, five-minute gaps start a zero-distance segment, and stream failure durably pauses recording with an error. Analyzer/unit/SQLite-workflow-tested; Android Battery Saver and background behavior remain physical-device unverified. |
| Visual route navigation | Trail-follow creation and connected whole-route snapping for manual/GPX routes; bounded junction-artifact cleanup; strict mapped-way forward recovery; exact-angle advance/apex, U-turn, consecutive-turn, and overshoot-tolerant guidance; monotonic distance/time progress; Tone + voice/Voice/Tones/Haptics modes; and audio-focus release are implemented and analyzer/unit/widget-tested. Live recovery geometry, heading, camera, audio/media, and background behavior remain physical-device unverified; visual progress percentage remains. |
| Recording map tracking | Persisted Follow position and North up / Running direction controls use quality-filtered course and atomic, zoom-preserving camera updates. One-finger pan disables Follow; pinch/double-tap zoom and rotation retain it. Analyzer/unit/widget-tested, not physical-device verified. |
| Route creation performance | Follow trails uses bounded local z14 loads and candidate routing. Distant taps retain explicit direct connections rather than fetching an unbounded corridor or being rejected. Graphs build lazily, endpoint splits are bounds-filtered, and display simplification preserves saved geometry. Analyzer/unit/widget-tested; long-route phone profiling remains. |
| Activity history | Implemented and emulator verified |
| Activity GPX export | Implemented and serialization-tested; native save dialog unverified |
| Android package size | v1.4.3 universal APK is 62.74 MB (59.83 MiB), primarily three CPU-architecture library sets. An ARM64-only payload is estimated at roughly 24 MB; no split build or size optimization was performed. App/User data remain distinct. See the [size audit](07-release-and-distribution.md#apk-size-audit-2026-09-22). |
| Latest published release | [v1.4.3+13](releases/v1.4.3.md) published 2026-09-22 from `f32b565` on `main`, after hosted CI and CodeQL passed. Public APK/IPA checksums, Android identity/certificate, exact tagged-workflow provenance, and stable latest URLs verify. Device testing remains pending. |
| Prepared next version | [v1.4.4+14](releases/v1.4.4.md), local and unpublished: routing bends/T-junctions, nearby snaps/direct connections, authorized Esri DEV workflow. 331 tests, analyzer, and authorized-DEV Android debug build pass; no install or field test. |
| Release workflow | [Run 35750301499](https://github.com/nachem/runTiyul/actions/runs/35750301499) passed metadata, Android permanent-signature/identity verification, unsigned iOS build, checksums, APK+IPA provenance, and publication for `v1.4.3`; `v1.2.1` remains an unpublished tag with no artifacts |
| Android update compatibility | `v1.4.3` retains the `v1.2.2` permanent certificate and increases `versionCode` to 13. On 2026-09-04, a locally rebuilt, matching-signed `1.4.0+10` APK replaced the installed `1.4.0+10` app on a Pixel 10 with `pm install -r`; Android preserved the original install timestamp and recorded a new update timestamp. A true cross-version upgrade and manual inspection of retained routes/maps remain unverified. Published builds through `v1.2.0` used incompatible ephemeral debug keys and require a one-time uninstall |
| Offline map downloads | Implemented behind provider-policy gate. The top-level picker offers **MBTiles / vector** and **Current map: _layer_**. Debug immediately enables public Streets/CyclOSM as `DEV`; release starts locked but this repository compiles the developer capability on by default, so seven taps plus warning/confirmation unlocks eligible sources on that device. Topographic/Satellite remain view-only unless a separately authorized internal build explicitly enables `ALLOW_AUTHORIZED_VIEW_RASTER_DEV_DOWNLOADS`; arbitrary providers remain excluded. Provider id + format persist per area for correct resume/render/delete. Android foreground keep-alive and foreground resume remain device-unverified |
| Offline tile rendering | Main-map bounds preview/edit and downloaded zoom constraints implemented; zoom-in overzooms saved tiles past the downloaded maximum. Saved tiles use an ordered, area-aware renderer, and provider/format namespaces prevent collisions. Offline-area bounding boxes remain visible as colored outlines but have fully transparent fills, so overlapping areas do not tint the map. Preview/auto-fit floor at the downloaded minimum (`offlineAwareFitZoom`), and a progress-independent map key prevents in-progress downloads from recreating the map controls |
| Offline storage management | Implemented for per-area/total bytes and overlap-safe delete, with per-area source chips and a details popup; the saved-areas list is drag-to-reorder and the order both persists and drives which area renders on top |
| Long-term offline maps | On-device vector→raster conversion uses pure-Dart `vector_tile_renderer`, crisp parent over-rendering above source z14 through selectable z16, English-preferring labels, trail emphasis, and peak labels; native MapLibre rendering and a hosted production source remain unimplemented |
| Topographic offline maps | Implemented only for converted-vector areas: Terrarium is fetched during conversion at z10-z13, rendered in memory into labeled contours + subdued hillshade (z13 parent reused with progressively reduced overlay opacity for deeper output), and baked into the final PNG. Raw elevation and overlays are never stored; online/raster maps make no separate elevation requests. The removed runtime overlay/cache/downloader is cleaned up once on startup. Converted maps credit both sources. Not device-verified; visual quality, conversion speed, memory, battery, and storage need physical-device validation |
| Open-source project health | Contribution, conduct, support, privacy, and security policies; CODEOWNERS; issue/PR templates; Dependabot; SHA-pinned Actions; and version-pinned PR/release workflows are configured. Private vulnerability reporting, dependency alerts/security updates, secret scanning, and push protection are enabled. Push CI and Pages pass; PR dependency review/provenance remain unexercised and `main` is not protected |
| Automated validation | On 2026-09-22, all 331 tests and full analysis passed for v1.4.4 preparation; changed Dart files were formatted and the authorized-DEV debug APK built. Synthetic planning/editor/persistence and mocked Esri workflow tests pass. No live-provider, device install/field test, signed release build, or iOS validation occurred for this change. v1.4.3 hosted release evidence remains recorded separately. |

Detailed evidence belongs in
[Implemented Details and Current Status](02-implementation-status.md).

Authorized Esri development: select **Running App (authorized raster DEV)** in
VS Code, then use the current-map seven-tap confirmation. The chip remains
tappable but cannot bypass build/provider eligibility; unlocked Satellite shows
`DEV`. The user confirmed development permission; no production rights are
implied. See the [local guide](05-local-debugging.md).

Development raster-download hardening (2026-09-22): current-map downloads now
use provider-specific pacing and batch breaks, shared persisted `Retry-After`
cooldowns, interruptible waits/retries, and resumable provider-requested pauses.
Development defaults use one worker; permission gates remain unchanged. All
305 tests and the analyzer passed; no live-provider or device validation was
performed for this change. The gate does not cover interactive browsing or
vector/terrain requests. See the
[implementation and evidence](02-implementation-status.md#2026-09-22-development-raster-download-hardening).

## Current implementation priority

Camera verification gate: v1.4.3 includes zoom-preserving Center view and
separate Fit, plus the v1.4.2 delayed-startup correction. Verify both centering
controls, manual scale, and explicit Fit with slow GPS on a phone. Earlier
APKs do not contain the complete control separation.

Routing verification gate: on a physical device, compare vector overlays with
the problematic raster routes, test sparse-control edits/save/reload, and check
forward recovery with real heading and trail access. Display-vector maps may
omit routable paths/topology/access metadata; do not claim a complete routing
engine or guaranteed offline coverage from the bounded opportunistic cache.

Immediate stability gate: connect the affected phone and reproduce the reported
crash on its existing signed installation before claiming a root cause. Inspect
targeted crash logs; verify download pause/resume/edit/delete, long terrain
conversion, Android background timeout, and retained routes/maps with a
matching-signed update. Do not uninstall or clear local data. The debug artifact
is not an in-place update for the permanent-signed release.

1. Verify topographic vector conversion with real regional data on a device:
  compare against CyclOSM, inspect contour labels/hillshade and z13 parent
  overzoom, and measure conversion speed, memory, battery, and final storage.
2. Verify independent Streets, CyclOSM, and OpenTopoMap online selection,
  including Topographic z18/z19 overzoom, plus a small development-only raster
  download while confirming no separate Terrarium request occurs.
3. Verify background recording/downloads and navigation on physical Android and
  iOS devices: mapped forward recovery with no backtracking, exact
  advance/apex/consecutive/U-turn prompts, 25 m overshoot grace, Follow position
  and Running direction camera behavior, off-route cadence, heading accuracy,
  outdoor audibility, headphones, missing-language fallback,
  interrupted-music resumption, and locked-screen playback.
4. Stress-test zoomed-out and long Follow trails routes on a mid-range physical device, including memory, tap latency, and save/reload fidelity.
5. Add free-space checks, orphan cleanup, and explicit database migrations.
6. Secure an independent signing-key backup, then verify a data-preserving
  upgrade from `v1.2.2` to `v1.4.0` on a physical Android device.
7. Require the verified CI check on `main`, verify dependency review on a pull
  request, and decide whether to publish an SBOM/dependency-license inventory.

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
