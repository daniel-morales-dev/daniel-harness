# Integración con Gentle AI

Daniel Harness integra Gentle AI como proveedor de routing y autoridad de review, no como una colección de prompts copiados.

## Contrato

| Gentle AI posee | Daniel Harness posee |
|---|---|
| Direct/delegated/optional SDD | Contexto y familias |
| RDD, candidate freeze y receipts | Scope de repositorios |
| Risk/lenses/correction budget | Políticas y trust boundary |
| Delivery gates y recovery | Linear, MCP routing y datos |
| SDD artifacts y phase delegation | Reglas específicas de monolito/micro/freelance |

## Routing orgánico

La política actual usa acción acotada directa, delegación cuando se necesita contexto fresco y SDD opcional cuando artefactos durables reducen ambigüedad. Tamaño y riesgo fortalecen verificación/review, pero no fuerzan SDD.

## OpenCode

- El conductor base es `gentle-orchestrator`.
- Los perfiles se administran con Gentle AI, no editando entries generadas.
- `gentle-ai sync` refresca contenido administrado.
- `gentle-ai skill-registry refresh --force` descubre `php-engineer`, `task-lifecycle` y otras skills.
- Reinicia OpenCode después de cambios de configuración.

## RDD

Cuando RDD está activo, la misma candidate congelada atraviesa review y gates. El harness no calcula hashes, no crea receipts y no deduce recovery desde mensajes.

Comandos read-only útiles:

```bash
gentle-ai version
gentle-ai doctor
gentle-ai review mode status --cwd .
```

El contrato negotiated review v2.1 tiene transporte immutable habilitado actualmente para Claude Code. OpenCode no debe invocarlo fingiendo identidad; usa el adapter y comportamiento instalados por Gentle AI hasta que capabilities anuncie soporte.

## Actualizaciones

1. Ejecuta `gentle-ai upgrade`.
2. Ejecuta `gentle-ai sync`.
3. Refresca skill registry.
4. Ejecuta `gentle-ai doctor` y `./scripts/doctor.sh`.
5. Revalida schemas y workflows si cambió el contrato público.

Nunca dependas de archivos internos o prompts generados. Negocia capabilities cuando el adapter ejecutable se implemente.
