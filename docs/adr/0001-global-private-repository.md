# ADR 0001: Global Private Repository

## Status

Accepted

## Decision

Maintain Daniel Harness as the private `daniel-morales-dev/daniel-harness` repository. Install it globally rather than copying the full harness into each project. Store local configuration and secrets under `~/.config/daniel-harness/`.

## Consequences

- Shared behavior is versioned once.
- Project repositories retain only their own rules.
- Private visibility does not permit committing secrets.
- Runtime adapters must not make the decision core OpenCode-only.
