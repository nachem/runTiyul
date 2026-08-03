# Privacy Policy

Effective date: 2026-08-01

RunTiyul is an offline-first, open-source trail-running application maintained
by Bernoulli Software. It is designed to keep route and activity history on the
user's device.

## Summary

- No RunTiyul account is required.
- The project does not operate analytics, advertising, telemetry, or a cloud
  service that receives activity history.
- Routes, recorded GPS samples, activity summaries, settings, and downloaded
  maps are stored locally by default.
- RunTiyul does not sell personal data or upload GPS tracks to the maintainer.
- Map and elevation providers receive ordinary network requests when online
  content is viewed or downloaded. Requested tile coordinates can approximate
  the area being viewed or prepared for offline use.

## Data Stored on the Device

Depending on the features used, RunTiyul stores:

- Imported and manually created routes, including coordinates and optional
  elevation or timestamps.
- Recorded activities and GPS samples, including coordinates, time, accuracy,
  and optional altitude, speed, and heading.
- Downloaded map tiles, offline-area boundaries, download status, and storage
  metadata.
- App settings and the locally acknowledged app version.

This data remains in the application's private storage unless the user exports
a GPX file through the platform file picker. Exported files are controlled by
the user and the selected destination or sharing application.

Users can delete individual routes, activities, and offline areas in the app.
Clearing app data or uninstalling the app normally removes its private local
data, subject to operating-system backup and deletion behavior.

## Permissions

RunTiyul may request:

- Precise or approximate location to show position, follow a route, and record
  an activity.
- Background location and foreground-service or notification access when the
  user starts functionality that must continue while the app is backgrounded.
- File-picker access when the user imports or exports GPX data.
- Network access for online maps and user-initiated offline-map downloads.

Permissions are controlled through the device settings. Denying a permission
limits the related feature but does not create a RunTiyul account or upload
location history.

## Network Requests and Third Parties

When online map content is used, the selected map provider receives standard
request information such as IP address, user agent, requested tile coordinates,
and request time. Converted-vector offline maps can also request vector map
tiles and transient elevation tiles while the selected area is being prepared.
The exact services depend on the configured provider and selected map layer;
the current built-in options are documented in the
[implementation status](docs/wiki/02-implementation-status.md).

RunTiyul does not send the recorded activity database or complete GPX tracks to
these providers. Nevertheless, a sequence of tile requests can reveal an area
of interest. Users who require network privacy should download needed content
over a network they trust and use the app offline afterward.

System text-to-speech and bundled navigation tones are used for guidance. The
application requests an installed offline voice and does not intentionally send
navigation prompts or coordinates to a speech service.

Third-party services process their own request logs under their respective
policies. RunTiyul does not control those retention practices.

## Project Website

The project website is hosted by GitHub Pages. It requests web fonts from
Google Fonts and queries the public GitHub Releases API to display current
release information. Those providers receive normal web request metadata. The
site stores the selected color theme in browser local storage and does not run
project-controlled analytics or advertising.

## Security, Support, and Changes

Use the private channel in [SECURITY.md](SECURITY.md) for a vulnerability or a
privacy issue that includes sensitive details. General privacy questions can be
asked through the channels in [SUPPORT.md](SUPPORT.md), but personal location
data should never be posted publicly.

Material changes to this policy will be committed to the public repository with
an updated effective date. The repository history preserves earlier versions.