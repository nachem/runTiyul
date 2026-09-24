# Local Run and Debug Guide

Last reviewed: 2026-09-06

## 1. Supported local targets

The repository contains Android and iOS runners.

- Android can be run from Windows, macOS, or Linux with an emulator or device.
- iOS requires macOS, Xcode, and an iOS simulator or registered device.
- Windows, web, and macOS desktop runners are not part of this project.

## 2. Prerequisites

- Flutter 3.44.6 stable or a compatible newer stable release.
- Android Studio with Android SDK and an emulator, or USB debugging enabled on
  an Android device.
- VS Code Flutter and Dart extensions when debugging from VS Code.
- macOS and Xcode for iOS.

Verify the toolchain:

```powershell
flutter doctor -v
flutter --version
flutter devices
```

## 3. Restore and validate

Run from the repository root:

```powershell
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

If formatting reports changes, apply them with:

```powershell
dart format lib test
```

## 4. Run on the configured Android emulator

An Android 14 emulator was detected as `emulator-5554` on 2026-07-14.

```powershell
flutter run -d emulator-5554
```

Debug builds expose tiny development-only OSM standard and CyclOSM raster
downloads by default. Both choices are labeled `DEV`; keep selections small and
never treat either public service as a production offline backend. To test the
production gate from a debug build, disable it explicitly:

```powershell
flutter run -d emulator-5554 `
  --dart-define=ENABLE_DEV_OSM_DOWNLOADS=false
```

When launching from VS Code, select **Running App**. Profile and release always
start with public-raster downloads locked. This repository defaults
`ALLOW_PUBLIC_RASTER_DEV_UNLOCK=true`: on an internal release, tap the locked
**Current map** choice seven times within four seconds, read the warning, and
confirm. The unlock persists on that device and enables only public Streets and
CyclOSM; Satellite remains view-only. To compile out this capability for a
future production build, pass:

```powershell
flutter build apk --release `
  --dart-define=ALLOW_PUBLIC_RASTER_DEV_UNLOCK=false
```

For a separately authorized internal build, Topographic and Satellite can be
added to that same seven-tap workflow by selecting **Running App (authorized
raster DEV)** in VS Code, or with:

```powershell
flutter build apk --release `
  --dart-define=ALLOW_AUTHORIZED_VIEW_RASTER_DEV_DOWNLOADS=true
```

This flag is false by default. Use it only when the provider permission covers
offline/debug caching, and continue to enforce the in-app tile cap, attribution,
retention, credentials, and any narrower terms in that grant.

Select Satellite with the map-layer picker, open Download area, and tap
**Current map: Satellite** seven times within four seconds. Confirm the DEV
warning; the chip becomes **Satellite · DEV** and the provider-limited raster
workflow becomes available. The chip stays tappable before unlock, but its tap
handler still checks build eligibility. Merely setting its enabled state does
not authorize Esri. Ordinary launch and published release defaults are unchanged.

Converted-vector downloads remain a separate path and never authorize a raster
endpoint.

### 4.1 Android release signing

Use debug builds for normal local development. Android release builds fail
closed unless all four environment values are present:

- `ANDROID_RELEASE_KEYSTORE_PATH`
- `ANDROID_RELEASE_STORE_PASSWORD`
- `ANDROID_RELEASE_KEY_ALIAS`
- `ANDROID_RELEASE_KEY_PASSWORD`

Do not put those values in the repository, shell history, logs, or a tracked
`key.properties`. Authorized release owners should load them from their local
secret store, build with `flutter build apk --release`, then verify the APK
certificate and version with Android SDK `apksigner` and `aapt`. GitHub Actions
reconstructs the keystore from encrypted repository secrets and performs those
checks automatically.

The permanent public certificate SHA-256 is
`d9f8b0d77eddcddd436d945eec37d66513f9a8f1488b5807b5bf50acf32139e5`.
Changing it or the application ID prevents Android from updating an installed
copy. The private key and password need a tested, access-controlled backup
outside both GitHub and the development machine.

For production development, configure a provider whose terms explicitly permit
offline download:

