# Daniel Harness

Daniel Harness es la capa global que coordina el trabajo agentic de Daniel Morales sobre OpenCode y Gentle AI. Resuelve contexto, repositorios, políticas, herramientas, seguimiento de tareas y seguridad sin duplicar el motor de workflow de Gentle AI.

El código y los contratos viven en este repositorio. La configuración local y los secretos viven fuera, en `~/.config/daniel-harness/`.

## Instalación

### Versión estable (v0.1.0)

```bash
# Opcion 1 (recomendada): clonar con git
git clone git@github.com:daniel-morales-dev/daniel-harness.git \
  "$HOME/.local/share/daniel-harness"
cd "$HOME/.local/share/daniel-harness"

# Perfil core (OpenCode, Gentle AI, Engram, CodeGraph, RTK)
./install --profile core --connect

# Perfil alegra (core + GitHub CLI, AWS CLI, MCPs)
./install --profile alegra --connect
```

### Perfiles disponibles

| Perfil | Incluye |
|--------|---------|
| `core` | OpenCode, Gentle AI, Engram, CodeGraph, RTK, DH CLI + MCPs codegraph/engram |
| `alegra` | Core + GitHub CLI, AWS CLI + MCPs linear/context7/wiki-alegra/github |
| `migration` | Alegra + Docker, MariaDB + MCP navi |
| `full` | Migration + MCP sentry |

### Data tools experimentales

Los closed data tools (MySQL, MongoDB, DynamoDB, Object Storage) están en **beta**
y deshabilitados por defecto. Para activarlos:

```bash
./install --profile <perfil> --experimental-data-tools
```

O durante bootstrap:

```bash
./scripts/bootstrap.sh --profile full --experimental-data-tools
```

Esto crea el runtime Python, instala dependencias (boto3, pymongo, sqlglot)
y activa los agentes, tools y comandos de acceso a datos.

**Estado: experimental**. No se consideran estables en v0.1.0.

### Uso diario

```bash
dh update        # actualiza el harness
dh doctor        # diagnóstico
```

### Instalación por pasos

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
| `dh bootstrap [--profile core/alegra/migration/full] [--skip-docker] [--experimental-data-tools]` | Instalación desde cero según perfil |
| `dh mcp-status` | Conexión y OAuth de servidores MCP |
| `dh tunnel list` | Lista túneles configurados |
| `dh update` | Actualiza el harness desde Git |
| `dh context [dir]` | Detecta contexto del proyecto |
| `dh project init` | Asistente para registrar proyecto |
| `dh session <issue>` | Crea brief de sesión desde Linear |
| `dh engram-service install\|enable\|disable\|status` | Servicio systemd para Engram |
| `dh preflight` | Contexto completo del proyecto (JSON) |
| `dh verify` | Valida el proyecto según su contexto |
| `dh version` | Muestra la versión actual del harness |

## Variables de entorno

| Variable | Uso |
|---|---|
| `DANIEL_HARNESS_CONFIG_DIR` | Directorio de configuración local (default: `~/.config/daniel-harness`) |
| `DANIEL_HARNESS_BIN_DIR` | Directorio de binarios (default: `~/.local/bin`) |
| `DANIEL_HARNESS_RUNTIME_DIR` | Directorio de runtime (default: `~/.local/share/daniel-harness/runtime-venv`) |
| `DANIEL_HARNESS_REPO` | Ruta al repositorio (default: auto-detect) |
| `OPENCODE_CONFIG_FILE` | Ruta a opencode.json (default: `~/.config/opencode/opencode.json`) |
| `GITHUB_PERSONAL_ACCESS_TOKEN` | Token para MCP de GitHub |
| `NAVI_MCP_URL` | URL del servidor MCP de Navi |
| `NAVI_OAUTH_CLIENT_ID` | Client ID para OAuth de Navi |

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

## Contextos soportados

- Monolito Alegra: PHP 7.0.9 y Zend Framework 1.
- Microservicios Alegra: Node.js 24, TypeScript, Lambda/CDK, DynamoDB, Kafka, Clean Architecture y DDD.
- Paridad y migraciones entre monolito y microservicios relacionados.
- Proyectos freelance, inicialmente K Agencia.

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

## Diagnóstico

`doctor.sh` es read-only. Detecta herramientas, Gentle AI/RDD, MCPs, permisos y túneles.

```bash
./scripts/doctor.sh
./scripts/doctor.sh --profile core --strict
./scripts/doctor.sh --profile alegra --strict --skip-oauth
```

## Rollback y recuperación

La transacción de OpenCode (plugins + MCPs) está protegida por:

- **Lock**: impide ejecución simultánea de bootstrap
- **Journal**: guarda paths exactos de archivos y backups
- **Backups**: copias antes de cada modificación
- **Recuperación**: si una ejecución se interrumpe, el bootstrap siguiente
  detecta el journal y restaura el estado anterior

Para recuperación manual:

```bash
# Si el bootstrap falla, ejecutar de nuevo completa la transacción
./scripts/bootstrap.sh --profile core

# Rollback manual (solo si se conoce la estructura)
cp ~/.config/opencode/opencode.json.bak.* ~/.config/opencode/opencode.json
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

**v0.1.0** — Estable del harness base.

| Componente | Estado |
|---|---|
| Instalación y perfiles | Estable |
| OpenCode + plugins + MCPs | Estable |
| Gentle AI + agentes + skills | Estable |
| Reconciliación y doctor | Estable |
| Preflight, verify, update | Estable |
| Closed data tools | Experimental (beta) |

## Soporte

- Plataforma: Ubuntu 24.04 LTS
- Reporta errores en: https://github.com/daniel-morales-dev/daniel-harness/issues

Ubuntu 24.04 soportado. No se concede licencia pública.
