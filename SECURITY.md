# Security Policy

RunTiyul handles location data and produces installable mobile artifacts. Please
report suspected vulnerabilities privately so they can be investigated before
details put users at risk.

## Supported Versions

| Version | Security support |
| --- | --- |
| Latest release on [GitHub Releases](https://github.com/nachem/runTiyul/releases/latest) | Supported |
| Current `main` branch | Reports accepted; fixes ship in a future release |
| Older releases | Not supported; reproduce against the latest release when possible |

The published iOS artifact is unsigned and has not been verified on a physical
device. See the [implementation status](docs/wiki/02-implementation-status.md)
for current platform limitations.

## Report a Vulnerability

Do not open a public issue or discussion. Use GitHub's
[private vulnerability reporting form](https://github.com/nachem/runTiyul/security/advisories/new).
GitHub labels the entry point **Report a vulnerability** on the repository's
**Security** tab.

Include as much of the following as you can:

- The affected release, commit, platform, and installation source.
- The impact and a realistic attack scenario.
- Minimal, reproducible steps or a proof of concept.
- Any conditions or permissions required for exploitation.
- A suggested remediation, if known.
- Your disclosure and credit preferences.

Use synthetic data. Never include real GPS tracks, home or activity locations,
provider credentials, signing material, access tokens, or other people's
personal data. Attach sensitive evidence only to the private advisory.

## What to Expect

The maintainer aims to:

- Acknowledge a report within 7 calendar days.
- Provide an initial severity and scope assessment within 14 calendar days.
- Keep the reporter informed when the status materially changes.
- Coordinate a fix, release, and GitHub Security Advisory before public
  disclosure when the report is valid.

These are response targets, not service-level guarantees. Timing depends on
severity, reproducibility, platform-release constraints, and maintainer
availability. This project does not currently operate a paid bug-bounty
program.

## Scope

Reports are welcome for the application source, local data handling, GPX
import/export, map and download networking, GitHub Actions workflows, release
artifacts, update identity, and the project-controlled website.

For vulnerabilities in Flutter, a dependency, a map provider, GitHub, Android,
or iOS, report the issue to that upstream project as well. General bugs,
feature requests, provider outages, and already documented device-validation
limitations belong in the public issue tracker unless they have a concrete
security impact.

## Responsible Research and Disclosure

- Test only with systems, devices, accounts, and data you own or are authorized
  to use.
- Do not disrupt services, degrade public map providers, access other users'
  data, or perform social engineering.
- Stop testing and report immediately if you encounter personal location data,
  credentials, or signing material.
- Give the maintainer a reasonable opportunity to investigate and release a
  fix before publishing technical details.

The project will not pursue action for good-faith research that follows this
policy, to the extent the maintainer controls such action.