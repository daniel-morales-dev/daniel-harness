# Daniel Harness

Daniel Harness es la capa privada y global que coordina el trabajo agentic de Daniel Morales sobre OpenCode y Gentle AI. Resuelve contexto, repositorios, políticas, herramientas, seguimiento de tareas y seguridad sin duplicar el motor de workflow de Gentle AI.

El código y los contratos viven en este repositorio. La configuración local y los secretos viven fuera, en `~/.config/daniel-harness/`.

## Instalación

### Primera vez

```bash
# Clona el harness en XDG data
gh repo clone daniel-morales-dev/daniel-harness \
  "$HOME/.local/share/daniel-harness"

# Instala todo el perfil cotidiano (OpenCode, agentes, MCPs, tools)
"$HOME/.local/share/daniel-harness/scripts/bootstrap.sh" \
  --profile alegra
```

Perfiles disponibles:

| Perfil | Incluye |
|--------|---------|
| `core` | OpenCode, Gentle AI, Engram, CodeGraph, RTK, DH CLI + MCPs codegraph/engram |
| `alegra` | Core + GitHub CLI, AWS CLI + MCPs linear/context7/wiki-alegra |
| `migration` | Alegra + Docker, MariaDB + MCP raia-lib |
| `full` | Migration + MCPs github/sentry |

Avanzado:

```bash
./scripts/bootstrap.sh               # perfil core
./scripts/bootstrap.sh --profile alegra
./scripts/bootstrap.sh --dry-run     # simulación
```

### Uso diario

```bash
dh update        # actualiza el harness
dh doctor        # diagnóstico
```

Install por pasos si ya tienes las herramientas base:

```bash
./scripts/install.sh               # configuración local + symlinks
./scripts/doctor.sh                # diagnóstico
gentle-ai skill-registry refresh --force
```

Reinicia OpenCode después de instalar agentes, skills o plugins.

## CLI `dh`

Después de `install.sh` o `bootstrap.sh`, `dh` queda disponible como comando global.

| Comando | Función |
|---|---|
| `dh doctor` | Diagnóstico completo del harness |
| `dh install` | Configuración local + symlinks |
| `dh bootstrap [--profile core|alegra|migration|full] [--skip-docker]` | Instalación desde cero según perfil |
| `dh mcp-status` | Conexión y OAuth de servidores MCP |
| `dh tunnel list` | Lista túneles configurados |
| `dh update` | Actualiza el harness desde Git |
| `dh context [dir]` | Detecta contexto del proyecto |
| `dh project init` | Asistente para registrar proyecto |
| `dh session <issue>` | Crea brief de sesión desde Linear |
| `dh engram-service install\|enable\|disable\|status` | Servicio systemd para Engram |

## Reparto de autoridad

| Superficie | Autoridad |
|---|---|
| Routing directo, delegado o SDD | Gentle AI |
| RDD, review, receipts y delivery gates | Gentle AI |
| Contexto y familia de proyecto | Daniel Harness |
| Repositorios en lectura/escritura | Daniel Harness |
| Precedencia, permisos y confianza del modelo | Daniel Harness |
| Linear, MCP routing y acceso de datos | Daniel Harness |
| Implementación mínima | Ponytail |
| Comunicación comprimida | Caveman, de forma adaptativa |
| Arquitectura y blast radius | CodeGraph |
| Memoria persistente | Engram |

SDD no se activa automáticamente por tamaño o riesgo. Gentle AI lo usa cuando el usuario lo pide o acepta una propuesta que justifica artefactos durables.

## Contextos soportados

- Monolito Alegra: PHP 7.0.9 y Zend Framework 1.
- Microservicios Alegra: Node.js 24, TypeScript, Lambda/CDK, DynamoDB, Kafka, Clean Architecture y DDD.
- Paridad y migraciones entre monolito y microservicios relacionados.
- Proyectos freelance, inicialmente K Agencia.

## Agentes y skills

| Recurso | Uso |
|---|---|
| `php-engineer` | Cambios quirúrgicos y compatibles con PHP 7.0.9/ZF1. |
| `alegra-microservice-engineer` | TypeScript/JavaScript, arquitectura y calidad. |
| `alegra-microservice-test-engineer` | Estrategia y construcción de pruebas. |
| `code-reviewer` | Revisión estricta antes de entrega. |
| `task-lifecycle` | Lectura completa y seguimiento de tareas Linear. |
| `monolith-to-micro-migration` | Paridad observable de PHP hacia TypeScript. |

## Configuración local

```text
~/.config/daniel-harness/
├── config.yaml
├── connections.yaml
├── project-registry.yaml
└── secrets/
    ├── mysql/
    ├── mongodb/
    ├── tunnels/
    └── tokens/
```

- `config.yaml`: autoridad de workflow, tooling, modelos, Linear y MCP routing.
- `connections.yaml`: endpoints locales, perfiles de datos y referencias de túneles.
- `project-registry.yaml`: proyectos, familias, relaciones, reglas y política Git.
- `secrets/tunnels/*.command`: comandos SSH reales, locales, modo `600`, nunca versionados.

Consulta `docs/configuration.md` para agregar o eliminar túneles, MCPs, proyectos y reglas.

## Flujos

- `docs/workflows/task-lifecycle.md`: tarea, subtareas, comentarios, avances y cierre.
- `docs/workflows/monolith.md`: bugs y features en PHP/ZF1.
- `docs/workflows/microservice.md`: features y fixes en Node/TypeScript.
- `docs/workflows/freelance.md`: proyectos externos y conexiones manuales.
- `docs/workflows/parity.md`: paridad monolito → micro y micro → monolito.

## Diagnóstico

`doctor.sh` es read-only. Detecta herramientas, Gentle AI/RDD, MCPs, permisos y túneles. Si falta un túnel, informa el perfil y el archivo local que debes ejecutar; nunca abre el túnel ni imprime su comando.

```bash
./scripts/doctor.sh
./scripts/redact-opencode-config.sh /ruta/explicita/opencode.json > opencode.redacted.json
```

## Seguridad

- Un repositorio privado no es un almacén de secretos.
- Los modelos restricted no reciben shell arbitrario ni lectura directa de secretos.
- MySQL/MariaDB operativo es siempre read-only.
- Las escrituras DynamoDB requieren confirmación exacta.
- Los túneles son manuales.
- No edites prompts, agentes o configuración generada por Gentle AI; usa `gentle-ai install`, `sync` y sus contratos públicos.

Consulta `SECURITY.md` y `docs/security-model.md`.

## Estado

La fundación, seguridad, `php-engineer`, workflows y contratos de integración están versionados. El context detector/preflight ejecutable y los data tools productivos siguen en el roadmap.

Este repositorio es privado y personal. No se concede licencia pública.
