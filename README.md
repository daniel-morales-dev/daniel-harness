# Daniel Harness

Daniel Harness es la capa global que coordina el trabajo agentic de Daniel Morales sobre OpenCode y Gentle AI. Resuelve contexto, repositorios, políticas, herramientas, seguimiento de tareas y seguridad sin duplicar el motor de workflow de Gentle AI.

El código y los contratos viven en este repositorio. La configuración local y los secretos viven fuera, en `~/.config/daniel-harness/`.

## Instalación

### Nueva instalación (recomendado)

```bash
# Clonar
git clone git@github.com:daniel-morales-dev/daniel-harness.git \
  "$HOME/.local/share/daniel-harness"
cd "$HOME/.local/share/daniel-harness"

# Selector interactivo de perfil
./install
```

### Instalación completa (full + connect)

```bash
./install --profile full --connect --reset-managed
```

Esto instala todos los componentes, configura secretos de forma persistente y autentica MCPs OAuth.

### Modo no interactivo

```bash
./install --profile full --non-interactive
```

Requiere `--profile`. No muestra prompts.

### Perfiles disponibles

Selección interactiva al ejecutar `./install` sin argumentos en una terminal, o explícita con `--profile`:

| Perfil | Descripción | Herramientas | MCPs |
|--------|-------------|-------------|------|
| `core` | Herramientas base | OpenCode, Gentle AI, Engram, CodeGraph, RTK, DH | codegraph, engram |
| `alegra` | Trabajo cotidiano Alegra | core + gh, aws | + linear, context7, wiki-alegra, github |
| `migration` | Migración monolito → micros | alegra + docker | + navi |
| `full` | Todos los MCPs y herramientas | alegra + docker | + navi, sentry |

### Flags

| Flag | Descripción |
|------|-------------|
| `--profile <perfil>` | Perfil a instalar. Requerido en modo `--non-interactive` |
| `--connect` | Autenticación interactiva de MCPs, doctor y resumen final |
| `--reset-managed` | Reinstala recursos administrados y reconcilia MCPs |
| `--non-interactive` | No mostrar prompts. Requiere `--profile` |
| `--experimental-data-tools` | Instala closed data tools experimentales (beta) |

Exit codes: `0` saludable, `1` error, `2` instalado con OAuth pendiente.

### Secretos persistentes

GitHub y Navi usan almacenamiento persistente en archivos (`~/.config/daniel-harness/secrets/`),
no requieren exportar variables en cada shell.

### Uso diario

```bash
# Diagnóstico
dh doctor

# Backup de configuración
dh opencode backup

# Listar backups
dh opencode backups

# Restaurar backup
dh opencode restore <backup-id>

# Actualizar harness
dh update
```

Reinicia OpenCode después de instalar agentes, skills o plugins.

## CLI `dh`

Después de `install.sh` o `bootstrap.sh`, `dh` queda disponible como comando global.

| Comando | Función |
|---|---|
| `dh doctor` | Diagnóstico completo del harness |
| `dh install` | Configuración local + symlinks |
| `dh bootstrap [--profile...]` | Instalación desde cero según perfil |
| `dh opencode backup` | Crea backup de opencode.json |
| `dh opencode backups` | Lista backups disponibles |
| `dh opencode restore <id>` | Restaura un backup |
| `dh opencode diff <id>` | Muestra diff estructural con un backup |
| `dh mcp-status` | Conexión y OAuth de servidores MCP |
| `dh tunnel list` | Lista túneles configurados |
| `dh update` | Actualiza el harness desde Git |
| `dh context [dir]` | Detecta contexto del proyecto |
| `dh project init` | Asistente para registrar proyecto |
| `dh session <issue>` | Crea brief de sesión desde Linear |
| `dh engram-service` | Servicio systemd para Engram |
| `dh preflight` | Contexto completo del proyecto (JSON) |
| `dh verify` | Valida el proyecto según su contexto |
| `dh version` | Versión actual del harness |

## Variables de entorno

| Variable | Uso |
|---|---|
| `DANIEL_HARNESS_CONFIG_DIR` | Configuración local (default: `~/.config/daniel-harness`) |
| `DANIEL_HARNESS_BIN_DIR` | Directorio de binarios (default: `~/.local/bin`) |
| `DANIEL_HARNESS_RUNTIME_DIR` | Directorio de runtime (default: `~/.local/share/daniel-harness/runtime-venv`) |
| `DANIEL_HARNESS_REPO` | Ruta al repositorio (default: auto-detect) |
| `OPENCODE_CONFIG_FILE` | Ruta a opencode.json (default: `~/.config/opencode/opencode.json`) |
| `DH_MCP_PROBE_TIMEOUT_SECONDS` | Timeout de probes MCP (default: 3) |
| `GITHUB_PERSONAL_ACCESS_TOKEN` | Usado solo durante migración a archivo persistente |
| `NAVI_MCP_URL` | URL del servidor MCP de Navi (migrable a archivo) |
| `NAVI_OAUTH_CLIENT_ID` | Client ID para OAuth de Navi (migrable a archivo) |

