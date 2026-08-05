# Instalación

## Requisitos

- Ubuntu 24.04 LTS (x86_64)
- Git
- Sudo (para paquetes del sistema)
- Conexión a Internet

## Instalación limpia

### Opción 1: Clonar y bootstrap (recomendada)

```bash
# Clonar el repositorio
git clone git@github.com:daniel-morales-dev/daniel-harness.git \
  "$HOME/.local/share/daniel-harness"
cd "$HOME/.local/share/daniel-harness"

# Instalar perfil core
./install --profile core

# Bootstrap completo
./scripts/bootstrap.sh --profile core
```

### Opción 2: Perfiles progresivos

```bash
# Core primero
./scripts/bootstrap.sh --profile core

# Alegra después
./scripts/bootstrap.sh --profile alegra

# Migration (requiere Docker o --skip-docker si no está disponible)
./scripts/bootstrap.sh --profile migration

# Full
./scripts/bootstrap.sh --profile full
```

### Opción 3: Con data tools experimentales

```bash
./scripts/install.sh --experimental-data-tools
./scripts/bootstrap.sh --profile full --experimental-data-tools
```

## Verificación

```bash
# Diagnóstico completo
./scripts/doctor.sh

# Con perfil específico y modo estricto
./scripts/doctor.sh --profile core --strict
./scripts/doctor.sh --profile alegra --strict --skip-oauth
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
# Eliminar enlaces administrados
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
| `GITHUB_PERSONAL_ACCESS_TOKEN` | — | Token para MCP de GitHub |
| `NAVI_MCP_URL` | — | URL del servidor Navi |
| `NAVI_OAUTH_CLIENT_ID` | — | Client ID de OAuth Navi |

## OAuth

Después de instalar, autentica los MCPs que requieren OAuth:

```bash
opencode mcp auth linear
opencode mcp auth sentry
opencode mcp auth wiki-alegra
opencode mcp auth navi
```

Configura `GITHUB_PERSONAL_ACCESS_TOKEN` para el MCP de GitHub:

```bash
export GITHUB_PERSONAL_ACCESS_TOKEN="ghp_..."
```

## Directorios creados

| Directorio | Propósito |
|---|---|
| `~/.config/daniel-harness/` | Configuración local |
| `~/.config/daniel-harness/secrets/` | Secretos (modo 700) |
| `~/.config/daniel-harness/state/` | Estado administrado |
| `~/.config/opencode/` | Configuración de OpenCode |
| `~/.local/share/daniel-harness/runtime-venv/` | Runtime Python |
| `~/.local/bin/` | Binarios (dh, dh-install) |
