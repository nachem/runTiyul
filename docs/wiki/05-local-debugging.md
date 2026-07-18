# Local Run and Debug Guide

Last reviewed: 2026-07-18

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
`ALLOW_PUBLIC_RASTER_DEV_UNLOCK=true`: on an internal release, tap the disabled
**Current map** choice seven times within four seconds, read the warning, and
confirm. The unlock persists on that device and enables only public Streets and
CyclOSM; Satellite remains view-only. To compile out this capability for a
future production build, pass:

```powershell
flutter build apk --release `
  --dart-define=ALLOW_PUBLIC_RASTER_DEV_UNLOCK=false
```

Converted-vector downloads remain a separate path and never authorize a raster
endpoint.

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
are also available. Tap both **Off route** and **Junction** under **Test alerts**
after changing the mode; previews use the unsaved selection.

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
  right, and straight junction prompts from simulated or real GPS movement.
6. Screen locked and app backgrounded on Android and iOS.
7. Missing or disabled English TTS, confirming the bundled-tone fallback.

Automated tests validate event routing and phrases but cannot prove audibility,
voice installation, output routing, or background playback.

## 7. Offline map debugging

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

Command validation on 2026-07-18 with Flutter 3.44.6:

- Dart formatter on changed Dart files: passed.
- `flutter analyze --no-pub`: passed with no issues.
- `flutter test`: all 138 tests passed.
- `flutter build apk --debug`: passed.
- `flutter build apk --release --no-pub`: passed; embedded version is
  `1.2.0` (`versionCode` 5).
- Tests cover navigation feedback mode persistence, bundled OGG validity,
  tone/voice/haptic routing, concise guidance, speech fallback, and settings
  previews; route-screen bottom safe areas; and realtime selected/saved route
  visibility, in addition to the prior map/download/terrain coverage.
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
