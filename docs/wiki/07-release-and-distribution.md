# Release & Distribution

Last reviewed: 2026-08-03

This page documents how RunTiyul is packaged, published, and marketed: the
public website, the release artifacts, and the CI that produces them. It
also records the public repository's contribution and security controls. It
distinguishes repository configuration from checks actually exercised by a
hosted run or release.

## 1. Summary

| Concern | Mechanism | Status |
| --- | --- | --- |
| Marketing/landing site | Static site in [`site/`](../../site/), deployed to GitHub Pages | Deployed and live at https://nachem.github.io/runTiyul/; run `30808751792` passed on 2026-08-03 |
| Android artifact | `RunTiyul.apk` published to GitHub Releases | Permanently signed `v1.3.0+8` published (62,085,540 bytes); package/version/certificate independently verified and latest-download link returned 200 on 2026-07-27 |
| iOS artifact | `RunTiyul.ipa` (unsigned) published to GitHub Releases | `v1.3.0+8` published (15,857,479 bytes); latest-download link returned 200 on 2026-07-27. On-device sideload remains unverified |
| Pull-request validation | Format, analyzer, test, and dependency-review jobs in `ci.yml` | Push run `30808751609` passed format/analyze/test with Flutter 3.44.6; dependency review awaits a pull request |
| Release supply chain | SHA-pinned Actions, least-privilege tokens, fixed Flutter version, APK identity gate, checksums, and GitHub provenance | Signing and identity gate verified for `v1.3.0`; checksum/provenance additions await the next release |
| Community and security | Public policies/templates plus GitHub security settings | Community files implemented; private reporting, Dependabot alerts/security updates, secret scanning, and push protection enabled on 2026-08-01 |
| License | [MIT](../../LICENSE), © Bernoulli Software | Implemented |
| Repository visibility | Public | Implemented |

