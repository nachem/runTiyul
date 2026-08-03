# Contributing to RunTiyul

Thank you for helping improve RunTiyul. Contributions can include code,
documentation, testing on real devices, design, accessibility work, and map
provider or licensing research.

By participating, you agree to follow the
[Code of Conduct](CODE_OF_CONDUCT.md). Report vulnerabilities through the
[security policy](SECURITY.md), not a public issue.

## Before You Start

- Search [open issues](https://github.com/nachem/runTiyul/issues) and
  [discussions](https://github.com/nachem/runTiyul/discussions) first.
- Open an issue or discussion before a large feature, dependency change,
  persistence migration, provider change, or architecture change.
- Keep location data private. Use synthetic GPX tracks and coordinates in code,
  tests, screenshots, logs, and issues.
- Do not use public OpenStreetMap or CyclOSM tile services for production bulk
  or offline downloads.

The product requirements and verified implementation state live in the
[project wiki](docs/wiki/INDEX.md). Source and automated tests are authoritative
for implemented behavior.

## Development Setup

RunTiyul requires Flutter stable with Dart SDK `^3.12.2`. Flutter 3.44.6 is the
currently validated toolchain. Android development works on Windows, macOS, and
Linux; iOS builds require macOS and Xcode.

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d <device-id>
```

See the [local run and debug guide](docs/wiki/05-local-debugging.md) for device,
permission, GPS simulation, and offline-map instructions.

## Make a Change

1. Fork the repository and create a focused branch from `main`.
2. Identify the relevant requirement IDs in
   [Product Requirements](docs/wiki/01-product-requirements.md) when behavior
   changes.
3. Add or update tests for behavior and failure paths.
4. Keep changes focused and preserve offline-first behavior, explicit errors,
   type safety, location privacy, and provider licensing.
5. Update the appropriate wiki pages when implementation, setup, validation,
   architecture, limitations, or priorities change.
6. Run the validation commands below and open a pull request.

## Validate Your Change

At minimum, run:

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
flutter test --no-pub
```

Also run the relevant platform build or device test for platform, plugin,
permission, GPS, background-execution, file-picker, audio, or map-rendering
changes. Do not claim iOS or physical-device verification unless you actually
performed it.

For documentation changes, verify that every changed local Markdown link
resolves. Record only commands and checks you actually ran.

## Pull Requests

Keep each pull request reviewable and describe:

- The problem and the chosen solution.
- Requirement IDs affected, when applicable.
- Validation performed and its results.
- Device and operating-system versions used for runtime checks.
- Privacy, permission, provider-policy, persistence, and release implications.
- Remaining limitations or follow-up work.

Include screenshots or a short recording for visible UI changes, with all
personal location data removed. Maintainers may ask for changes before merge.

Unless explicitly stated otherwise, contributions are provided under the
repository's [MIT License](LICENSE).