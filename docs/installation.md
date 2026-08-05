# Instalación

## Requisitos

- Ubuntu 24.04 LTS (x86_64)
- Git
- Sudo (para paquetes del sistema)
- Conexión a Internet

## Nueva instalación (recomendado)

```bash
git clone git@github.com:daniel-morales-dev/daniel-harness.git \
  "$HOME/.local/share/daniel-harness"
cd "$HOME/.local/share/daniel-harness"

# Selector interactivo de perfil
./install
```

## Instalación completa

```bash
./install --profile full --connect --reset-managed
```

## Instalación por perfil

```bash
# Core
./install --profile core

# Alegra
./install --profile alegra

# Migration (requiere Docker)
./install --profile migration

# Full
./install --profile full
```

## Modo no interactivo

```bash
./install --profile full --non-interactive
```

Requiere `--profile`. Falla inmediatamente si falta.

## Flags de instalación

| Flag | Descripción |
|------|-------------|
| `--profile <perfil>` | Perfil a instalar: `core`, `alegra`, `migration`, `full` |
| `--connect` | Autenticación interactiva de MCPs + doctor + resumen |
| `--reset-managed` | Reinstala solo recursos del harness |
| `--non-interactive` | No muestra prompts |
| `--experimental-data-tools` | Closed data tools (beta) |

## Bootstrap directo

```bash
# Core primero
./scripts/bootstrap.sh --profile core

# Alegra después
./scripts/bootstrap.sh --profile alegra

# Migration (requiere Docker o --skip-docker)
./scripts/bootstrap.sh --profile migration --skip-docker

# Full
./scripts/bootstrap.sh --profile full
```

## Data tools experimentales

```bash
./scripts/install.sh --experimental-data-tools
./scripts/bootstrap.sh --profile full --experimental-data-tools
```

## Secretos persistentes

GitHub y Navi se configuran durante `--connect` y se almacenan en:

- `~/.config/daniel-harness/secrets/github/authorization`
- `~/.config/daniel-harness/secrets/navi/url`
- `~/.config/daniel-harness/secrets/navi/client-id`

No requieren exportar variables de entorno en cada shell.

## Verificación

```bash
# Diagnóstico completo
./scripts/doctor.sh

# Con perfil específico y modo estricto
./scripts/doctor.sh --profile core --strict

# Solo validación estructural (sin probes OAuth)
./scripts/doctor.sh --install-check --skip-oauth
```

## OAuth

Después de instalar, autentica los MCPs que requieren OAuth:

```bash
opencode mcp auth linear
opencode mcp auth sentry
opencode mcp auth wiki-alegra
opencode mcp auth navi
```

O con `--connect`:
```bash
./install --profile full --connect
```

## Backup y restauración

```bash
# Crear backup de opencode.json
dh opencode backup

# Listar backups
dh opencode backups

# Restaurar
dh opencode restore <backup-id>

# Ver diferencias estructurales
dh opencode diff <backup-id>
```

## Actualización

```bash
dh update
```

O manualmente:

```bash
cd "$HOME/.local/share/daniel-harness"
git pull
./scripts/bootstrap.sh --profile <perfil>
```

## Desinstalación

```bash
# Eliminar enlaces y copias administradas
./scripts/uninstall.sh

# Con data tools experimentales
./scripts/uninstall.sh --experimental-data-tools

# La configuración local (~/.config/daniel-harness/) se conserva
```

## Variables de entorno

| Variable | Default | Descripción |
|---|---|---|
| `DANIEL_HARNESS_CONFIG_DIR` | `~/.config/daniel-harness` | Directorio de configuración |
| `DANIEL_HARNESS_BIN_DIR` | `~/.local/bin` | Directorio de binarios |
| `DANIEL_HARNESS_RUNTIME_DIR` | `~/.local/share/daniel-harness/runtime-venv` | Runtime Python |
| `DH_MCP_PROBE_TIMEOUT_SECONDS` | `3` | Timeout de probes MCP en doctor |
| `GITHUB_PERSONAL_ACCESS_TOKEN` | — | Token para migración a archivo persistente |
| `NAVI_MCP_URL` | — | URL del servidor Navi (migrable) |
| `NAVI_OAUTH_CLIENT_ID` | — | Client ID de OAuth Navi (migrable) |

## Directorios creados

| Directorio | Propósito | Permisos |
|---|---|---|
| `~/.config/daniel-harness/` | Configuración local | 700 |
| `~/.config/daniel-harness/secrets/` | Secretos | 700 |
| `~/.config/daniel-harness/secrets/github/` | Token GitHub | 700 |
| `~/.config/daniel-harness/secrets/navi/` | Credenciales Navi | 700 |
| `~/.config/daniel-harness/state/` | Estado administrado | 700 |
| `~/.config/daniel-harness/backups/` | Backups de opencode.json | 700 |
| `~/.config/opencode/` | Configuración de OpenCode | — |
| `~/.local/share/daniel-harness/runtime-venv/` | Runtime Python | — |
| `~/.local/bin/` | Binarios (dh, dh-install) | — |

## Agentes del harness

Los 5 agentes administrados se instalan como copias regulares:

| Agente | Propósito |
|---|---|
| `alegra-microservice-engineer` | Microservicios TypeScript Alegra |
| `alegra-microservice-test-engineer` | Tests de microservicios |
| `code-reviewer` | Code review estricto |
| `php-engineer` | PHP 7.0.9 / ZF1 |
| `migration-parity-reviewer` | Paridad PHP ↔ TS |

Modo: `subagent`. Verificables con `dh doctor` o `opencode agent list`.