```powershell
flutter run -d emulator-5554 `
  --dart-define=TRAIL_TILE_PROVIDER_ID=my-provider `
  --dart-define=TRAIL_TILE_URL=https://example.com/{z}/{x}/{y}.png `
  --dart-define=TRAIL_TILE_ATTRIBUTION="Provider attribution" `
  --dart-define=TRAIL_TILE_OFFLINE_ALLOWED=true
```

Useful interactive commands while `flutter run` is active:

- `r`: hot reload.
- `R`: hot restart.
- `p`: toggle debug paint.
- `o`: switch Android/iOS platform rendering when supported.
- `q`: stop the application.

To run without keeping an interactive Flutter terminal:

```powershell
flutter run -d emulator-5554 --no-resident
```

`--no-resident` verifies installation and startup, then disconnects from the
debug session. Use normal `flutter run` for hot reload and debugging.

## 5. Run from VS Code

1. Open the `Running App` directory as the workspace.
2. Select the device from the Flutter device indicator in the status bar.
3. Open `lib/main.dart`.
4. Press `F5` or choose **Run > Start Debugging**.
5. Accept location permissions when testing recording and current-position
   behavior.

Set breakpoints in controllers, repositories, and services rather than only in
widgets. Use the Debug Console for exceptions and Flutter Inspector for widget
layout.

## 6. Android location simulation

For emulator GPS testing:

1. Open the emulator's **Extended controls**.
2. Select **Location**.
3. Set a single position or load a GPX route.
4. Start playback after beginning an activity in the app.

Test these states separately:

- Permission denied.
- Permission permanently denied.
- Location service disabled.
- No GPS fix.
- Good simulated movement.
- Poor accuracy or unrealistic jumps.
- App backgrounded and screen locked.

Emulator behavior does not prove background recording reliability. Complete the
release acceptance test on a physical Android and iOS device.

### 6.1 Navigation alert audio

Open **Record → Alerts** before starting a routed activity. **Tone + voice** is
the recommended default for trail use; **Voice**, **Tones**, and **Haptics only**
are also available. Tap **Off route**, **Junction**, **Route finder**, and
**Progress** under **Test alerts** after changing the mode; previews use the
unsaved selection. The same sheet configures off-route reminder cadence and
on-route progress announcements by distance or time.

Voice uses an installed English system voice and works without network access.
If speech is unavailable, Voice falls back to the bundled tone and the preview
shows a message. The device media volume controls the output.

Physical-device verification must cover:

1. Phone speaker audibility indoors and outdoors with wind and footfall noise.
2. Wired, Bluetooth, and open-ear/bone-conduction routing where available.
3. Tone + voice sequencing while music and spoken audio are playing.
4. Silent/Do Not Disturb and low-media-volume behavior without claiming an
  override the OS does not grant.
5. A selected-route run that triggers sustained off-route and approaching-left,
  right, straight, sharp-turn, and intentional U-turn prompts from simulated or
  real GPS movement. Confirm each maneuver alerts in advance and again at the
  apex, including a consecutive pair less than 45 m apart.
6. While off route, move closer and confirm two slow warning cues; then move
  away and confirm three fast cues. When the runner is on a recognized mapped
  way with a reliable course, confirm the solid recovery path reconnects ahead
  and never says behind/turn around. Without a safe connected path, confirm the
  prompt says to remain on a recognized path while searching ahead.
7. On route, cross a configured distance milestone and a time milestone;
  confirm completed/remaining distance and that no progress cue masks an
  off-route warning.
8. Slightly overshoot a turn (less than 25 m), join the correct outgoing trail,
   and confirm the apex prompt completes without a missed-waypoint warning.
9. Toggle Follow position and **North up** / **Running direction** while moving.
   Confirm reliable course changes rotate smoothly, a pan disables Follow only,
   and orientation remains selected.
10. Screen locked and app backgrounded on Android and iOS.
11. Missing or disabled English TTS, confirming the matching tone-pattern
  fallback.

Automated tests validate event routing and phrases but cannot prove audibility,
voice installation, output routing, or background playback.

## 7. Offline map debugging

### Vector comparison and route verification

