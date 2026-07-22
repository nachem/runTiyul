# Release & Distribution

Last reviewed: 2026-07-21

This page documents how RunTiyul is packaged, published, and marketed: the
public website, the release artifacts, and the CI that produces them. It
describes what is **implemented in the repository**, not planned work.

## 1. Summary

| Concern | Mechanism | Status |
| --- | --- | --- |
| Marketing/landing site | Static site in [`site/`](../../site/), deployed to GitHub Pages | Deployed and live at https://nachem.github.io/runTiyul/ (verified 2026-07-16) |
| Android artifact | `RunTiyul.apk` published to GitHub Releases | Built and published in `v1.2.0` (61,511,724 bytes); latest-download link verified 200 on 2026-07-18 |
| iOS artifact | `RunTiyul.ipa` (unsigned) published to GitHub Releases | Built on the macOS runner and published in `v1.2.0` (15,780,126 bytes); latest-download link verified 200 on 2026-07-18. On-device sideload remains unverified |
| License | [MIT](../../LICENSE), © Bernoulli Software | Implemented |
| Repository visibility | Public | Implemented |

The download links used by the site and README point at stable asset names via
`https://github.com/nachem/runTiyul/releases/latest/download/RunTiyul.apk` and
`...RunTiyul.ipa`. As of the
[`v1.2.0` release](https://github.com/nachem/runTiyul/releases/tag/v1.2.0)
(2026-07-18), both resolve `200`. Release workflow
[`29647773618`](https://github.com/nachem/runTiyul/actions/runs/29647773618)
passed its metadata gate, Android build, unsigned iOS build, and publication
jobs; the published body exactly matches `docs/wiki/releases/v1.2.0.md`.

## 2. Website (`site/`)

- Static, dependency-free landing page: `index.html`, `styles.css`, `main.js`,
  plus `.nojekyll`, `robots.txt`, `sitemap.xml`, and optimized assets under
  `site/assets/`.
- The new RunTiyul artwork is used consistently across the website: GIF with
  WebP/PNG fallbacks for the hero, a compact square PNG for header/footer marks,
  dedicated 32 px/192 px favicons and Apple touch icon, and a 1200x630 social
  preview image. Native Android/iOS launcher icons use an aspect-preserving
  square derivative from `assets/branding/app_icon.png`.
- Dark/light theme (persisted in `localStorage`), responsive layout, scroll
  reveal, and a live "latest release" lookup via the GitHub REST API that
  rewrites the download links and shows the current version when a release
  exists.
- Prominent attribution to **Bernoulli Software** (hero, open-source section,
  footer) and a "comment to become a maintainer" contributor call-to-action
  linking to a pre-filled GitHub issue.
- Content is derived from the app's implemented feature set (offline maps, GPX
  import/route builder, GPS recording, on-route navigation, history/GPX export,
  privacy-first local storage). Copy must not claim unverified capabilities;
  keep it aligned with [implementation status](02-implementation-status.md).

Deployed URL (once Pages is enabled): `https://nachem.github.io/runTiyul/`.

## 3. CI workflows

### `.github/workflows/release.yml`

- **Triggers:** pushed tag matching `v*`, or manual `workflow_dispatch`.
- **Metadata gate:** before any platform build, strict `vMAJOR.MINOR.PATCH` must
  match the semantic version in `pubspec.yaml`, and a non-empty matching note at
  `docs/wiki/releases/<tag>.md` must exist.
- **Android job (Ubuntu):** `flutter build apk --release`, renamed to
  `RunTiyul.apk`. Before building, it decodes the permanent keystore from
  Actions secrets into the runner's temporary directory. Gradle fails closed
  unless all signing values are present.
- **Android identity gate:** the metadata job requires a positive build number
  greater than every prior tagged release. After building, CI verifies package
  `com.bernoulli.trailrunner.trail_runner`, the expected version name/code, and
  release certificate SHA-256
  `d9f8b0d77eddcddd436d945eec37d66513f9a8f1488b5807b5bf50acf32139e5`
  before the APK can be uploaded.
- **iOS job (macOS):** `flutter build ios --release --no-codesign`, then the
  `Runner.app` is zipped into a `Payload/` structure to produce an **unsigned**
  `RunTiyul.ipa`. No Apple signing secrets are used.
- **Publish:** both assets are attached to a GitHub Release via
  `softprops/action-gh-release@v2` (needs `permissions: contents: write`). The
  matching wiki release-note file is used verbatim as the Release body. The
  publish job is resilient: it runs whenever the Android APK build succeeds and
  attaches the iOS `.ipa` only when that best-effort macOS build produced one, so
  a failing iOS build never blocks the APK release.
- Stable asset names are required so `releases/latest/download/...` links stay
  valid across releases.

### `.github/workflows/pages.yml`

- **Triggers:** push to `main` touching `site/**`, or manual dispatch.
- **Deploy:** `actions/configure-pages` → `upload-pages-artifact` →
  `deploy-pages`, publishing the `site/` directory.

## 4. Operational runbook

One-time setup (both completed 2026-07-16):

1. Repository must be **public** (done).
2. Enable Pages via _Settings → Pages → Build and deployment → Source: **GitHub
   Actions**_ (done; also settable with
   `gh api -X POST repos/nachem/runTiyul/pages -f build_type=workflow`).

Required repository Actions secrets (configured 2026-07-21):

- `ANDROID_RELEASE_KEYSTORE_BASE64`
- `ANDROID_RELEASE_STORE_PASSWORD`
- `ANDROID_RELEASE_KEY_ALIAS`
- `ANDROID_RELEASE_KEY_PASSWORD`

Secret values and the private key must never be committed or printed. The
release owner must retain an access-controlled backup outside the repository;
losing the key makes future in-place Android updates impossible.

To publish a release (example `v1.2.1`):

1. Choose the next semantic version and a monotonically increasing Flutter
  build number.
2. Update `pubspec.yaml` (for example `version: 1.2.1+6`).
3. Add `docs/wiki/releases/v1.2.1.md`, update the
  [release-notes index](08-release-notes.md), and synchronize this page and
  `INDEX.md`.
4. Run formatting, analyzer, tests, the relevant platform build, and local wiki
  link validation.
5. Commit the complete release state, then tag and push that exact commit:

```powershell
git tag v1.2.1
git push origin main
git push origin v1.2.1
```

This runs `release.yml`, builds both artifacts, and creates the Release. After
the run completes, the website's download buttons resolve automatically. Note
that pushing/merging to `main` does **not** trigger a release build — only a
`v*` tag or a manual `workflow_dispatch` does. `pages.yml` redeploys the site
only when a push to `main` changes files under `site/**`.

The workflow fails before platform builds if the tag, `pubspec.yaml`, and
authored wiki note do not agree, if the Android build number is not greater than
all earlier tagged releases, or if signing/identity verification fails. Never
move an existing release tag or add its notes retrospectively.

### Android signing transition

Published APKs through `v1.2.0` used runner-local debug keys; their certificate
fingerprints differ, so Android rejects one as an update to another. `v1.2.1`
is prepared as the first permanent-signing baseline. Users of an older build
must uninstall it once before installing `v1.2.1`, which normally deletes that
installation's local app data. Starting from `v1.2.1`, every later release must
keep the application ID and pinned certificate and increase `versionCode` so
Android can update in place.

## 5. Known limitations

- The unsigned iOS `.ipa` **builds successfully in CI** (verified in `v1.2.0` on
  the macOS runner) but its on-device sideload/runtime has **not been verified**
  (the wider iOS runtime is also unverified — see
  [implementation status](02-implementation-status.md)). The release job is
  designed to still publish the Android APK if the iOS step fails.
- The `releases/latest/download/...` links and the site's live-release
  enhancement depend on at least one published `v*` release; `v1.2.0` satisfies
  this.
- CI actions emit a Node.js 20 deprecation warning (non-blocking).
- An in-place Android upgrade using the permanent certificate cannot be
  device-verified until both the `v1.2.1` baseline and a later signed APK exist.

## 6. Licensing & attribution

- Code: MIT License, `Copyright (c) 2026 Bernoulli Software`.
- Navigation earcons: Kenney **Interface Sounds 1.0**, CC0 1.0 Universal.
  `assets/audio/navigation/LICENSE.txt` records the source URL, original names,
  download date, and SHA-256 hashes for the two bundled OGG files. CC0 does not
  require attribution, but the provenance is retained for release auditing.
- Map data © OpenStreetMap contributors; in-app attribution requirements and the
  prohibition on bulk/offline use of `tile.openstreetmap.org` continue to apply
  (see [offline map implementation](06-offline-map-packages.md)).
