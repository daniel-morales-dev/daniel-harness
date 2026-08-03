# MCP Capability Registry

The registry is capability-driven and discovered at runtime. This table is the known starting inventory, not a hardcoded source of truth.

| Server | Expected state | Capabilities | Sensitive configuration |
|---|---|---|---|
| `codegraph` | Connected | Structure, symbols, references, call paths, impact. | No credentials expected in output. |
| `context7` | Connected | Current public library documentation. | Service authentication remains runtime-owned. |
| `engram` | Connected | Persistent observations and SDD artifacts. | Stored content must exclude secrets. |
| `github` | Connected | Repositories, issues, PRs. | Authentication must be externalized. |
| `linear` | Connected | Issues, comments, statuses, relations. | Tokens remain outside repository. |
| `wiki-alegra` | Connected | Internal documentation. | Internal content follows project trust rules. |
| `sentry` | Authentication required | Error and event diagnosis. | Never expose auth headers. |
| `alegra-test` | Present, tools unknown | Discover before routing. | Unknown until capability discovery. |
| `mcp-raia-lib` | Disabled | `docs.search`, `docs.overview`, indexed shared-library guidance. | GHCR authentication stays outside prompts. |

## Discovery Record

For each server, retain only name, enabled state, local/remote type, advertised tools/resources, health, and last discovery time. Do not persist headers, environment values, full private URLs, or tokens.

Raia search uses Spanish queries, result ranking rather than an absolute RRF threshold, preference `hybrid` over `lexical` over `vector`, and citations by `documentPath`.