For `MAP-013`, use the polyline icon (**Show vector roads and trails**) on a map.
At z14 and above it shows the actual configured vector transportation lines:
teal dashed trails, blue roads, and gray restricted ways. Below z14 it is hidden
and makes no new tile requests. Compare this overlay with Streets, CyclOSM, or
Topographic to identify raster-visible paths missing from the vector dataset.
The app does not infer routing geometry from raster pixels.

For `RTE-012`, open a dense imported route in Edit waypoints. It should retain
all coordinates but show sparse controls. Tap a visible control, or long-press
a hidden section to insert/select one, then Move/Delete. In Follow trails, only
the neighboring span changes. With snapping off, Checkpoint mode allows explicit straight edits;
switching modes itself must not change the line. Undo restores the whole edit.
Test repeated mode switching, failed/disconnected edits, and save/reload with
optional GPX altitude/timestamps.

For the v1.4.4 planning change, test a sparse right-angle bend, an S-bend,
hairpin with a point at its apex, and a T-junction whose branch meets a segment
interior. Tap within 40 m of a mapped way, then well outside it: the nearby point
should snap; the distant point should remain and produce a direct-unmapped
segment count. Undo should remove that leg and its diagnostic. Bridges, nearby
parallel paths, and prohibited connectors must not become mapped links. Repeat
with cached data in Offline mode and with a GPX off-map stop, checking retained
geometry and metadata after save/reload. Direct lines are not verified access
or navigation-recovery connections. Automated versions of these scenarios pass;
outdoor and phone performance verification remain pending.

For the v1.4.5 checkpoint update, create a new route in
**Checkpoints** with **Snap to nearby trail** enabled. Select two points around
a long bend/hairpin and verify the routed preview appears before Save. Add a
point 40-150 m off the nearest way: its location should remain and the preview
should use explicit unmapped approach segments rather than a whole-leg shortcut.
Try crowded junctions, a small end-to-end gap, and a near T-junction gap. Gap
connections are limited to 12 m, same level, and plausible continuation; parallel
ways and bridges must not acquire a mapped connection. Undo, Move, Delete,
control insertion, and Save should retain checkpoint order and preview geometry.
Repeat with cached data in Offline mode and compare saved manual Snap with GPX
shape matching. The actual phone, access/barrier situation, and missing-data
behavior still require field validation; synthetic scenarios are not a guarantee.

For the unpublished 2026-09-24 non-road fix, locate a path/track hairpin in the
vector overlay, especially one stored as a single winding line. In Checkpoints
and Follow trails, tap exactly on opposite arms and verify that both endpoints
and the intervening bend remain. Repeat beside a shorter nearby road: deliberate
trail taps should not jump to it when the trail connects. Place a slightly noisy
middle checkpoint between arms and check continuity with the neighboring points.
Reverse the route, save/reload, and inspect turns on footways, steps, and tracks.
The synthetic extraction/turn and SQLite cases pass; an actual failing GPX or map
location is still needed to verify the reported real-world case. Do not assume
missing raster-visible paths exist in the vector routing data.

For `NAV-007`, start a selected-route recording and move onto a connected
off-route way with a reliable course. The recovery line and arrow should start
forward, select the shortest available connection within the local search, and
update the rejoin distance as movement continues. Confirm a dead end, missing
way, prohibited link, or unavailable heading does not produce an invented path.
Off-route movement must not advance planned-route progress.

Offline routing requires cached extracted ways or a local MBTiles source.
The cache is bounded and opportunistic; downloading raster tiles alone is not
enough. Verify behavior with the network disabled and after restart. Physical
GPS, heading, terrain-access accuracy, and prolonged mobile CPU/memory behavior
remain unverified for the 2026-09-06 changes.

The public OpenStreetMap standard tile service must not be used for production
bulk download. Use only the app's explicitly labeled development mode for small
test areas, or configure a provider that permits offline use.

To verify offline behavior:

1. Download a deliberately small area and zoom range.
2. Confirm the area reports complete and has non-zero actual bytes.
3. Enable airplane mode or disable the emulator network.
4. Restart the app.
5. Navigate through every downloaded zoom level within the selected bounds.
6. Confirm missing coverage is visible rather than silently fetched online.
7. Delete the area and confirm reported usage decreases.

