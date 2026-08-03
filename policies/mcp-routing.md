# MCP Routing

Discover configured servers and their available tools at runtime. Never infer capabilities solely from a server name and never print headers, environment values, tokens, or full private URLs.

| Capability | Preferred server | Rule |
|---|---|---|
| Code structure and impact | `codegraph` | First choice for symbols, call flow, dependencies, and blast radius. |
| Public library docs | `context7` | Resolve library identity, then query current documentation. |
| Persistent decisions | `engram` | Save decisions, discoveries, fixes, conventions, and session summaries. |
| Git hosting | `github` | Use only when project identity and authorization allow it. |
| Work tracking | `linear` | Read issue and comments before work; update in Spanish after verified completion. |
| Internal Alegra docs | `wiki-alegra` | Activate for Wiki links and internal concepts. |
| Error diagnosis | `sentry` | Use only after authentication is available. |
| Test capabilities | `alegra-test` | Discover tools before assigning responsibility. |
| Expenses shared libraries | `mcp-raia-lib` | Search Spanish docs for common/shared utilities; never fabricate when offline. |

Raia is initially disabled. Enabling it requires prior GHCR authentication outside prompts, an available image, explicit approval, and an OpenCode restart.
