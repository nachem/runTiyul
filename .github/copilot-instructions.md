# GitHub Copilot Repository Instructions

Use the project wiki as the required context for every coding task in this
repository.

## Before changing code

1. Read [`AGENTS.md`](../AGENTS.md).
2. Read [`docs/wiki/INDEX.md`](../docs/wiki/INDEX.md).
3. Follow the index's required reading order:
   - Product requirements for intended behavior and acceptance criteria.
   - Implementation status for the verified current state.
   - Target architecture for technical direction.
   - AI assistant guide for implementation and validation workflow.
4. Inspect the actual source and tests related to the request.

If `AGENTS.md` or any required wiki file is inaccessible, stop and notify the
user before proceeding with any code changes.

Do not assume that a requirement, planned architecture, dependency, or generated
file is implemented. Source code and automated tests are authoritative for
implemented behavior.

## While implementing

- Reference requirement IDs when adding or changing product behavior.
- Follow the architecture guide. Deviate only when the guide explicitly cannot
  satisfy the task's requirements (e.g., a required API or pattern is
  incompatible); document the reason and update the architecture documentation
  in the same change.
- Preserve offline-first behavior, explicit error handling, type safety,
  location privacy, and map provider licensing constraints.
- Never use the public `tile.openstreetmap.org` service for production bulk or
  offline downloads.
- Add or update tests and run the relevant Flutter validation commands.
- Do not commit secrets, map-provider credentials, or personal location data.

## Before completing a task

Update the wiki in the same change whenever the work affects requirements,
implementation status, architecture, setup, validation evidence, limitations,
priorities, or open decisions.

Always update [`docs/wiki/INDEX.md`](../docs/wiki/INDEX.md) when:

- A wiki page is added, removed, renamed, or changes purpose.
- A feature's implementation status changes.
- The current milestone, next priority, or an open decision changes.
- Validation evidence changes.
- The wiki is reviewed or its last-reviewed date needs updating.

Keep the index concise and place details in the appropriate wiki guide. Use
absolute `YYYY-MM-DD` dates, report only validation actually performed, and
verify all local Markdown links after documentation changes.
