# Release Notes Index

Last reviewed: 2026-07-22

This page is the durable index and policy for RunTiyul release notes. Detailed,
authored notes live under [`releases/`](releases/) and are also used verbatim as
the corresponding GitHub Release body.

## Release-note contract

Every public release must, in the same commit that is tagged:

1. Update `pubspec.yaml` to the release semantic version and a monotonically
   increasing build number.
2. Add a non-empty `docs/wiki/releases/vMAJOR.MINOR.PATCH.md` whose filename
   exactly matches the Git tag.
3. Add the release to this index and update
   [Release & Distribution](07-release-and-distribution.md).
4. Update [the wiki index](INDEX.md) when release status, validation evidence,
   priorities, or the last-reviewed date changes.
5. Include user-visible highlights, fixes, validation actually performed,
   downloads/install notes, licensing changes, and unresolved limitations.
6. Run the documented validation and verify local Markdown links before tagging.

The release workflow enforces items 1 and 2 before starting Android or iOS
builds. A mismatched tag/version or missing/empty note file fails the release.
Do not create a tag first and write notes afterward.

## Releases

| Version | Date | Status | Summary |
| --- | --- | --- | --- |
| [v1.2.2](releases/v1.2.2.md) | 2026-07-22 | Prepared | Permanent Android release signing, CRLF-safe update gates, and installed-version awareness. |
| [v1.2.1](releases/v1.2.1.md) | 2026-07-22 | Unpublished | Tag workflow stopped at metadata validation because CRLF was not normalized; no artifacts or GitHub Release were published. Superseded by `v1.2.2`. |
| [v1.2.0](releases/v1.2.0.md) | 2026-07-18 | [Published](https://github.com/nachem/runTiyul/releases/tag/v1.2.0) | Offline tone/voice navigation alerts, alert previews, route-map visibility, and bottom-panel fixes. |

Earlier published releases predate the enforced authored-note contract and are
available in [GitHub Releases](https://github.com/nachem/runTiyul/releases).
