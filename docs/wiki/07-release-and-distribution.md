# Release & Distribution

Last reviewed: 2026-09-23

This page documents how RunTiyul is packaged, published, and marketed: the
public website, the release artifacts, and the CI that produces them. It
also records the public repository's contribution and security controls. It
distinguishes repository configuration from checks actually exercised by a
hosted run or release.

## 1. Summary

| Concern | Mechanism | Status |
| --- | --- | --- |
| Marketing/landing site | Static site in [`site/`](../../site/), deployed to GitHub Pages | Deployed and live at https://nachem.github.io/runTiyul/; run `30808751792` passed on 2026-08-03 |
| Android artifact | `RunTiyul.apk` published to GitHub Releases | Permanently signed `v1.4.3+13` published (62,741,316 bytes); package/version/certificate, provenance, checksum, and stable latest URL independently verified on 2026-09-22 |
| iOS artifact | `RunTiyul.ipa` (unsigned) published to GitHub Releases | `v1.4.3+13` published (16,036,646 bytes); checksum, provenance, and stable latest URL verified on 2026-09-22. On-device sideload remains unverified |
| Pull-request validation | Format, analyzer, test, and dependency-review jobs in `ci.yml` | Push run `35750005333` passed formatting, analysis, and the complete committed-source test suite with Flutter 3.44.6. Dependency review awaits a pull request |
| Release supply chain | SHA-pinned Actions, least-privilege tokens, fixed Flutter version, APK identity gate, checksums, and GitHub provenance | Release run `35750301499` passed signing/identity, checksums, APK+IPA provenance, and publication for `v1.4.3` |
| Community and security | Public policies/templates plus GitHub security settings | Community files implemented; private reporting, Dependabot alerts/security updates, secret scanning, and push protection enabled on 2026-08-01 |
| License | [MIT](../../LICENSE), © Bernoulli Software | Implemented |
| Repository visibility | Public | Implemented |