## Agentes del harness

Los 5 agentes administrados se instalan como copias administradas (no symlinks):

- `alegra-microservice-engineer`
- `alegra-microservice-test-engineer`
- `code-reviewer`
- `php-engineer`
- `migration-parity-reviewer`

Modo: `subagent`, `hidden: false`. Verificables con `dh doctor` o `opencode agent list`.

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
├── state/
│   └── opencode-managed.state
├── backups/
│   └── opencode-*.json
├── policies/
├── policies.local/
└── secrets/
    ├── github/
    ├── navi/
    ├── mysql/
    ├── mongodb/
    ├── tunnels/
    └── tokens/
```

- `config.yaml`: autoridad de workflow, tooling, modelos, Linear y MCP routing.
- `connections.yaml`: endpoints locales, perfiles de datos y referencias de túneles.
- `project-registry.yaml`: proyectos, familias, relaciones, reglas y política Git.
- `state/opencode-managed.state`: estado administrado de recursos del harness.
- `backups/`: backups automáticos de opencode.json.
- `secrets/github/authorization`: token persistente de GitHub (modo 600).
- `secrets/navi/url` y `secrets/navi/client-id`: credenciales Navi (modo 600).
- `secrets/tunnels/*.command`: comandos SSH reales, locales, modo 600, nunca versionados.

Consulta `docs/configuration.md` para agregar o eliminar túneles, MCPs, proyectos y reglas.

## Diagnóstico

`doctor.sh` es read-only. Detecta herramientas, Gentle AI/RDD, MCPs, permisos y túneles.

```bash
./scripts/doctor.sh
./scripts/doctor.sh --profile core --strict
./scripts/doctor.sh --profile alegra --strict --skip-oauth
./scripts/doctor.sh --install-check --skip-oauth  # solo validación estructural
```

Variable `DH_MCP_PROBE_TIMEOUT_SECONDS` (default: 3) para controlar timeout de probes.

## Backup y restauración

```bash
# Crear backup
dh opencode backup

# Listar backups
dh opencode backups

# Restaurar por prefijo SHA
dh opencode restore a1b2c3d4

# Ver diff estructural (solo nombres, sin valores)
dh opencode diff a1b2c3d4
```

Los backups se almacenan en `~/.config/daniel-harness/backups/` con modo 600.
La configuración activa se respalda automáticamente antes de cada modificación.

## Seguridad

- Un repositorio privado no es un almacén de secretos.
- Los modelos restricted no reciben shell arbitrario ni lectura directa de secretos.
- MySQL/MariaDB operativo es siempre read-only.
- Las escrituras DynamoDB requieren confirmación exacta.
- Los túneles son manuales.
- No edites prompts, agentes o configuración generada por Gentle AI; usa `gentle-ai install`, `sync` y sus contratos públicos.
- Los secretos GitHub y Navi se almacenan fuera de opencode.json, en archivos modo 600.
- `dh opencode diff` solo muestra estructura, nunca valores.

Consulta `SECURITY.md` y `docs/security-model.md`.

## Estado

**v0.1.1** — Hotfix de instalación, migración y configuración completa.

| Componente | Estado |
|---|---|
| Instalación y perfiles | Estable |
| Selector interactivo de perfil | Nueva |
| OpenCode + plugins + MCPs | Estable |
| Gentle AI + agentes + skills | Estable |
| Agentes como copias administradas | Nueva en v0.1.1 |
| Secretos persistentes (GitHub, Navi) | Nueva en v0.1.1 |
| Backup y restauración de opencode.json | Nueva en v0.1.1 |
| Reconciliación y doctor | Estable |
| Doctor --install-check --skip-oauth | Nueva en v0.1.1 |
| Preflight, verify, update | Estable |
| Closed data tools | Experimental (beta) |

## Soporte

- Plataforma: Ubuntu 24.04 LTS
- Reporta errores en: https://github.com/daniel-morales-dev/daniel-harness/issues
- Smoke test de release: `docs/release-smoke.md`

Ubuntu 24.04 soportado. No se concede licencia pública.