The download links used by the site and README point at stable asset names via
`https://github.com/nachem/runTiyul/releases/latest/download/RunTiyul.apk` and
`...RunTiyul.ipa`. As of the
[`v1.3.0` release](https://github.com/nachem/runTiyul/releases/tag/v1.3.0)
(2026-07-27), both resolve `200`. Release workflow
[`30255797959`](https://github.com/nachem/runTiyul/actions/runs/30255797959)
passed its metadata gate, permanent-signature Android identity verification,
unsigned iOS build, and publication jobs. Independent downloads match the
GitHub-reported SHA-256 digests: APK
`341c038a3514df921fb2b2647101b24cd31b2601166501092e61a21191314496`
and IPA
`d5fe1f765ee31b2de71027536dfb3acdb04fd7f1f513db0e0a8d0253c0181601`.
The public APK reports package `com.bernoulli.trailrunner.trail_runner`,
`versionName=1.3.0`, `versionCode=8`, and the pinned permanent certificate.

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
- The footer links the privacy and security policies. Public copy states that
  physical-device screen-lock and iOS runtime verification remain pending and
  does not claim the unimplemented course-up mode.

Deployed URL (once Pages is enabled): `https://nachem.github.io/runTiyul/`.

## 3. Repository automation and community health

### `.github/workflows/ci.yml`

- **Triggers:** pull requests, pushes to `main`, and manual dispatch.
- **Flutter validation:** pins Flutter 3.44.6, installs locked dependencies,
  checks Dart formatting, runs `flutter analyze --no-pub`, and executes
  `flutter test --no-pub`.
- **Dependency review:** pull requests are checked with GitHub's dependency
  review Action for newly introduced vulnerable dependencies.
- **Safety:** read-only repository permission, non-persisted checkout
  credentials, concurrency cancellation for superseded runs, job timeouts, and
  immutable Action commit SHAs.

The equivalent local format, analyzer, and test commands passed on 2026-08-01,
and checksum-verified `actionlint` 1.7.12 passed. Hosted push run
[`30808751609`](https://github.com/nachem/runTiyul/actions/runs/30808751609)
then passed setup, dependency installation, formatting, analysis, and tests on
2026-08-03. Dependency review correctly skipped for that push and remains to be
verified on a pull request.

### `.github/workflows/release.yml`

- **Triggers:** pushed tag matching `v*`, or manual `workflow_dispatch`.
- **Metadata gate:** before any platform build, strict `vMAJOR.MINOR.PATCH` must
  match the semantic version in `pubspec.yaml`, and a non-empty matching note at
  `docs/wiki/releases/<tag>.md` must exist.
- **Toolchain and Actions:** Flutter is pinned to validated version 3.44.6;
  third-party Actions use immutable commit SHAs; checkout credentials are not
  persisted. Workflow-level access is read-only, and only the publish job gets
  release and provenance write permissions.
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
- **Publish:** the publish job generates `SHA256SUMS.txt`, attests available app
  artifacts with GitHub build provenance, and attaches them through a pinned
  release Action. The matching wiki release-note file is used verbatim as the
  Release body. The job runs whenever the Android APK succeeds and attaches the
  iOS `.ipa` only when that best-effort macOS build produced one, so a failing
  iOS build never blocks the APK release.
- Stable asset names are required so `releases/latest/download/...` links stay
  valid across releases.

### `.github/workflows/pages.yml`

- **Triggers:** push to `main` touching `site/**`, or manual dispatch.
- **Deploy:** `actions/configure-pages` → `upload-pages-artifact` →
  `deploy-pages`, publishing the `site/` directory. All Actions are SHA-pinned
  and checkout credentials are not persisted.

### Dependency and repository security

- `dependabot.yml` checks Dart packages, GitHub Actions, and Android Gradle
  dependencies weekly; referenced triage labels exist in the repository.
- GitHub private vulnerability reporting is enabled and is the confidential
  channel linked from `SECURITY.md` and the issue chooser.
- Dependabot vulnerability alerts and automated security updates are enabled.
- Secret scanning and secret push protection are enabled.
- Authenticated checks on 2026-08-01 found zero open Dependabot alerts and zero
  open secret-scanning alerts. GitHub's dependency graph inventories 161
  packages and can produce an SPDX SBOM.
- `main` has no branch protection or repository ruleset as of 2026-08-01. Add
  required CI checks only after `ci.yml` has merged and completed successfully.

### Community files

The repository root contains contribution, privacy, security, support, license,
and conduct policies. `.github/` provides CODEOWNERS, structured bug and feature
forms, issue-routing links, and a pull-request checklist. The website and README
link the privacy and security policies. Reports are explicitly told not to
include personal GPS data or credentials.

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

To publish a release (example `v1.2.2`):

1. Choose the next semantic version and a monotonically increasing Flutter
  build number.
2. Update `pubspec.yaml` (for example `version: 1.2.2+7`).
3. Add `docs/wiki/releases/v1.2.2.md`, update the
  [release-notes index](08-release-notes.md), and synchronize this page and
  `INDEX.md`.
4. Run formatting, analyzer, tests, the relevant platform build, and local wiki
  link validation.
5. Commit the complete release state, then tag and push that exact commit:

```powershell
git tag v1.2.2
git push origin main
git push origin v1.2.2
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
fingerprints differ, so Android rejects one as an update to another. The
`v1.2.1` tag produced no artifacts because its metadata job did not normalize
CRLF; it remains an immutable unpublished tag. `v1.2.2` is the first
published permanent-signing baseline. Users of an older build must uninstall it
once before installing `v1.2.2`, which normally deletes that installation's
local app data. Starting from `v1.2.2`, every later release must keep the
application ID and pinned certificate and increase `versionCode` so Android can
update in place.

## 5. Known limitations

- The unsigned iOS `.ipa` **builds successfully in CI** (verified in `v1.2.0` on
  the macOS runner) but its on-device sideload/runtime has **not been verified**
  (the wider iOS runtime is also unverified — see
  [implementation status](02-implementation-status.md)). The release job is
  designed to still publish the Android APK if the iOS step fails.
- The `releases/latest/download/...` links and the site's live-release
  enhancement depend on at least one published `v*` release; `v1.3.0` is the
  current latest release.
- CI actions emit a Node.js 20 deprecation warning (non-blocking).
- `v1.2.2` and `v1.3.0` now provide both permanently signed APKs needed for an
  in-place upgrade test, but data preservation remains physical-device
  unverified.
- Push CI passed in run `30808751609`. Pull-request dependency review remains
  unexercised. The checksum asset and provenance attestation are configured but
  have not run; the current `v1.3.0` release predates those additions.
- `main` is not protected by a branch rule or ruleset. Although GitHub's
  dependency graph can produce an SPDX SBOM, no SBOM or aggregated
  dependency-license inventory is currently published with releases.

## 6. Licensing & attribution

- Code: MIT License, `Copyright (c) 2026 Bernoulli Software`.
- Navigation earcons: Kenney **Interface Sounds 1.0**, CC0 1.0 Universal.
  `assets/audio/navigation/LICENSE.txt` records the source URL, original names,
  download date, and SHA-256 hashes for the two bundled OGG files. CC0 does not
  require attribution, but the provenance is retained for release auditing.
- Map data © OpenStreetMap contributors; in-app attribution requirements and the
  prohibition on bulk/offline use of `tile.openstreetmap.org` continue to apply
  (see [offline map implementation](06-offline-map-packages.md)).
