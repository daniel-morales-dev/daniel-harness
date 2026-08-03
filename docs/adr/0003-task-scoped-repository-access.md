# ADR 0003: Task-Scoped Repository Access

## Status

Accepted

## Decision

Determine repository scope from the task rather than the initial directory. Support `single-repo`, `related-repos`, and exceptional `multi-project` scopes. Report read/write repositories before editing; related-repository access does not require an extra authorization prompt.

## Consequences

- Monolith-to-micro work can read the monolith and write the micro directly.
- The main session must maintain an explicit access map.
- Independent repositories are not pulled into scope speculatively.