The download links used by the site and README point at stable asset names via
`https://github.com/nachem/runTiyul/releases/latest/download/RunTiyul.apk` and
`...RunTiyul.ipa`. As of the
[`v1.4.3` release](https://github.com/nachem/runTiyul/releases/tag/v1.4.3)
(2026-09-22), both return HTTP `200`. Release workflow
[`35750301499`](https://github.com/nachem/runTiyul/actions/runs/35750301499)
passed its metadata gate, permanent-signature Android identity verification,
unsigned iOS build, checksums, APK+IPA provenance, and publication jobs.
Independent downloads match `SHA256SUMS.txt`: APK
`d8cf6f549ae9890013c1e7f9c75b7c0eaf51ebd41f5c336c8a81b6e9f2d6a2a0`
(62,741,316 bytes) and IPA
`1a690c3f18fbeac2bbed32422b858441b7613b53d5cf748b6a570d2034713b30`
(16,036,646 bytes). Both build-provenance attestations verify against the
tagged release workflow, exact source commit, and GitHub-hosted runner policy.
The public APK reports package `com.bernoulli.trailrunner.trail_runner`,
`versionName=1.4.3`, `versionCode=13`, and the pinned permanent certificate.

### APK size audit (2026-09-22)

Read-only ZIP inspection of the verified public v1.4.3 APK measured 62,741,316
bytes: 62.74 decimal MB or 59.83 MiB. Most of the download is native code for
three CPU architectures, not maps or activity data:

| Packaged component | Stored MiB |
| --- | --- |
| ARM64 native libraries | 18.98 |
| ARMv7 native libraries | 16.78 |
| x86-64 native libraries | 20.43 |
| Flutter assets | 2.32 |
| Android image resources | 0.72 |
| Android DEX bytecode | 0.36 |

Flutter engine and compiled application libraries dominate the native entries.
The two non-ARM64 architectures account for 39,014,388 bytes (39.01 MB), useful
for broad device compatibility but unnecessary on an ARM64-only phone. Summing
ARM64 entries and shared content gives an estimated 23.62 MB payload, so an
architecture-specific release could be roughly 24 MB before further asset
optimization. This is an archive-derived estimate, not a built or installed
split APK. Distribution still publishes the unchanged universal APK; separate
per-ABI APKs or Play app-bundle delivery have not been implemented here.

The largest bundled asset is `assets/branding/app_icon.png` at 2.06 MiB. It is
used in the About dialog and for launcher generation, so a smaller display
variant or lossless image optimization is preferable to removal. The private
`backup.ab` file is not present in the APK. No source changes, dependency
removals, new build, or device storage inspection were performed for this audit.

Android **User data** is separate from APK size: downloaded maps, SQLite data,
and caches may contribute. `TrailNetworkCache` caps its routing-data disk cache
at 64 MiB / 256 tiles; that is a retention limit, not preallocated storage or
evidence of the actual bytes on a phone. A device storage breakdown is needed
to attribute a reported 64 MB specifically to User data rather than App size.

### 1.4.4 publication preparation

[v1.4.4+14](releases/v1.4.4.md) is prepared locally on 2026-09-22 with route
bend/T-junction fixes, nearby snapping and reported direct connections, and the
authorized Esri DEV picker/profile. All 331 tests and the full analyzer passed;
changed Dart files were formatted. The Android debug APK built with
`ALLOW_AUTHORIZED_VIEW_RASTER_DEV_DOWNLOADS=true`, without installation. This
debug artifact is not an in-place update for the permanent-signed release.
Signing identity, schema, provider licensing, and production defaults are
unchanged. The private backup remains excluded. No tag, push, publication,
signed release build, live-provider request, or device test was performed as
part of this preparation; v1.4.3 remains the latest public release.

On 2026-09-23, publication was requested after source commit `41ceb506` was
pushed. [CI 35765968661](https://github.com/nachem/runTiyul/actions/runs/35765968661)
and [CodeQL 35765967694](https://github.com/nachem/runTiyul/actions/runs/35765967694)
passed for that exact source. Release notes are being finalized before the
immutable tag is created; tagged builds and public artifact verification remain
pending. Ordinary release provider gates remain unchanged.

### 1.4.3 center-view release publication

[v1.4.3+13](releases/v1.4.3.md) was published on 2026-09-22. The release
changes the center-to-view icon to preserve zoom and adds a separate explicit
zoom-to-fit control. The shared map widget, related tests, release metadata,
and wiki are updated; the private backup remains excluded. Existing committed
download-editor changes in `c55f53c` are retained. An empty test file and unused
local from that commit were removed to resolve release validation blockers,
without restoring or changing that editor's behavior. All 28 focused tests and
312 full-suite tests pass; formatting checks all 101 Dart files and analysis
is clean. Commit `f32b5653efe8dda5605d2e80140d6f93f27204eb` was pushed to `main`,
passed [CI 35750005333](https://github.com/nachem/runTiyul/actions/runs/35750005333)
and [CodeQL 35750004979](https://github.com/nachem/runTiyul/actions/runs/35750004979),
then tagged `v1.4.3`. [Release run
35750301499](https://github.com/nachem/runTiyul/actions/runs/35750301499) passed
both platform builds and publication. Independent public checksum, Android
identity/signature, provenance, and latest-link verification passed. No physical
device was installed or tested. The tag remains fixed at that source commit.

### 1.4.2 recenter hotfix publication

Publication of [v1.4.2+12](releases/v1.4.2.md) completed on 2026-09-22 for
the delayed-startup recenter zoom regression. The release includes only the
camera fix, its regression tests, version metadata, and wiki updates. Separate
uncommitted download-screen/test edits and the private backup remain local.
The committed snapshot retains download permission checks and the full test
suite. Commit `11c83fc013882d87b2f8833601003cc645feb3e7` was pushed to `main`,
passed [CI 35745309481](https://github.com/nachem/runTiyul/actions/runs/35745309481)
and [CodeQL 35745308024](https://github.com/nachem/runTiyul/actions/runs/35745308024),
then tagged `v1.4.2`. [Release run
35745585108](https://github.com/nachem/runTiyul/actions/runs/35745585108) passed
both platform builds and publication. Independent public checksum, Android
identity/signature, provenance, and latest-link verification passed. No physical
device was installed or tested. The tag remains fixed at that source commit.

### Local 1.4.1 build

On 2026-09-22 the workspace version was advanced to `1.4.1+11` with
[authored notes](releases/v1.4.1.md). All 303 tests, formatting, and analysis
passed. `flutter build apk --release --no-pub` produced a permanent-signed APK;
Android SDK tools verified the application ID, version `1.4.1+11`, and pinned
release certificate. The 62,724,952-byte versioned local artifact is
`build/app/outputs/flutter-apk/RunTiyul-1.4.1.apk`, SHA-256
`a65c12b61cb1e03dbda322b21dfc94f458a7ba188353e4c8d797b655b766f2ab`.
That initial preparation did not publish or install the artifact. Publication
was requested and completed on 2026-09-22 through the existing tagged GitHub
Actions workflow, including the newer raster pacing/cooldown changes.
Final pre-publication checks passed all 305 tests, 102-file formatting, analysis,
release metadata, all 94 local Markdown targets, and whitespace.
Commit `fcf721fd7592cf3ddc98ca150cb549b1e1a36ecd` is pushed to `main` and tagged
`v1.4.1`. Hosted [Continuous integration
35740358839](https://github.com/nachem/runTiyul/actions/runs/35740358839) and
[CodeQL 35740358543](https://github.com/nachem/runTiyul/actions/runs/35740358543)
passed before the release tag was pushed. [Release workflow
35740728459](https://github.com/nachem/runTiyul/actions/runs/35740728459) passed,
followed by independent public checksum, Android identity/signature, provenance,
and stable-link verification. Public artifacts were rebuilt from the tagged
release commit rather than uploaded from this earlier local output. At that
point the latest published version was `v1.4.1+11`; no physical-device install
was performed.

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
- The footer links the privacy and security policies. Public copy must state
  that physical-device screen-lock, navigation-camera/recovery behavior, and
  iOS runtime verification remain pending.

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

- The unsigned iOS `.ipa` **builds successfully in CI** (verified in `v1.4.3` on
  the macOS runner) but its on-device sideload/runtime has **not been verified**
  (the wider iOS runtime is also unverified — see
  [implementation status](02-implementation-status.md)). The release job is
  designed to still publish the Android APK if the iOS step fails.
- The `releases/latest/download/...` links and the site's live-release
  enhancement depend on at least one published `v*` release; `v1.4.3` is the
  current latest release.
- CI actions emit a Node.js 20 deprecation warning (non-blocking).
- `v1.2.2` through `v1.4.3` provide permanently signed APKs suitable for an
  in-place upgrade test, but data preservation remains physical-device
  unverified.
- Push CI passed in run `35750005333`; CodeQL passed in run `35750004979`.
  Pull-request dependency review remains unexercised. `v1.4.3` independently
  verified the published checksum asset and both provenance attestations.
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
