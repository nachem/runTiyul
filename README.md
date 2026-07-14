# RunTiyul

RunTiyul is an offline-first Flutter application for trail route
management, on-route navigation, GPS activity recording, and offline map
storage.

> Current status: functional Android-verified MVP. Production map-provider
> configuration, iOS validation, and physical-device background tracking remain
> before release readiness.

## Project wiki

Start with the [wiki index](docs/wiki/INDEX.md). It records the required reading
order, current implementation state, immediate priorities, and maintenance
rules.

All coding agents must follow [`AGENTS.md`](AGENTS.md) and update the relevant
wiki pages plus the index whenever project status or documentation changes.

For local launch and troubleshooting, see the
[local run and debug guide](docs/wiki/05-local-debugging.md).

## Quick start

Prerequisites:

- Flutter 3.44.6 stable or a compatible newer stable release
- Android Studio and an Android emulator, or a connected Android device
- macOS with Xcode for iOS builds

```powershell
flutter pub get
flutter analyze
flutter test
flutter devices
flutter run -d <device-id>
```

This repository currently contains Android and iOS targets. It does not contain
a Windows desktop target.
