#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MANIFEST="$ROOT_DIR/bootstrap/manifest.yaml"
source "$ROOT_DIR/scripts/profile-resolver.sh"

CONFIG_ROOT=${XDG_CONFIG_HOME:-"$HOME/.config"}
HARNESS_CONFIG_DIR=${DANIEL_HARNESS_CONFIG_DIR:-"$CONFIG_ROOT/daniel-harness"}
STATE_DIR="$HARNESS_CONFIG_DIR/state"
STATE_FILE="$STATE_DIR/opencode-managed.json"
MANAGED_MCPS=()

DRY_RUN=false
SKIP_DOCKER=false
PROFILE=core

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --skip-docker) SKIP_DOCKER=true; shift ;;
    --profile) PROFILE=$2; shift 2 ;;
    --profile=*) PROFILE=${1#*=}; shift ;;
    --help|-h) printf 'Uso: bootstrap.sh [--dry-run] [--profile core|alegra|migration|full] [--skip-docker]\n'; exit 0 ;;
    *) printf 'Argumento desconocido: %s\n' "$1" >&2; exit 1 ;;
  esac
done

if [[ ! -f "$MANIFEST" ]]; then
  printf 'error: no se encuentra %s\n' "$MANIFEST" >&2
  exit 1
fi

if [[ $DRY_RUN == true ]]; then
  printf '\n[preflight] Simulación (--dry-run)\n\n'
fi

phase() {
  local label=$1
  printf '\n==> %s\n' "$label"
}

ok() { printf '  [ok] %s\n' "$*"; }
skip() { printf '  [- ] %s\n' "$*"; }
info() { printf '  [..] %s\n' "$*"; }
warn() { printf '  [aviso] %s\n' "$*"; }
critical() { printf '  [crítico] %s\n' "$*"; }
run() {
  if [[ $DRY_RUN == true ]]; then
    info "[simulado] $*"
  else
    "$@"
  fi
}
sudo_run() {
  if [[ $DRY_RUN == true ]]; then
    info "[simulado] sudo $*"
  else
    sudo "$@"
  fi
}

# ---------------------------------------------------------------------------
# Fase 0: Preflight
# ---------------------------------------------------------------------------
phase "Preflight"

if [[ ! -f /etc/os-release ]] || ! grep -qi 'ubuntu' /etc/os-release 2>/dev/null; then
  printf '  [aviso] Sistema operativo no verificado como Ubuntu\n'
fi

if ! command -v sudo >/dev/null 2>&1; then
  printf 'error: sudo es necesario\n' >&2
  exit 1
fi

_ensure_sudo() {
  if [[ $DRY_RUN == false ]] && ! sudo -n true 2>/dev/null; then
    printf 'Se necesita acceso sudo.\n'
    sudo -v || exit 1
  fi
}

# Parseadores del manifest (sin dependencia de yq)
# provistos por profile-resolver.sh:
#   parse_section, parse_nested_list, parse_value
#   parse_mcp_names, parse_mcp_field, parse_mcp_headers_json
#   _get_profile_field, _get_profile_extend, profile_includes
#   get_profile_mcps, get_profile_tools, get_profile_plugins

# ---------------------------------------------------------------------------
# Fase 1: Dependencias del sistema
# ---------------------------------------------------------------------------
phase "Dependencias del sistema (sudo apt-get)"

mapfile -t packages < <(
  parse_nested_list "system_packages" "required"
)
mapfile -t optional_packages < <(
  parse_nested_list "system_packages" "optional"
)

missing=()
for pkg in "${packages[@]}"; do
  dpkg -s "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
done
for pkg in "${optional_packages[@]}"; do
  if profile_includes "$PROFILE" "optional_packages" "$pkg"; then
    dpkg -s "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
  else
    skip "Paquete opcional $pkg (no incluido en perfil $PROFILE)"
  fi
done