## 8. Reset local application data

Use this only when test data can be discarded:

```powershell
flutter clean
flutter pub get
```

`flutter clean` removes build output, not necessarily application data installed
on the emulator. To reset installed Android data:

```powershell
adb shell pm clear com.bernoulli.trailrunner.trail_runner
```

Clearing package data deletes local routes, activities, settings, and offline
maps.

## 9. Diagnostic commands

```powershell
flutter logs -d emulator-5554
adb logcat
flutter doctor -v
flutter pub deps
flutter pub outdated
```

Do not include complete GPS tracks, API keys, or personal location data in
shared logs or bug reports.

## 10. Before reporting successful local verification

Record:

- Absolute date.
- Flutter version.
- Target ID and Android/iOS version.
- Commands run and exact result.
- Screens and workflows exercised.
- Whether networking was disabled for offline validation.
- Whether background tracking used a physical device.
- Any permission, provider, or platform limitations.

## 11. Latest local verification

Routing/overlay/editor pass on 2026-09-06: all 273 tests passed, analysis was
clean, and the debug APK built. The tests exercise the actual overlay control,
zoom hiding, a 390x844 dense-editor layout, cache persistence, matching and
grade/access regressions, stale-result protection, and a synthetic recording
with forward recovery and in-process pause/resume. No device was connected;
no installation, outdoor validation, or iOS runtime test was performed.

Stability review on 2026-09-06:

- Analyzer and Android debug build passed; the build retains the existing
  non-fatal `flutter_tts` Kotlin-plugin migration warning.
- The full Flutter tests cover download serialization, duplicate resume,
  edit/delete cancellation, large-plan resume, vector HTTP failures, native
  picture cleanup, startup retry, and preserved route/activity links. Final
  suite totals are maintained in [implementation status](02-implementation-status.md).
- `adb devices -l` listed no device. No installation or live crash reproduction
  was possible; no signature, database corruption, or OOM root cause is confirmed.
- Do not install the debug APK over the permanent-signed release, uninstall,
  or clear app data. Reproduce on the original signed installation and inspect
  targeted crash logs; a repaired update must use the same permanent key.
- CyclOSM and Topographic are separate picker choices. No live provider
  availability claim was made during this pass. Foreground-service timeout,
  offline airplane mode, background GPS, memory stress, and iOS still need a
  physical-device test.

Current source/test validation on 2026-09-04:

- Changed Dart files were formatted.
- `flutter analyze --no-pub`: passed with no issues.
- Full VS Code Flutter test runner: all 175 tests passed, including terrain,
  temporary offline-preview, and direct topographic-provider regressions.
- The source/test run itself did not use a device; map behavior was not manually
  inspected during that run.
- Live tile probes returned valid images for OSM Standard, OpenTopoMap, and
  Esri while CyclOSM returned HTTP 502. Online Topographic now uses OpenTopoMap
  directly so interactive tiles remain cacheable and do not wait on CyclOSM.
- The direct-Topographic revision built with the protected permanent signer,
  installed in place on the Pixel 10, and cold-launched successfully in 667 ms.
  Device screenshots confirmed Online Streets and settled, sharp Online
  Topographic tiles; the next 500 buffered log lines had no immediate Flutter
  or Android fatal exception.
- The current source then built as a release APK with the DPAPI-protected local
  recovery key. Its package, `1.4.0+10` identity, and permanent certificate were
  verified before `pm install -r` returned `Success` on a Pixel 10. Android kept
  the original first-install timestamp, the cold activity launch returned
  `Status: ok` in 273 ms, the process remained alive, and no immediate fatal
  log lines were found. Stored routes/maps and map rendering were not manually
  inspected; this was a same-version replacement, not a cross-version upgrade.

The latest APK validation remains the 2026-08-19 run with Flutter 3.44.6 and
Dart 3.12.2:

