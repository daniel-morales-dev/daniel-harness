# Agent Instructions

This repository defines the stable foundation for Daniel Harness.

## Start Here

1. Read `docs/project-memory.md`.
2. Read relevant records under `docs/adr/`.
3. Read the policy for the surface being changed.
4. Use CodeGraph before broad code exploration when it is available.

## Precedence

1. Explicit user instruction.
2. This repository's `AGENTS.md`.
3. Context policy.
4. Global policy.
5. Conservative default.

## Boundaries

- Never read, print, copy, or commit real secrets.
- Never treat a private repository as secret storage.
- Do not edit Gentle AI generated prompts, agents, or artifacts.
- Do not modify migrated Phase 1 assets unless a task explicitly targets them.
- Do not create a branch without asking first.
- Do not edit production OpenCode configuration automatically.
- Keep comments in Spanish when they explain a non-obvious technical decision; omit obvious comments.

## Changes

- Prefer the smallest correct change.
- Keep one writer per shared surface.
- Run focused tests and lint checks for the changed files.
- Use synthetic fixtures only; never test against real local configuration.
- Conventional Commit headers use an English type, a Spanish description, and at most 120 characters.
- Commit, push, and deploy only when the user's project-specific authorization allows it.

## Repository Assets

Files under `agents/`, `skills/monolith-to-micro-migration/`, and `commands/migration-gap-analysis.md` were migrated unchanged in Phase 1. Their source mapping and checksums are recorded in `docs/project-memory.md`.