if (( ${#missing[@]} > 0 )); then
  _ensure_sudo
  info "Instalando: ${missing[*]}"
  sudo_run apt-get update -qq
  sudo_run apt-get install -y --no-install-recommends "${missing[@]}"
else
  ok 'Todos los paquetes del sistema están instalados'
fi

# ---------------------------------------------------------------------------
# Fase 2: NVM + Node
# ---------------------------------------------------------------------------
phase "NVM + Node.js"

NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
if [[ -s "$NVM_DIR/nvm.sh" ]]; then
  ok "NVM ya instalado ($(source "$NVM_DIR/nvm.sh" && nvm --version 2>/dev/null))"
else
  info 'Instalando NVM...'
  run bash -c 'curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash'
fi

if [[ -s "$NVM_DIR/nvm.sh" ]]; then
  . "$NVM_DIR/nvm.sh"
  if node --version 2>/dev/null | head -1 | grep -q '^v24'; then
    ok "Node.js 24 activo ($(node --version))"
  else
    info 'Instalando Node.js 24...'
    run nvm install 24
    run nvm alias default 24
    . "$NVM_DIR/nvm.sh"
    ok "Node.js 24 instalado ($(node --version))"
  fi
fi

# ---------------------------------------------------------------------------
# Fase 3: Herramientas user-space
# ---------------------------------------------------------------------------
phase "Herramientas CLI"

install_tool_if_in_profile() {
  local profile_key=$1 label=$2 check=$3 install_cmd=$4
  if profile_includes "$PROFILE" "tools" "$profile_key"; then
    if eval "$check" >/dev/null 2>&1; then
      ok "$label ya instalado"
    else
      info "Instalando $label..."
      run bash -c "$install_cmd"
    fi
  else
    skip "$label (no incluido en perfil $PROFILE)"
  fi
}

install_tool_if_in_profile "opencode"  "OpenCode"  "command -v opencode"  "curl -fsSL https://opencode.ai/install | bash"
install_tool_if_in_profile "gentle-ai" "Gentle AI" "command -v gentle-ai" "curl -fsSL https://gentle-ai.dev/install.sh | sh"
install_tool_if_in_profile "engram"    "Engram"    "command -v engram"    "curl -fsSL https://engram.sh/install.sh | sh"

if [[ -s "$NVM_DIR/nvm.sh" ]]; then
  . "$NVM_DIR/nvm.sh"
elif [[ $DRY_RUN == true ]]; then
  info "[simulado] NVM estaría disponible después de la instalación. CodeGraph puede fallar sin Node."
fi
install_tool_if_in_profile "codegraph" "CodeGraph" "command -v codegraph" "npm install -g @codegraph/cli"
install_tool_if_in_profile "rtk"       "RTK"       "command -v rtk"       "curl -fsSL https://rtk.dev/install.sh | sh"

if profile_includes "$PROFILE" "tools" "gh"; then
  if dpkg -s gh >/dev/null 2>&1; then
    ok "GitHub CLI ya instalado"
  else
    info 'Instalando GitHub CLI...'
    sudo_run apt-get install -y --no-install-recommends gh
  fi
else
  skip "GitHub CLI (no incluido en perfil $PROFILE)"
fi

if profile_includes "$PROFILE" "tools" "aws"; then
  if command -v aws >/dev/null 2>&1; then
    ok "AWS CLI ya instalado"
  else
    info 'Instalando AWS CLI...'
    # ponytail: checksum for known-good version, update when AWS releases new v2
    run bash -c '
      curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip &&
      echo "02a8eb2fe985be8ebcc284aaa5bae206ee8668872d6369e66a5c7d49d8671a08  /tmp/awscliv2.zip" | sha256sum -c - &&
      unzip -q /tmp/awscliv2.zip -d /tmp/ && sudo /tmp/aws/install && rm -rf /tmp/aws /tmp/awscliv2.zip
    '
  fi
else
  skip "AWS CLI (no incluido en perfil $PROFILE)"
fi

# ---------------------------------------------------------------------------
# Fase 4: Configuración de OpenCode (crear opencode.json si no existe)
# ---------------------------------------------------------------------------
phase "Configuración de OpenCode"

CONFIG_ROOT=${XDG_CONFIG_HOME:-"$HOME/.config"}
OC_FILE="${OPENCODE_CONFIG_FILE:-$CONFIG_ROOT/opencode/opencode.json}"

ensure_opencode_config() {
  local config_dir
  config_dir=$(dirname "$OC_FILE")

  if [[ -f "$OC_FILE" ]]; then
    if jq empty "$OC_FILE" >/dev/null 2>&1; then
      ok "opencode.json existe y es JSON válido"
      return 0
    else
      local backup
      backup="${OC_FILE}.bak.$(date +%s)"
      cp "$OC_FILE" "$backup" 2>/dev/null || true
      chmod 600 "$backup" 2>/dev/null || true
      critical "opencode.json existe pero no es JSON válido"
      critical "  Backup creado: $backup"
      critical "  Corrige el JSON o elimina el archivo para regenerarlo."
      return 1
    fi
  fi

  run mkdir -p "$config_dir"

  if [[ $DRY_RUN == true ]]; then
    OC_FILE=$(mktemp /tmp/opencode.json.XXXXXXXX)
  else
    local tmp
    tmp=$(mktemp "$config_dir/opencode.json.XXXXXXXX")
    printf '{\n  "$schema": "https://opencode.ai/config.json",\n  "plugin": [],\n  "mcp": {}\n}\n' > "$tmp"

    if ! jq empty "$tmp" >/dev/null 2>&1; then
      critical "JSON generado no es válido"
      rm -f "$tmp"
      return 1
    fi

    mv "$tmp" "$OC_FILE"
    chmod 600 "$OC_FILE"
  fi
  ok "opencode.json creado en $OC_FILE"
}

ensure_opencode_config

# ---------------------------------------------------------------------------
# Fase 5: Docker
# ---------------------------------------------------------------------------
if profile_includes "$PROFILE" "tools" "docker"; then
  if [[ $SKIP_DOCKER == true ]]; then
    skip 'Docker omitido (--skip-docker)'
  else
    phase "Docker"
    if command -v docker >/dev/null 2>&1; then
      ok "Docker ya instalado ($(docker --version 2>/dev/null))"
    else
      info 'Instalando Docker...'
      run bash -c 'curl -fsSL https://get.docker.com | sh'
      run sudo usermod -aG docker "$USER"
      info "Docker instalado. Cierra sesión y vuelve a entrar para usar Docker sin sudo."
    fi
  fi
else
  skip 'Docker (no incluido en perfil)'
fi

# ---------------------------------------------------------------------------
# Fase 6: Plugins de OpenCode
# ---------------------------------------------------------------------------
phase "Plugins de OpenCode"

if profile_includes "$PROFILE" "plugins" "ponytail"; then
  PLUGIN_PACKAGE=$(parse_nested_value "plugins" "ponytail" "package")
  PLUGIN_LIST=$(jq -r '(.plugin // [])[]' "$OC_FILE" 2>/dev/null || true)
  PLUGIN_BASE="${PLUGIN_PACKAGE%@*}"
  if echo "$PLUGIN_LIST" | grep -qxF "$PLUGIN_PACKAGE"; then
    ok "Ponytail ya registrado ($PLUGIN_PACKAGE)"
  elif echo "$PLUGIN_LIST" | grep -q "^${PLUGIN_BASE}"; then
    info "Reemplazando Ponytail por versión exacta ($PLUGIN_PACKAGE)..."
    if [[ $DRY_RUN == true ]]; then
      info "[simulado] Reemplazar $PLUGIN_BASE* por $PLUGIN_PACKAGE"
    else
      TMP=$(mktemp)
      jq --arg p "$PLUGIN_PACKAGE" --arg b "$PLUGIN_BASE" '.plugin = ((.plugin // []) | map(select(startswith($b) | not)) + [$p])' "$OC_FILE" > "$TMP" && mv "$TMP" "$OC_FILE"
      chmod 600 "$OC_FILE"
      ok "Ponytail reemplazado por versión exacta ($PLUGIN_PACKAGE)"
    fi
  else
    info "Registrando Ponytail ($PLUGIN_PACKAGE)..."
    if [[ $DRY_RUN == true ]]; then
      info "[simulado] Agregar $PLUGIN_PACKAGE como plugin"
    else
      TMP=$(mktemp)
      jq --arg p "$PLUGIN_PACKAGE" '.plugin = ((.plugin // []) + [$p])' "$OC_FILE" > "$TMP" && mv "$TMP" "$OC_FILE"
      chmod 600 "$OC_FILE"
      ok "Ponytail registrado en opencode.json ($PLUGIN_PACKAGE)"
    fi
  fi
else
  skip 'Ponytail (no incluido en perfil)'
fi

# ---------------------------------------------------------------------------
# Fase 7: Configuración del harness
# ---------------------------------------------------------------------------
phase "Configuración del harness"

if [[ -f "$ROOT_DIR/scripts/install.sh" ]]; then
  info 'Ejecutando install.sh...'
  run bash "$ROOT_DIR/scripts/install.sh"
else
  info 'install.sh no encontrado'
fi

if command -v gentle-ai >/dev/null 2>&1; then
  info 'Sincronizando skills con Gentle AI...'
  run gentle-ai skill-registry refresh --force 2>/dev/null || true
  run gentle-ai sync -skill task-lifecycle 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Fase 8: Servidores MCP (transaccional — candidato único + validación + backup)
# ---------------------------------------------------------------------------
phase "Servidores MCP"

TMP_CANDIDATE=$(mktemp)
cp "$OC_FILE" "$TMP_CANDIDATE"
MCP_ADDED=0
MCP_UPDATED=0
MCP_SKIPPED=0

_mcp_jq() {
  local tmp_next
  tmp_next=$(mktemp)
  jq "$@" "$TMP_CANDIDATE" > "$tmp_next" && mv "$tmp_next" "$TMP_CANDIDATE"
}

# Compare desired vs current for a managed MCP, apply with drift check
_reconcile_mcp() {
  local name=$1 desired=$2
  local current
  current=$(jq --arg n "$name" '.mcp[$n]' "$TMP_CANDIDATE" 2>/dev/null || echo "null")

  if [[ "$current" == "$desired" ]]; then
    ok "MCP $name configurado, idéntico al manifest"
    return
  fi

  if [[ -f "$STATE_FILE" ]]; then
    local current_hash last_hash
    current_hash=$(echo "$current" | sha256sum | cut -d' ' -f1)
    last_hash=$(jq -r --arg n "$name" '.mcps[$n].lastAppliedHash // ""' "$STATE_FILE" 2>/dev/null || echo "")
    if [[ -n "$last_hash" && "$current_hash" != "$last_hash" ]]; then
      warn "MCP $name modificado externamente desde la última aplicación. Conservando configuración personalizada."
      MCP_SKIPPED=$((MCP_SKIPPED + 1))
      return
    fi
  fi

  _mcp_jq --arg n "$name" --argjson d "$desired" '.mcp[$n] = $d'
  info "MCP $name actualizado (configuración administrada diferente del manifest)"
  MCP_UPDATED=$((MCP_UPDATED + 1))
}

MANAGED_MCPS=()

while IFS= read -r name; do
  [[ -z "$name" ]] && continue
  if ! profile_includes "$PROFILE" "mcps" "$name"; then
    skip "MCP $name (no incluido en perfil $PROFILE)"
    continue
  fi

  type=$(parse_mcp_field "$name" "type")
  cmd=$(parse_mcp_field "$name" "command")
  skip_mcp=false
  desired=""

  if [[ $type == local && -n "$cmd" ]]; then
    if echo "$cmd" | jq -e '. | type == "array"' >/dev/null 2>&1; then
      cmd_array=$cmd
    else
      cmd_array=$(printf '%s' "$cmd" | jq -R 'split(" ")')
    fi
    cmd_first=$(echo "$cmd_array" | jq -r '.[0] // ""')
    cmd_enabled=true
    if [[ "$cmd_first" == "docker" ]] && { [[ $SKIP_DOCKER == true ]] || ! command -v docker >/dev/null 2>&1; }; then
      cmd_enabled=false
      warn "MCP $name requiere Docker — registrado como deshabilitado"
    fi
    desired=$(jq -n --argjson cmd "$cmd_array" --arg e "$cmd_enabled" \
      '{type: "local", command: $cmd, enabled: ($e == "true")}')
  elif [[ $type == remote ]]; then
    url=$(parse_mcp_field "$name" "url")
    if [[ -n "$url" ]]; then
      desired=$(jq -n --arg u "$url" '{type: "remote", url: $u, enabled: true}')
      oauth_raw=$(parse_mcp_field "$name" "oauth_required")
      if [[ "$oauth_raw" == "true" ]]; then
        desired=$(echo "$desired" | jq '. + {oauth: {}}')
      elif [[ "$oauth_raw" == "false" ]]; then
        desired=$(echo "$desired" | jq '. + {oauth: false}')
      fi
      headers_json=$(parse_mcp_headers_json "$name")
      if [[ "$headers_json" != "{}" ]]; then
        desired=$(echo "$desired" | jq --argjson h "$headers_json" '. + {headers: $h}')
      fi
    else
      skip "MCP remoto $name: sin URL. Configúralo manualmente en opencode.json"
      skip_mcp=true
    fi
  else
    skip "MCP $name: tipo desconocido '$type'. Configúralo manualmente"
    skip_mcp=true
  fi

  $skip_mcp && continue

  exists=$(jq --arg n "$name" '.mcp // {} | has($n)' "$TMP_CANDIDATE" 2>/dev/null || false)
  if [[ $exists == true ]]; then
    if [[ -f "$STATE_FILE" ]]; then
      if ! jq -e --arg n "$name" '.mcps | has($n)' "$STATE_FILE" >/dev/null 2>&1; then
        warn "MCP $name personalizado, no administrado por bootstrap. Omite actualización."
        MCP_SKIPPED=$((MCP_SKIPPED + 1))
        continue
      fi
    else
      current=$(jq --arg n "$name" '.mcp[$n]' "$TMP_CANDIDATE" 2>/dev/null || echo "null")
      if [[ "$current" != "$desired" ]]; then
        warn "MCP $name personalizado (sin state, diferente del manifest). Omite actualización."
        MCP_SKIPPED=$((MCP_SKIPPED + 1))
        continue
      fi
    fi
    _reconcile_mcp "$name" "$desired"
  else
    if [[ $DRY_RUN == true ]]; then
      info "[simulado] jq injectaría MCP $name"
      MCP_ADDED=$((MCP_ADDED + 1))
      continue
    fi
    _mcp_jq --arg n "$name" --argjson d "$desired" '.mcp[$n] = $d'
    ok "MCP $name registrado en candidato"
    MCP_ADDED=$((MCP_ADDED + 1))
  fi
  MANAGED_MCPS+=("$name")
done < <(parse_mcp_names)

_build_state() {
  local src=$1 dst=$2
  mkdir -p "$(dirname "$dst")" "$STATE_DIR"
  existing=$(cat "$STATE_FILE" 2>/dev/null || echo "{}")
  new_state="{}"
  for m in "${MANAGED_MCPS[@]}"; do
    val=$(jq --arg n "$m" '.mcp[$n]' "$src" 2>/dev/null || echo "null")
    hash=$(echo "$val" | sha256sum | cut -d' ' -f1)
    new_state=$(echo "$new_state" | jq --arg n "$m" --arg h "$hash" '.mcps[$n] = {lastAppliedHash: $h}')
  done
  echo "$existing" "$new_state" | jq -s '.[0] * .[1]' > "$dst"
  chmod 600 "$dst"
}

if [[ $DRY_RUN == false ]]; then
  OC_SCHEMA="$ROOT_DIR/tests/fixtures/opencode-config.schema.json"
  TMP_STATE=$(mktemp)

  if (( MCP_ADDED > 0 || MCP_UPDATED > 0 )); then
    if ! jq empty "$TMP_CANDIDATE" >/dev/null 2>&1; then
      critical "Candidato JSON inválido — cambios NO aplicados"
      rm -f "$TMP_CANDIDATE" "$TMP_STATE"
    elif ! python3 "$ROOT_DIR/scripts/validate-opencode-config.py" \
         --config "$TMP_CANDIDATE" --schema "$OC_SCHEMA" >/dev/null 2>&1; then
      critical "Candidato no pasa validación de schema — cambios NO aplicados"
      rm -f "$TMP_CANDIDATE" "$TMP_STATE"
    elif (( ${#MANAGED_MCPS[@]} > 0 )) && ! _build_state "$TMP_CANDIDATE" "$TMP_STATE"; then
      critical "No se pudo construir state — cambios NO aplicados"
      rm -f "$TMP_CANDIDATE" "$TMP_STATE"
    else
      BACKUP_OC="${OC_FILE}.bak.$(date +%s)"
      cp "$OC_FILE" "$BACKUP_OC" 2>/dev/null || true
      chmod 600 "$BACKUP_OC" 2>/dev/null || true
      if (( ${#MANAGED_MCPS[@]} > 0 )); then
        BACKUP_STATE="${STATE_FILE}.bak.$(date +%s)"
        cp "$STATE_FILE" "$BACKUP_STATE" 2>/dev/null || true
        chmod 600 "$BACKUP_STATE" 2>/dev/null || true
      fi

      mv "$TMP_CANDIDATE" "$OC_FILE" && chmod 600 "$OC_FILE"
      OC_MOVED=$?
      STATE_MOVED=0
      if (( ${#MANAGED_MCPS[@]} > 0 )); then
        mv "$TMP_STATE" "$STATE_FILE" && chmod 600 "$STATE_FILE"
        STATE_MOVED=$?
      fi

      if (( OC_MOVED == 0 && STATE_MOVED == 0 )); then
        summary="${MCP_ADDED} nuevos"
        [[ $MCP_UPDATED -gt 0 ]] && summary="${summary}, ${MCP_UPDATED} existentes verificados"
        [[ $MCP_SKIPPED -gt 0 ]] && summary="${summary}, ${MCP_SKIPPED} personalizados omitidos"
        ok "Configuración aplicada (${summary})"
        [[ -f "$BACKUP_OC" ]] && info "Backup: $BACKUP_OC"
      else
        critical "Fallo al escribir configuración o state — restaurando backups"
        [[ -f "$BACKUP_OC" ]] && cp "$BACKUP_OC" "$OC_FILE" 2>/dev/null || true
        [[ -f "$BACKUP_STATE" ]] && cp "$BACKUP_STATE" "$STATE_FILE" 2>/dev/null || true
        rm -f "$TMP_CANDIDATE" "$TMP_STATE"
      fi
    fi
  else
    if (( ${#MANAGED_MCPS[@]} > 0 )); then
      if _build_state "$OC_FILE" "$TMP_STATE"; then
        BACKUP_STATE="${STATE_FILE}.bak.$(date +%s)"
        cp "$STATE_FILE" "$BACKUP_STATE" 2>/dev/null || true
        chmod 600 "$BACKUP_STATE" 2>/dev/null || true
        mv "$TMP_STATE" "$STATE_FILE" && chmod 600 "$STATE_FILE" || {
          critical "Fallo al escribir state — restaurando backup"
          [[ -f "$BACKUP_STATE" ]] && cp "$BACKUP_STATE" "$STATE_FILE" 2>/dev/null || true
        }
      fi
    fi
    summary=""
    [[ $MCP_SKIPPED -gt 0 ]] && summary="${MCP_SKIPPED} personalizados omitidos"
    rm -f "$TMP_CANDIDATE" "$TMP_STATE"
    if [[ -n "$summary" ]]; then
      ok "MCPs: ${summary}"
    else
      ok "No hay MCPs nuevos que agregar"
    fi
  fi
fi

info "MCPs excluidos del bootstrap: alegra-test (incompatible), remotos sin url (configurar manualmente)"

# ---------------------------------------------------------------------------
# Fase 8: Verificación
# ---------------------------------------------------------------------------
phase "Verificación"

if [[ -f "$ROOT_DIR/scripts/doctor.sh" ]]; then
  info 'Ejecutando doctor.sh...'
  doctor_args=(--profile "$PROFILE" --strict --skip-oauth)
  if $SKIP_DOCKER; then doctor_args+=(--skip-docker); fi
  if run bash "$ROOT_DIR/scripts/doctor.sh" "${doctor_args[@]}"; then
    ok 'Bootstrap completado y saludable'
  else
    printf '\n========================================\n'
    printf '  Bootstrap completado con acciones pendientes\n'
    if [[ $DRY_RUN == true ]]; then
      printf '  (simulación, no se realizaron cambios)\n'
    fi
    printf '========================================\n'
    printf '\nRevisa los errores críticos arriba antes de usar el harness.\n'
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# Resumen
# ---------------------------------------------------------------------------
printf '\n========================================\n'
printf '  Bootstrap completado y saludable\n'
if [[ $DRY_RUN == true ]]; then
  printf '  (simulación, no se realizaron cambios)\n'
fi
printf '========================================\n'
printf '\nPróximos pasos:\n'
printf '  1. Autentica MCPs OAuth:\n'

while IFS= read -r name; do
  configured=$(jq --arg n "$name" '.mcp // {} | has($n)' "$OC_FILE" 2>/dev/null || false)
  [[ $configured == true ]] || continue
  oauth=$(parse_mcp_field "$name" "oauth_required")
  if [[ "$oauth" == "true" ]]; then
    printf '     opencode mcp auth %s\n' "$name"
  fi
done < <(parse_mcp_names)

printf '     Configura GITHUB_PERSONAL_ACCESS_TOKEN para el MCP de GitHub\n'
printf '     https://github.com/settings/tokens (permisos: repo, read:org, read:user)\n'

printf '\n  2. Verifica estado con doctor.sh\n'
printf '     bash scripts/doctor.sh\n'
printf '\n  3. Si es primera instalación, reinicia OpenCode\n'
printf '\n'
