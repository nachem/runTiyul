# RunTiyul Wiki

This wiki is the durable project context for developers and AI coding
assistants. It separates product intent from code that actually exists.

Start with the dedicated [wiki index](INDEX.md). It contains the current
implementation summary, document catalog, priorities, and mandatory index
maintenance contract.

## Reading order

1. [Wiki index](INDEX.md)
   - Records current status and directs all future documentation maintenance.
2. [Product requirements](01-product-requirements.md)
   - Defines the product, scope, behavior, constraints, and acceptance criteria.
3. [Implemented details and current status](02-implementation-status.md)
   - Records only behavior verified in the repository.
4. [Target architecture](03-target-architecture.md)
   - Defines the intended module boundaries, data model, and technical design.
5. [AI assistant development guide](04-ai-assistant-guide.md)
   - Gives future assistants a safe implementation and verification workflow.
6. [Local run and debug guide](05-local-debugging.md)
   - Explains local setup, launch, GPS simulation, and offline verification.
7. [Long-term offline map package implementation](06-offline-map-packages.md)
   - Defines the proposed legal PMTiles/MBTiles supply chain, mobile migration,
     validation, and rollout plan.
8. [Release and distribution](07-release-and-distribution.md)
   - Documents artifact CI, publishing, install links, and the release runbook.
9. [Release notes](08-release-notes.md)
   - Indexes authored per-version notes and defines the mandatory release gate.

## Source-of-truth rules

When documents disagree, use this priority:

1. The latest explicit user instruction.
2. `01-product-requirements.md` for intended product behavior.
3. Source code and automated tests for implemented behavior.
4. `02-implementation-status.md` as a human-readable snapshot of that code.
5. `03-target-architecture.md` for design direction that is not implemented yet.

Do not interpret a dependency in `pubspec.yaml`, an item in the target
architecture, or a requirement as proof that a feature has been implemented.

## Documentation maintenance

Every feature change should update:

- `INDEX.md` when feature status, priorities, decisions, validation, or the wiki
  catalog changes.
- Requirement status and acceptance criteria when product behavior changes.
- Implementation status when code is added, removed, or validated.
- Architecture when module boundaries or persistence formats change.
- Setup instructions when tooling, permissions, or platform support changes.
- Release notes and the release index whenever a version is prepared or
   published.

Use absolute dates in status notes. Avoid vague descriptions such as "recently"
or "almost finished."
