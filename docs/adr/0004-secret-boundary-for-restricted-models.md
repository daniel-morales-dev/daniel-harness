# ADR 0004: Secret Boundary for Restricted Models

## Status

Accepted

## Decision

Restricted models receive neither direct secret reads nor arbitrary host shell. They use closed tools that own credential access, validate operations, enforce policy, and sanitize results.

## Context

File-read denial alone is bypassable through Bash, interpreters, database clients, and similar tools. RTK compresses output but does not enforce access.

## Consequences

- Existing OpenCode configuration cannot be described as isolated until audited and changed.
- Productive data adapters must expose narrow operations rather than generic command execution.
- Phase 1 documents and diagnoses this boundary without automatically changing production configuration.
