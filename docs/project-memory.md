# Memoria del proyecto

## Estado

Daniel Harness está versionado en `daniel-morales-dev/daniel-harness`. La fundación y la segunda fase documental/agentes están implementadas sobre OpenCode, con núcleo portable.

## Invariantes

- Harness global; config local en `~/.config/daniel-harness/`.
- CLI `dh` como entry point unificado (`docs/dh-cli.md`).
- Gentle AI es autoridad de routing y RDD; no fork ni edición de generated assets.
- SDD es explícito o surge de una propuesta aceptada, no de tamaño/riesgo automático.
- Scope por tarea: `single-repo`, `related-repos` o `multi-project`.
- Nunca crear rama sin preguntar.
- MySQL operativo siempre read-only.
- DynamoDB write con confirmación exacta.
- Túneles manuales y comandos reales fuera del repo.
- Restricted sin Bash arbitrario ni secretos directos.
- CodeGraph primero para estructura; Engram para memoria.
- Ponytail minimiza código; Caveman comprime comunicación, no artefactos.

## Reglas de operación

- **Alegra**: nunca empezar sin tarea Linear. Si no existe, crearla antes de implementar.
- **ADR**: toda decisión de arquitectura o diseño se registra en `docs/adr/` del proyecto activo.

## Contextos

| Contexto | Reglas clave |
|---|---|
| `alegra-monolith` | PHP 7.0.9, ZF1, cambios quirúrgicos, `php -l` en contenedor, sin modernización lateral. |
| `alegra-microservice` | Node 24, TypeScript, Lambda/CDK, Clean/DDD, tests enfocados y 90% line/branch en business logic modificada. |
| `freelance` | Reglas del proyecto primero; conexiones y túneles manuales. |

## Assets migrados de Fase 1

| Target | SHA-256 |
|---|---|
| `agents/alegra-microservice-engineer.md` | `30dbb1827661345acc4a214eae99c5ccbea6ff4ea6df7e59c4b127426b081ba4` |
| `agents/code-reviewer.md` | `1b5acdb457ad9621057c8bba3697307dbd6c612ea06ca9775ec87044d906a0c0` |
| `agents/alegra-microservice-test-engineer.md` | `73720259e88ff37f16452c841d199e8859e251473555ed0f977af1077e0658f3` |
| `skills/monolith-to-micro-migration/SKILL.md` | `bebea5554a4480174f4e02c3267e9375585716ad11979b835c772a88b37714a0` |
| `commands/migration-gap-analysis.md` | `2b3126ea4a4b34b888f9d560ebdef4b33799d42013a3fccdd9b7de1a683be7d1` |

No modificar estos assets salvo tarea explícita. `migration-gap.md` solo fue normalizado de nombre.

## Assets propios posteriores

- `agents/php-engineer.md`.
- `skills/task-lifecycle/SKILL.md`.
- `bin/dh`: CLI unificada.
- `scripts/detect-context.sh`: detector de contexto.
- `scripts/bootstrap.sh`: instalación completa.
- `bootstrap/manifest.yaml`: versión de herramientas.
- Workflows y guías de configuración en `docs/`.

## Seguridad

- El token GitHub previamente hardcodeado debe rotarse y externalizarse.
- Una guía local no versionada del monolito contiene credenciales; no se copiaron.
- Los comandos SSH compartidos se guardan solo en archivos locales restringidos.
- La separación de modelos restricted aún necesita enforcement productivo.

## Gentle AI observado

- Versión local al diseñar esta fase: `2.2.4`.
- RDD activo por default.
- OpenCode instalado como integración full multi-mode.
- `gentle-ai doctor` degradado por dos binarios Engram en PATH.
- El contrato negotiated review v2.1 usa transporte immutable soportado solo por Claude Code; OpenCode debe usar el adapter administrado por Gentle AI y no fingir compatibilidad v2.1.
