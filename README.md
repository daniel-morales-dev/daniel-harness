# Daniel Harness

Daniel Harness is a private, global agentic-coding control layer for Daniel Morales. It sits above OpenCode and Gentle AI to resolve project context, repository scope, task risk, model trust, available capabilities, workflow, delegation, and verification.

This repository is the versioned foundation. Local configuration and credentials live outside it under `~/.config/daniel-harness/`.

## Status

Phase 1 establishes policies, schemas, examples, migrated agent assets, diagnostics, and safe installation. The executable context router and production data adapters are intentionally deferred.

## Architecture

```text
Request
  -> Daniel Harness preflight
     -> context and repository scope
     -> size and risk classification
     -> project and model-trust policies
     -> MCP/tool capability routing
     -> workflow selection
        -> direct
        -> OpenCode Plan/Build
        -> Gentle AI SDD
        -> migration workflow
```

See `docs/architecture.md` and `docs/adr/` for the stable decisions.

## Supported Contexts

- Alegra monolith: PHP 7.0.9 and Zend Framework 1.
- Alegra microservices: Node.js 24, TypeScript, Lambda/CDK, DynamoDB, Kafka, Clean Architecture, and DDD.
- Monolith-to-micro migrations across related repositories.
- Freelance projects, initially K Agencia.

## Install

```bash
./scripts/install.sh
```

The installer creates local configuration directories with restrictive permissions, copies example configuration only when a local file is absent, and links missing OpenCode assets. It does not edit `opencode.json` or overwrite existing files.

Restart OpenCode after installation so it can discover new agents, skills, and commands.

To remove only links created by this repository:

```bash
./scripts/uninstall.sh
```

Local configuration and secrets are preserved during uninstall.

## Diagnostics

```bash
./scripts/doctor.sh
./scripts/redact-opencode-config.sh /explicit/path/to/opencode.json > opencode.redacted.json
```

`doctor.sh` is read-only. The redactor writes only to standard output and never changes its input.

Schema tests use the pinned development dependencies in `requirements-dev.txt`; installation is explicit and is not performed by `install.sh`.

## Gentle AI

Gentle AI remains the SDD engine for large and critical changes. Daniel Harness invokes it through an external contract; this repository does not fork Gentle AI, edit generated prompts, or depend on volatile internals.

## Security

- A private repository is not a secret vault.
- Keep config in `~/.config/daniel-harness/` and credentials under its `secrets/` directory.
- Restricted models must not receive arbitrary shell access or direct secret reads.
- Rotate any credential that was ever hardcoded or shared in plaintext.
- Never commit raw OpenCode configuration containing headers, environment values, or tokens.

See `SECURITY.md` and `docs/security-model.md`.

## Private Use

This is a personal, private repository. No public license is granted. External use, redistribution, or relicensing requires an explicit later decision by the owner.

Contributions currently follow Daniel's private workflow and the rules in `AGENTS.md`.
