# Instructions for Coding Agents

These instructions apply to every AI coding assistant and automated agent
working anywhere in this repository.

GitHub Copilot-specific repository instructions are also available at its
standard location,
[`.github/copilot-instructions.md`](.github/copilot-instructions.md).

## Mandatory wiki workflow

Before making changes:

1. Read [`docs/wiki/INDEX.md`](docs/wiki/INDEX.md).
2. Follow its reading order and source-of-truth rules.
3. Inspect the source code and tests relevant to the task.

Before declaring any task complete:

1. Update the relevant files under `docs/wiki/` when requirements,
   implementation, architecture, setup, validation, or known limitations
   changed.
2. Update [`docs/wiki/INDEX.md`](docs/wiki/INDEX.md) whenever:
   - A wiki page is added, removed, renamed, or changes purpose.
   - A feature changes implementation status.
   - The current milestone, next priority, or an open decision changes.
   - Validation evidence or the wiki's last-reviewed date changes.
3. Keep the index concise. Put detailed content in the appropriate wiki page
   and link to it from the index.
4. Verify every local Markdown link after documentation changes.
5. Never mark a feature implemented based only on plans, dependencies, generated
   files, or untested code.

Code and automated tests are the source of truth for implemented behavior.
The wiki must accurately summarize that behavior for future agents.

## Documentation standards

- Use absolute dates in `YYYY-MM-DD` format.
- Separate required, implemented, partially implemented, and unimplemented
  behavior.
- Record commands actually run and their results; do not infer validation.
- Document unresolved limitations and production-readiness concerns.
- Do not commit secrets, provider credentials, or personal location data.
- Do not create planning documents outside the established wiki unless the user
  explicitly requests one. Extend the existing pages instead.

## Completion checklist

- [ ] Requested behavior is implemented completely.
- [ ] Relevant tests and analysis pass.
- [ ] Real-device limitations are stated where device validation was required.
- [ ] Relevant wiki pages are synchronized with the code.
- [ ] `docs/wiki/INDEX.md` is synchronized with the wiki and project status.
- [ ] Local Markdown links resolve.
