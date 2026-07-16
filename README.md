<div align="center">

<img src="RunTiyul.gif" alt="RunTiyul" width="132" />

# RunTiyul

### Run wild. Stay found.

**Offline-first trail running for Android & iOS — download the map before you
lose signal, follow your route with live GPS, and record every run. No account,
no tracking.**

_An open-source app by **[Bernoulli Software](https://github.com/nachem/runTiyul)**._

[![Website](https://img.shields.io/badge/website-nachem.github.io%2FRunTiyul-4f7ff0?style=flat-square)](https://nachem.github.io/runTiyul/)
[![Download APK](https://img.shields.io/badge/Android-Download%20APK-3ddc84?style=flat-square&logo=android&logoColor=white)](https://github.com/nachem/runTiyul/releases/latest/download/RunTiyul.apk)
[![Download IPA](https://img.shields.io/badge/iOS-Download%20IPA-000000?style=flat-square&logo=apple&logoColor=white)](https://github.com/nachem/runTiyul/releases/latest/download/RunTiyul.ipa)
[![License: MIT](https://img.shields.io/badge/License-MIT-f97316?style=flat-square)](LICENSE)
[![Built with Flutter](https://img.shields.io/badge/Built%20with-Flutter-027DFD?style=flat-square&logo=flutter&logoColor=white)](https://flutter.dev)

**[🌐 Website](https://nachem.github.io/runTiyul/) · [⬇️ Download](https://github.com/nachem/runTiyul/releases/latest) · [📖 Wiki](docs/wiki/INDEX.md) · [🤝 Become a maintainer](https://github.com/nachem/runTiyul/issues/new?title=I%27d%20like%20to%20help%20maintain%20RunTiyul)**

</div>

---

RunTiyul is an offline-first Flutter application for trail route management,
on-route navigation, GPS activity recording, and offline map storage. It is
designed for the backcountry: everything you need works with the phone in
airplane mode, and nothing about your runs leaves your device.

> **Current status:** functional Android-verified MVP. Production map-provider
> configuration, iOS runtime validation, and physical-device background tracking
> remain before full release readiness. See the
> [implementation status](docs/wiki/02-implementation-status.md) for the
> evidence-based, dated inventory.

## Features

- **📍 Offline maps** — download map areas ahead of time and render them with no
  connectivity (airplane-mode capable).
- **🗺️ GPX import & route builder** — bring in existing routes or build new ones
  by tapping real trails.
- **🏃 GPS activity recording** — track distance, pace, and elevation with
  filtering for clean stats.
- **🧭 On-route navigation** — follow your line with off-route and junction
  alerts so you stay found.
- **📚 Activity history & GPX export** — review past runs and export them as GPX.
- **🔒 Privacy-first** — local-only storage, no account, no ads, no trackers.

## Download

Public, permanent builds are published as **GitHub Release** assets, and the
same links are surfaced on the [website](https://nachem.github.io/runTiyul/):

| Platform | File | Link |
| --- | --- | --- |
| Android | `RunTiyul.apk` | [Download APK](https://github.com/nachem/runTiyul/releases/latest/download/RunTiyul.apk) |
| iOS (unsigned) | `RunTiyul.ipa` | [Download IPA](https://github.com/nachem/runTiyul/releases/latest/download/RunTiyul.ipa) |

**Android:** enable "install unknown apps" for your browser/file manager, then
open the `.apk` (or `adb install RunTiyul.apk`).

**iOS:** the `.ipa` is **unsigned**. Sideload it with
[AltStore](https://altstore.io) or [Sideloadly](https://sideloadly.io) using
your own Apple ID, then trust the developer profile in
_Settings → General → VPN & Device Management_.

> Download links resolve once the first `v*` release has been published by CI.

## Quick start (developers)

Prerequisites:

- Flutter stable (Dart SDK `^3.12.2`), Flutter 3.44.6 or a compatible newer
  stable release
- Android Studio and an Android emulator, or a connected Android device
- macOS with Xcode for iOS builds

```powershell
flutter pub get
flutter analyze
flutter test
flutter devices
flutter run -d <device-id>
```

This repository contains Android and iOS targets. It does not contain a Windows
desktop target. For toolchain setup, VS Code debugging, GPS simulation, and
offline verification, see the
[local run and debug guide](docs/wiki/05-local-debugging.md).

## Build release artifacts locally

```powershell
# Android
flutter build apk --release        # build/app/outputs/flutter-apk/app-release.apk

# iOS (unsigned .app, then zip into an .ipa Payload)
flutter build ios --release --no-codesign
```

## Continuous delivery

Two GitHub Actions workflows power distribution:

- **[`.github/workflows/release.yml`](.github/workflows/release.yml)** — on a
  pushed `v*` tag (or manual dispatch) it builds the Android APK on Ubuntu and an
  unsigned iOS `.ipa` on macOS, then publishes a GitHub Release with the stable
  assets `RunTiyul.apk` and `RunTiyul.ipa`.
- **[`.github/workflows/pages.yml`](.github/workflows/pages.yml)** — on pushes to
  `main` that touch `site/**` (or manual dispatch) it deploys the marketing site
  in [`site/`](site/) to GitHub Pages.

### One-time setup

1. **Enable Pages:** repository _Settings → Pages → Build and deployment →
   Source: **GitHub Actions**_.
2. **Publish the first release** so download links resolve:

   ```powershell
   git tag v1.0.0
   git push origin v1.0.0
   ```

   The stable asset names (`RunTiyul.apk` / `RunTiyul.ipa`) keep the
   `releases/latest/download/...` links valid across every future release.

## Project layout

| Path | Purpose |
| --- | --- |
| `lib/` | Flutter application source |
| `test/` | Automated tests |
| `site/` | GitHub Pages marketing/landing site |
| `.github/workflows/` | Release + Pages CI |
| `docs/wiki/` | Authoritative project wiki (start at `INDEX.md`) |

## Project wiki

Start with the [wiki index](docs/wiki/INDEX.md). It records the required reading
order, current implementation state, immediate priorities, and maintenance
rules. Release and distribution specifics live in
[Release & distribution](docs/wiki/07-release-and-distribution.md).

All coding agents must follow [`AGENTS.md`](AGENTS.md) and update the relevant
wiki pages plus the index whenever project status or documentation changes.

## Contributing & maintainers

RunTiyul is open source and **actively looking for maintainers and
contributors**. Whether you want to fix a bug, improve the docs, verify iOS, or
help steward the project long-term — you're welcome here.

**New here and want to help maintain RunTiyul?** The easiest first step is to
[open an issue or leave a comment](https://github.com/nachem/runTiyul/issues/new?title=I%27d%20like%20to%20help%20maintain%20RunTiyul&body=Hi%20Bernoulli%20Software%2C%20I%27d%20like%20to%20contribute%2Fbecome%20a%20maintainer.%20Here%27s%20a%20bit%20about%20me%3A)
introducing yourself and asking to become a maintainer.

Ways to contribute:

1. **Report bugs & request features** on the
   [issues page](https://github.com/nachem/runTiyul/issues).
2. **Open a pull request** — fork, branch, run `flutter analyze` and
   `flutter test`, then submit.
3. **Improve the wiki** under `docs/wiki/` following [`AGENTS.md`](AGENTS.md).

Please keep the project's principles intact: offline-first behavior, explicit
error handling, type safety, location privacy, and map-provider licensing
(never use the public `tile.openstreetmap.org` service for bulk/offline
downloads).

## License

Released under the [MIT License](LICENSE).

Map data © OpenStreetMap contributors.

---

<div align="center">

Made with 🦊 by **Bernoulli Software**

</div>
