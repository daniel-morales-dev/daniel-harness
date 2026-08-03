# Project Memory

## State

Phase 1 foundation is being implemented in the private `daniel-morales-dev/daniel-harness` repository. OpenCode is the first runtime; the decision core must remain portable.

## Invariants

- Harness is global; local config lives in `~/.config/daniel-harness/`.
- Gentle AI is subordinate and external: no fork and no generated-prompt edits.
- Repository scope is per task: `single-repo`, `related-repos`, or `multi-project`.
- Related repositories may be read and written in one task after reporting access.
- Never create a branch without asking.
- MySQL is always read-only.
- DynamoDB writes require exact confirmation.
- Tunnels are manual.
- Restricted models have no arbitrary shell or direct secret reads.
- CodeGraph is first for structural exploration.
- MCP capabilities are discovered rather than assumed.

## Context Rules

| Context | Key constraints |
|---|---|
| `alegra-monolith` | PHP 7.0.9, Zend Framework 1, minimal changes, syntax check with `docker exec alegra-app-php-1 php -l <file>`. |
| `alegra-microservice` | Node 24, TypeScript, Lambda/CDK, Clean Architecture, DDD, focused tests during iteration, 90% line and branch coverage for changed business logic. |
| `freelance` | Project rules first; K Agencia tunnels remain manual. |

## Migrated Assets

These Phase 1 files are copied without content changes:

| Target | Source | SHA-256 at migration |
|---|---|---|
| `agents/senior-engineer.md` | `~/.config/opencode/agents/senior-engineer.md` | `30dbb1827661345acc4a214eae99c5ccbea6ff4ea6df7e59c4b127426b081ba4` |
| `agents/code-reviewer.md` | `~/.config/opencode/agents/code-reviewer.md` | `1b5acdb457ad9621057c8bba3697307dbd6c612ea06ca9775ec87044d906a0c0` |
| `agents/test-engineer.md` | `~/.config/opencode/agents/test-engineer.md` | `73720259e88ff37f16452c841d199e8859e251473555ed0f977af1077e0658f3` |
| `skills/monolith-to-micro-migration/SKILL.md` | microservice `.opencode/skills/monolith-to-micro-migration/SKILL.md` | `e288b645ea446696fc6628d8a1623f4be0e70a9fc8dd2d94a2be6639b2dda997` |
| `commands/migration-gap-analysis.md` | monolith `.opencode/commands/migration-gap.md` | `6ab1df3564c0e109c55c5e6e81f129815768d7e7b1a2aead50fdd12240803898` |

The command target name is normalized to the requested public name; its content remains unchanged.

## Security State

- A previously hardcoded GitHub bearer token must be considered compromised, rotated, and externalized.
- A local, untracked monolith guide contains literal credentials and an operational key. Values were not copied. Remediation is separate from this repository.
- Current OpenCode permission isolation has not been proven; shell can bypass direct-read denial.

## Documentation Findings

Project docs contain stale or conflicting claims about deletion semantics, Kafka tombstones, configuration, test gates, and migration status. Treat project-specific docs as evidence to verify, not policies to copy globally.

## Open Questions

- Exact proprietary-code policy for restricted/free models.
- MongoDB mutation policy for K Agencia.
- Concrete tools and trust boundary of `alegra-test`.
- Final implementation language for the portable core.
- Final OpenCode installation mechanism after Phase 1 symlink experience.
