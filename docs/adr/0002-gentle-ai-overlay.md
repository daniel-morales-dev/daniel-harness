# ADR 0002: Gentle AI Overlay

## Status

Accepted

## Decision

Use Gentle AI as the external SDD engine for large and critical changes. Daniel Harness selects when to invoke it through a stable adapter and does not fork Gentle AI or modify generated prompts and agents.

## Consequences

- Gentle AI upgrades remain independent.
- Harness policy and context resolution stay under Daniel's control.
- The adapter must depend on documented behavior, not volatile internal files.
