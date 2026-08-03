# Registro de capacidades MCP

El registro se descubre por capacidad. Esta tabla es inventario inicial, no source of truth hardcodeado.

| Servidor | Estado esperado | Capacidades |
|---|---|---|
| `codegraph` | Connected | Estructura, símbolos, referencias, call paths e impacto. |
| `context7` | Connected | Documentación pública actual. |
| `engram` | Connected | Memoria persistente y artefactos SDD. |
| `github` | Connected | Repositorios, issues y PRs; identidad depende del proyecto. |
| `linear` | Connected | Tareas, comentarios, jerarquía y estados. |
| `wiki-alegra` | Connected | Documentación interna. |
| `sentry` | Requiere autenticación | Diagnóstico de errores. |
| `alegra-test` | Incompatible con OpenCode | Funciona solo en Claude Code y ChatGPT. No incluir en bootstrap ni en la configuración de OpenCode. |
| `mcp-raia-lib` | Disabled | `docs.search`, `docs.overview` y librerías shared de Expenses. |

Conserva solo nombre, enabled, tipo local/remote, tools/resources anunciados, salud y fecha de discovery. Nunca persistas headers, env, URLs privadas completas o tokens.

Raia usa queries en español, ranking RRF, preferencia `hybrid > lexical > vector` y citas por `documentPath`.