- Dart formatting passed on every changed Dart source/test file.
- `flutter analyze --no-pub`: passed with no issues.
- Full VS Code Flutter test runner: all 171 tests passed.
- `flutter build apk --debug --no-pub`: passed for `1.4.0+10`; Android SDK
  inspection reports package `com.bernoulli.trailrunner.trail_runner`,
  `versionName=1.4.0`, `versionCode=10`, and label `RunTiyul`.
- Local debug APK: 166,344,270 bytes, SHA-256
  `e4a076f89c8b6d221ce947620c58e1ae71d841dd86446f030aa158fdbcb2f4aa`.
- CRLF-aware `git diff --check` passed.
- The new Back history, route cleanup/snapping, forward mapped-way recovery,
  exact maneuver timing/angles/sequences, overshoot grace, and recording camera
  settings are analyzer/unit/widget-tested but not physical-device verified.

Hosted release validation on 2026-08-20:

- Release run
  [`32322574702`](https://github.com/nachem/runTiyul/actions/runs/32322574702)
  passed metadata, protected Android signing/identity verification, unsigned
  iOS packaging, checksums, provenance, and publication for `v1.4.0+10`.
- Independent public checksums passed: APK
  `b33d2d81a7dd30966052e210dc820fff2314774ff52e29cbc4da6e9d86e40e12`
  (62,118,520 bytes) and IPA
  `0fde120ff9bc435dc362eb24d0f8cb2dcc8138466cb3fcafe3ad2478a7ee721c`
  (15,947,212 bytes).
- Public APK inspection confirmed package
  `com.bernoulli.trailrunner.trail_runner`, `1.4.0+10`, label `RunTiyul`, and
  the permanent release certificate. Both provenance attestations and stable
  latest-download URLs verified.

Previous published-release validation:

Command validation on 2026-07-27 with Flutter 3.44.6:

- Dart formatter on changed Dart files: passed.
- `flutter analyze --no-pub`: passed with no issues.
- `flutter test`: all 148 tests passed.
- `flutter build apk --debug --no-pub`: passed; the APK embeds `1.3.0`
  (`versionCode` 8) and the expected package.
- Release run
  [`30255797959`](https://github.com/nachem/runTiyul/actions/runs/30255797959)
  passed metadata, protected Android signing/identity verification, unsigned
  iOS packaging, and publication.
- Independent `apksigner`/`aapt` verification of the public APK passed for
  package `com.bernoulli.trailrunner.trail_runner`, `1.3.0+8`, and the permanent
  certificate. Public APK SHA-256 is
  `341c038a3514df921fb2b2647101b24cd31b2601166501092e61a21191314496`.
- Public IPA SHA-256 is
  `d5fe1f765ee31b2de71027536dfb3acdb04fd7f1f513db0e0a8d0253c0181601`;
  both stable latest-download URLs returned 200.
- Wiki links and the CRLF-aware Git diff check passed. `actionlint` was
  unavailable locally.
- Tests cover nearest-route bearing and relative direction, off-route trend
  cadence, monotonic distance/time progress milestones, junction priority,
  tone/voice/haptic routing, speech fallback, persistence, and four settings
  previews, in addition to the prior map/download/terrain coverage.
- Tests also cover first-install/change detection, one-time version
  acknowledgement, update-dialog content, and About version display.
- The Android build emitted a non-blocking future-compatibility warning because
  `flutter_tts` 4.2.5 still applies KGP rather than Built-in Kotlin.

Last Android emulator interaction evidence remains from 2026-07-14:

- Android 14/API 34 emulator launch: passed.
- Primary map controls and Auto/Online/Offline selector: exercised; Online
  persisted across process restart and Auto was restored afterward.
- All saved trails intersecting the viewport rendered on the primary map, and
  route selection switched from Routes to Map with the full control stack.
- Saved offline area selection switched to the primary map with bounds and edit
  action; Offline was selectable regardless of current coverage.
- A zoom 12-15 offline area disabled zoom-out at 12 and zoom-in at 15.
- Manual route persistence, recording lifecycle, activity history, offline
  selection/estimate, and storage reporting: exercised.
- Completed offline area preview after disabling network and restarting:
  rendered local tiles.

Physical-device background tracking, alert audibility/background playback, and
iOS remain unverified.
