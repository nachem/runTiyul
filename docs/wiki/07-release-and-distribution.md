# Release & Distribution

Last reviewed: 2026-07-16

This page documents how RunTiyul is packaged, published, and marketed: the
public website, the release artifacts, and the CI that produces them. It
describes what is **implemented in the repository**, not planned work.

## 1. Summary

| Concern | Mechanism | Status |
| --- | --- | --- |
| Marketing/landing site | Static site in [`site/`](../../site/), deployed to GitHub Pages | Implemented; not yet deployed (needs Pages source + branch merge) |
| Android artifact | `RunTiyul.apk` published to GitHub Releases | Workflow implemented; no release tagged yet |
| iOS artifact | `RunTiyul.ipa` (unsigned) published to GitHub Releases | Workflow implemented; macOS build not yet run/verified |
| License | [MIT](../../LICENSE), © Bernoulli Software | Implemented |
| Repository visibility | Public | Implemented |

The download links used by the site and README point at stable asset names via
`https://github.com/nachem/RunTiyul/releases/latest/download/RunTiyul.apk` and
`...RunTiyul.ipa`. These 404 until the first `v*` release has been built.

## 2. Website (`site/`)

- Static, dependency-free landing page: `index.html`, `styles.css`, `main.js`,
  plus `.nojekyll`, `robots.txt`, `sitemap.xml`, and optimized assets under
  `site/assets/`.
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

Deployed URL (once Pages is enabled): `https://nachem.github.io/RunTiyul/`.

## 3. CI workflows

### `.github/workflows/release.yml`

- **Triggers:** pushed tag matching `v*`, or manual `workflow_dispatch`.
- **Android job (Ubuntu):** `flutter build apk --release`, renamed to
  `RunTiyul.apk`.
- **iOS job (macOS):** `flutter build ios --release --no-codesign`, then the
  `Runner.app` is zipped into a `Payload/` structure to produce an **unsigned**
  `RunTiyul.ipa`. No Apple signing secrets are used.
- **Publish:** both assets are attached to a GitHub Release via
  `softprops/action-gh-release@v2` (needs `permissions: contents: write`). The
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

One-time setup:

1. Repository must be **public** (done).
2. Enable Pages: _Settings → Pages → Build and deployment → Source: **GitHub
   Actions**_.

To publish a release:

```powershell
git tag v1.0.0
git push origin v1.0.0
```

This runs `release.yml`, builds both artifacts, and creates the Release. After
the run completes, the website's download buttons resolve automatically.

## 5. Known limitations

- The unsigned iOS `.ipa` build on the macOS runner has **not been executed or
  verified**; it may require adjustment (the wider iOS runtime is also
  unverified — see [implementation status](02-implementation-status.md)). The
  release job is designed to still publish the Android APK if this step fails.
- Pages does not deploy until `pages.yml` is present on `main`.
- The site's live-release enhancement and the `releases/latest/download/...`
  links depend on at least one published `v*` release.

## 6. Licensing & attribution

- Code: MIT License, `Copyright (c) 2026 Bernoulli Software`.
- Map data © OpenStreetMap contributors; in-app attribution requirements and the
  prohibition on bulk/offline use of `tile.openstreetmap.org` continue to apply
  (see [offline map implementation](06-offline-map-packages.md)).
