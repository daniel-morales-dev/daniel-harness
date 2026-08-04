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

# --help debe ejecutarse antes de crear cualquier estado o lock
for arg in "$@"; do
  if [[ "$arg" == "--help" || "$arg" == "-h" ]]; then
    printf 'Uso: bootstrap.sh [--dry-run] [--profile core|alegra|migration|full] [--skip-docker] [--experimental-data-tools]\n'
    exit 0
  fi
done

DRY_RUN=false
SKIP_DOCKER=false
PROFILE=core
EXPERIMENTAL_DATA_TOOLS=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --skip-docker) SKIP_DOCKER=true; shift ;;
    --profile) PROFILE=$2; shift 2 ;;
    --profile=*) PROFILE=${1#*=}; shift ;;
    --experimental-data-tools) EXPERIMENTAL_DATA_TOOLS=true; shift ;;
    --help|-h) printf 'Uso: bootstrap.sh [--dry-run] [--profile core|alegra|migration|full] [--skip-docker] [--experimental-data-tools]\n'; exit 0 ;;
    *) printf 'Argumento desconocido: %s\n' "$1" >&2; exit 1 ;;
  esac
done

LOCAL_BIN=${DANIEL_HARNESS_BIN_DIR:-"$HOME/.local/bin"}
NPM_BIN=""

if [[ $DRY_RUN == false ]]; then
  mkdir -p "$LOCAL_BIN"
  if command -v npm >/dev/null 2>&1; then
    NPM_BIN="$(npm prefix -g 2>/dev/null || true)/bin"
  fi
fi
export PATH="$LOCAL_BIN:$PATH"

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

# Lock de arranque solo si no es dry-run
if [[ $DRY_RUN == false ]]; then
  LOCK_FILE="$STATE_DIR/.bootstrap.lock"
  mkdir -p "$STATE_DIR" 2>/dev/null || { critical "No se pudo crear $STATE_DIR"; exit 1; }
  if ! exec 200>"$LOCK_FILE" 2>/dev/null; then
    critical "No se pudo crear lock (estado no escribible)"
    exit 1
  elif ! flock -n 200 2>/dev/null; then
    critical "Otro bootstrap en ejecución (lock: $LOCK_FILE)"
    exit 1
  fi
fi

if [[ ! -f "$MANIFEST" ]]; then
  printf 'error: no se encuentra %s\n' "$MANIFEST" >&2
  exit 1
fi

if [[ $DRY_RUN == true ]]; then
  printf '\n[preflight] Simulación (--dry-run)\n\n'
fi

# ---------------------------------------------------------------------------
# Fase 0: Preflight
# ---------------------------------------------------------------------------
phase "Preflight"

if [[ ! -f /etc/os-release ]] || ! grep -qi 'ubuntu' /etc/os-release 2>/dev/null; then
  printf '  [aviso] Sistema operativo no verificado como Ubuntu\n'
fi

if ! command -v sudo >/dev/null 2>&1; then
  if [[ $DRY_RUN == true ]]; then
    printf '  [aviso] sudo no está instalado; se requeriría para la instalación real\n'
  else
    printf 'error: sudo es necesario\n' >&2
    exit 1
  fi
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
# Fase 2: Runtime Python (venv administrado)
# ---------------------------------------------------------------------------
phase "Runtime Python"

VENV_DIR="${DANIEL_HARNESS_RUNTIME_DIR:-$HOME/.local/share/daniel-harness/runtime-venv}"
RQ_FILE="$ROOT_DIR/requirements-runtime.txt"
STATE_VENV_HASH="$STATE_DIR/venv-hash.txt"

_create_venv() {
  python3 -m venv "$VENV_DIR"
      "$VENV_DIR/bin/python" -m pip install --quiet --upgrade pip
    if [[ -f "$RQ_FILE" ]]; then
      "$VENV_DIR/bin/python" -m pip install --quiet -r "$RQ_FILE"
      mkdir -p "$(dirname "$STATE_VENV_HASH")"
      sha256sum "$RQ_FILE" | cut -d' ' -f1 > "$STATE_VENV_HASH"
  fi
  ok "Venv creado en $VENV_DIR"
}

if [[ $EXPERIMENTAL_DATA_TOOLS == false ]]; then
  if [[ $DRY_RUN == true ]]; then
    info "[simulado] Runtime venv omitido (data tools deshabilitadas)"
  else
    ok "Runtime venv omitido (data tools deshabilitadas, usa --experimental-data-tools)"
  fi
elif [[ $DRY_RUN == true ]]; then
  info "[simulado] Se verificaría/crearía runtime venv en $VENV_DIR"
elif [[ ! -f "$VENV_DIR/bin/python" ]]; then
  info "Creando runtime venv..."
  _create_venv
elif [[ -f "$RQ_FILE" ]]; then
  current_hash=$(sha256sum "$RQ_FILE" | cut -d' ' -f1)
  applied_hash=$(cat "$STATE_VENV_HASH" 2>/dev/null || echo "")
  if [[ "$current_hash" != "$applied_hash" ]]; then
    info "requirements-runtime.txt changed, updating venv..."
    _create_venv
  else
    ok "Runtime venv actualizado"
  fi
else
  ok "Runtime venv presente"
fi

# ---------------------------------------------------------------------------
# Fase 3: NVM + Node
# ---------------------------------------------------------------------------
phase "NVM + Node.js"

NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
_install_nvm() {
  local tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/daniel-harness-nvm.XXXXXXXX") || {
    critical "No se pudo crear temporal para NVM"
    return 1
  }
  mkdir -p "$NVM_DIR" || { rm -f "$tmp"; critical "No se pudo crear $NVM_DIR"; return 1; }
  if ! curl -fsSL \
    "https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh" \
    -o "$tmp"; then
    rm -f "$tmp"
    critical "No se pudo descargar el instalador de NVM"
    return 1
  fi
  if ! bash "$tmp"; then
    rm -f "$tmp"
    critical "El instalador de NVM terminó con error"
    return 1
  fi
  rm -f "$tmp"
  if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
    critical "NVM no quedó instalado en $NVM_DIR"
    return 1
  fi
}

if [[ -s "$NVM_DIR/nvm.sh" ]]; then
  ok "NVM ya instalado ($(source "$NVM_DIR/nvm.sh" && nvm --version 2>/dev/null))"
else
  info 'Instalando NVM...'
  run _install_nvm || exit 1
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

source "$ROOT_DIR/scripts/lib/tool-path.sh"

install_tool_if_in_profile "opencode"  "OpenCode"  "command -v opencode"  "curl -fsSL https://opencode.ai/install | bash"
_ensure_tool_visible "opencode" "$HOME/.opencode/bin/opencode" || exit 1

install_tool_if_in_profile "gentle-ai" "Gentle AI" "command -v gentle-ai" "curl -fsSL https://raw.githubusercontent.com/Gentleman-Programming/gentle-ai/main/scripts/install.sh | bash"
_ensure_tool_visible "gentle-ai" "$LOCAL_BIN/gentle-ai" || exit 1

install_tool_if_in_profile "engram"    "Engram"    "command -v engram"    "npm install -g @engram-ai-memory/cli"
_ensure_tool_visible "engram" "${NPM_BIN:+$NPM_BIN/engram}" "$LOCAL_BIN/engram" || exit 1

if [[ -s "$NVM_DIR/nvm.sh" ]]; then
  . "$NVM_DIR/nvm.sh"
elif [[ $DRY_RUN == true ]]; then
  info "[simulado] NVM estaría disponible después de la instalación. CodeGraph puede fallar sin Node."
fi
CG_INSTALL=$(parse_nested_value "user_tools" "codegraph" "install")
install_tool_if_in_profile "codegraph" "CodeGraph" "command -v codegraph" "$CG_INSTALL"
_ensure_tool_visible "codegraph" "${NPM_BIN:+$NPM_BIN/codegraph}" "$LOCAL_BIN/codegraph" || exit 1

install_tool_if_in_profile "rtk"       "RTK"       "command -v rtk"       "curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | bash"
_ensure_tool_visible "rtk" "$LOCAL_BIN/rtk" || exit 1

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

AWS_VERSION=$(parse_nested_value "user_tools" "aws" "version")
AWS_URL=$(parse_nested_value "user_tools" "aws" "url")
AWS_SHA256=$(parse_nested_value "user_tools" "aws" "sha256")

if profile_includes "$PROFILE" "tools" "aws"; then
  if command -v aws >/dev/null 2>&1; then
    ok "AWS CLI ya instalado ($(aws --version 2>/dev/null || true))"
  else
    info 'Instalando AWS CLI v'"$AWS_VERSION"'...'
    run bash -c '
      tmp_dir=$(mktemp -d) && trap "rm -rf \"$tmp_dir\"" EXIT &&
      cd "$tmp_dir" &&
      curl -fsSL "'"$AWS_URL"'" -o awscliv2.zip &&
      echo "'"$AWS_SHA256"'  awscliv2.zip" | sha256sum -c - &&
      unzip -q awscliv2.zip &&
      sudo ./aws/install
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

# Journal para transacción crash-consistent
JOURNAL_FILE="$STATE_DIR/.bootstrap-journal.json"
TMP_CANDIDATE=""
TMP_STATE=""
BACKUP_OC=""
BACKUP_STATE=""

# Recuperar transacción incompleta de una ejecución anterior
_recover_incomplete_transaction() {
  trap '' EXIT INT TERM
  local j_oc j_st b_oc b_st e_oc e_st
  j_oc=$(jq -r '.configFile // ""' "$JOURNAL_FILE" 2>/dev/null || echo "")
  j_st=$(jq -r '.stateFile // ""' "$JOURNAL_FILE" 2>/dev/null || echo "")
  b_oc=$(jq -r '.backupConfig // ""' "$JOURNAL_FILE" 2>/dev/null || echo "")
  b_st=$(jq -r '.backupState // ""' "$JOURNAL_FILE" 2>/dev/null || echo "")
  e_oc=$(jq -r '.existedBeforeConfig // false' "$JOURNAL_FILE" 2>/dev/null || echo "false")
  e_st=$(jq -r '.existedBeforeState // false' "$JOURNAL_FILE" 2>/dev/null || echo "false")
  warn "Recuperando transacción incompleta"
  if [[ -n "$b_oc" && -f "$b_oc" ]]; then
    cp "$b_oc" "$j_oc" || { critical "No se pudo restaurar backup de config"; return 1; }
    chmod 600 "$j_oc" || { critical "No se pudo fijar permiso de config"; return 1; }
  elif [[ "$e_oc" == "false" && -n "$j_oc" ]]; then
    rm -f "$j_oc" || { critical "No se pudo eliminar config creada en transaccion fallida"; return 1; }
  fi
  if [[ -n "$b_st" && -f "$b_st" ]]; then
    cp "$b_st" "$j_st" || { critical "No se pudo restaurar backup de state"; return 1; }
    chmod 600 "$j_st" || { critical "No se pudo fijar permiso de state"; return 1; }
  elif [[ "$e_st" == "false" && -n "$j_st" ]]; then
    rm -f "$j_st" || { critical "No se pudo eliminar state creado en transaccion fallida"; return 1; }
  fi
  rm -f "$JOURNAL_FILE"
}
if [[ -f "$JOURNAL_FILE" ]]; then
  _recover_incomplete_transaction || { critical "Recuperación fallida — journal conservado en $JOURNAL_FILE"; exit 1; }
fi

# Trap para transacción actual
trap _rollback EXIT
trap '_rollback; exit 1' INT TERM

_rollback() {
  local rc=$?
  trap '' EXIT INT TERM
  if [[ -f "$JOURNAL_FILE" ]]; then
    local j_oc j_st b_oc b_st e_oc e_st restore_failed=false
    j_oc=$(jq -r '.configFile // ""' "$JOURNAL_FILE" 2>/dev/null || echo "")
    j_st=$(jq -r '.stateFile // ""' "$JOURNAL_FILE" 2>/dev/null || echo "")
    b_oc=$(jq -r '.backupConfig // ""' "$JOURNAL_FILE" 2>/dev/null || echo "")
    b_st=$(jq -r '.backupState // ""' "$JOURNAL_FILE" 2>/dev/null || echo "")
    e_oc=$(jq -r '.existedBeforeConfig // false' "$JOURNAL_FILE" 2>/dev/null || echo "false")
    e_st=$(jq -r '.existedBeforeState // false' "$JOURNAL_FILE" 2>/dev/null || echo "false")
    critical "Rollback transacción incompleta (fase: $(jq -r '.phase // "unknown"' "$JOURNAL_FILE" 2>/dev/null || echo "unknown"))"
    if [[ -n "$b_oc" && -f "$b_oc" ]]; then
      cp "$b_oc" "$j_oc" || { critical "Rollback: no se pudo restaurar config"; restore_failed=true; }
      chmod 600 "$j_oc" || { critical "Rollback: no se pudo fijar permiso de config"; restore_failed=true; }
    elif [[ "$e_oc" == "false" && -n "$j_oc" ]]; then
      rm -f "$j_oc" || { critical "Rollback: no se pudo eliminar config"; restore_failed=true; }
    fi
    if [[ -n "$b_st" && -f "$b_st" ]]; then
      cp "$b_st" "$j_st" || { critical "Rollback: no se pudo restaurar state"; restore_failed=true; }
      chmod 600 "$j_st" || { critical "Rollback: no se pudo fijar permiso de state"; restore_failed=true; }
    elif [[ "$e_st" == "false" && -n "$j_st" ]]; then
      rm -f "$j_st" || { critical "Rollback: no se pudo eliminar state"; restore_failed=true; }
    fi
    $restore_failed && critical "Rollback: journal conservado para reintento manual" || _clear_journal
  fi
  [[ -n "$TMP_CANDIDATE" && -f "$TMP_CANDIDATE" ]] && rm -f "$TMP_CANDIDATE"
  [[ -n "$TMP_STATE" && -f "$TMP_STATE" ]] && rm -f "$TMP_STATE"
  exit $rc
}

# Journal de transacción con paths exactos de backup
_write_journal() {
  local phase=$1 b_oc=$2 b_st=$3 e_oc=$4 e_st=$5
  jq -n --arg p "$phase" \
    --arg oc "$OC_FILE" \
    --arg st "$STATE_FILE" \
    --arg b_oc "${b_oc:-}" \
    --arg b_st "${b_st:-}" \
    --argjson e_oc "${e_oc:-false}" \
    --argjson e_st "${e_st:-false}" \
    '{phase: $p, configFile: $oc, stateFile: $st, backupConfig: $b_oc, backupState: $b_st, existedBeforeConfig: $e_oc, existedBeforeState: $e_st}' > "$JOURNAL_FILE"
}
_clear_journal() { rm -f "$JOURNAL_FILE"; }

_check_failpoint() {
  local point=$1
  if [[ "${DH_TEST_MODE:-0}" == "1" && "$DH_FAIL_AT" == "$point" ]]; then
    critical "Failpoint alcanzado: $point"
    exit 1
  fi
}

# Registrar si los archivos existían antes de la transacción
OC_EXISTED_BEFORE=false
[[ -f "$OC_FILE" ]] && OC_EXISTED_BEFORE=true
STATE_EXISTED_BEFORE=false
[[ -f "$STATE_FILE" ]] && STATE_EXISTED_BEFORE=true

ensure_opencode_config() {
  if [[ -f "$OC_FILE" ]]; then
    if jq empty "$OC_FILE" >/dev/null 2>&1; then
      ok "opencode.json existe y es JSON válido"
      return 0
    else
      local backup
      backup="${OC_FILE}.bak.$(date +%s)"
      cp "$OC_FILE" "$backup" || { critical "No se pudo crear backup de opencode.json inválido"; return 1; }
      chmod 600 "$backup" || { critical "No se pudo fijar permisos del backup"; return 1; }
      critical "opencode.json existe pero no es JSON válido"
      critical "  Backup creado: $backup"
      critical "  Corrige el JSON o elimina el archivo para regenerarlo."
      return 1
    fi
  fi

  if [[ $DRY_RUN == true ]]; then
    info "[simulado] Se crearía opencode.json en $OC_FILE"
    return 0
  fi

  # Primer arranque: no crear archivo real — solo validar que podemos crearlo
  if ! jq empty <<< '{"$schema":"https://opencode.ai/config.json","plugin":[],"mcp":{}}' >/dev/null 2>&1; then
    critical "JSON base no es válido"
    return 1
  fi
  ok "Directorio de configuración accesible"
}

ensure_opencode_config

# Crear candidato temprano — plugins y MCPs comparten una transacción
_determine_candidate() {
  local cfg_dir
  cfg_dir=$(dirname "$OC_FILE")
  local base_json='{"$schema":"https://opencode.ai/config.json","plugin":[],"mcp":{}}'

  if [[ $DRY_RUN == true ]] && [[ ! -d "$cfg_dir" ]]; then
    TMP_CANDIDATE=$(mktemp /tmp/.opencode.json.XXXXXXXX)
    printf '{}' > "$TMP_CANDIDATE"
    return
  fi

  run mkdir -p "$cfg_dir"
  TMP_CANDIDATE=$(mktemp "$cfg_dir/.opencode.json.XXXXXXXX")

  if [[ -f "$OC_FILE" ]]; then
    cp "$OC_FILE" "$TMP_CANDIDATE"
  else
    # Primer arranque: candidato con JSON base, archivo real se crea en transacción
    printf '%s\n' "$base_json" > "$TMP_CANDIDATE"
    if ! jq empty "$TMP_CANDIDATE" >/dev/null 2>&1; then
      critical "JSON base inválido en candidato"
      rm -f "$TMP_CANDIDATE"
      exit 1
    fi
  fi
}
_determine_candidate

_candidate_jq() {
  local tmp_next
  tmp_next=$(mktemp)
  jq "$@" "$TMP_CANDIDATE" > "$tmp_next" && mv "$tmp_next" "$TMP_CANDIDATE"
}

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
      _candidate_jq --arg p "$PLUGIN_PACKAGE" --arg b "$PLUGIN_BASE" '.plugin = ((.plugin // []) | map(select(startswith($b) | not)) + [$p])'
      ok "Ponytail reemplazado por versión exacta ($PLUGIN_PACKAGE)"
    fi
  else
    info "Registrando Ponytail ($PLUGIN_PACKAGE)..."
    if [[ $DRY_RUN == true ]]; then
      info "[simulado] Agregar $PLUGIN_PACKAGE como plugin"
    else
      _candidate_jq --arg p "$PLUGIN_PACKAGE" '.plugin = ((.plugin // []) + [$p])'
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
  INSTALL_ARGS=()
  $EXPERIMENTAL_DATA_TOOLS && INSTALL_ARGS+=(--experimental-data-tools)
  info 'Ejecutando install.sh...'
  run bash "$ROOT_DIR/scripts/install.sh" "${INSTALL_ARGS[@]}"
else
  info 'install.sh no encontrado'
fi
_ensure_tool_visible "dh" "$LOCAL_BIN/dh" || exit 1

if command -v gentle-ai >/dev/null 2>&1; then
  info 'Sincronizando skills con Gentle AI...'
  run gentle-ai skill-registry refresh --force 2>/dev/null || true
  run gentle-ai sync -skill task-lifecycle 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Fase 8: Servidores MCP (crash-consistent transaction)
# ---------------------------------------------------------------------------
phase "Servidores MCP"

# TMP_CANDIDATE ya fue creado en la fase de configuración de OpenCode
# (plugins y MCPs comparten la misma transacción)
TMP_STATE=""
MCP_ADDED=0
MCP_UPDATED=0
MCP_SKIPPED=0

# Estados explicitos de reconciliacion via variable (seguro bajo set -e)
# RECONCILE_STATUS=unchanged|updated|drift-conflict
_reconcile_mcp() {
  local name=$1 desired=$2
  local current
  current=$(jq --arg n "$name" '.mcp[$n]' "$TMP_CANDIDATE" 2>/dev/null || echo "null")

  local desired_canonical current_canonical
  desired_canonical=$(echo "$desired" | jq -S -c . 2>/dev/null || echo "$desired")
  current_canonical=$(echo "$current" | jq -S -c . 2>/dev/null || echo "$current")

  if [[ "$current_canonical" == "$desired_canonical" ]]; then
    ok "MCP $name configurado, identico al manifest"
    RECONCILE_STATUS=unchanged
    return 0
  fi

  if [[ -f "$STATE_FILE" ]]; then
    local current_hash last_hash
    current_hash=$(echo "$current_canonical" | sha256sum | cut -d' ' -f1)
    last_hash=$(jq -r --arg n "$name" '.mcps[$n].lastAppliedHash // ""' "$STATE_FILE" 2>/dev/null || echo "")
    if [[ -n "$last_hash" && "$current_hash" != "$last_hash" ]]; then
      warn "MCP $name modificado externamente desde la ultima aplicacion. Conservando configuracion personalizada."
      MCP_SKIPPED=$((MCP_SKIPPED + 1))
      RECONCILE_STATUS=drift-conflict
      return 0
    fi
  fi

  _candidate_jq --arg n "$name" --argjson d "$desired" '.mcp[$n] = $d'
  info "MCP $name actualizado (configuracion administrada diferente del manifest)"
  MCP_UPDATED=$((MCP_UPDATED + 1))
  RECONCILE_STATUS=updated
  return 0
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
      # Full OAuth object (navi) takes priority
      oauth_json=$(parse_mcp_oauth_json "$name")
      if [[ "$oauth_json" != "{}" ]]; then
        desired=$(echo "$desired" | jq --argjson navi_oauth "$oauth_json" '. + {oauth: $navi_oauth}')
      else
        oauth_raw=$(parse_mcp_field "$name" "oauth_required")
        if [[ "$oauth_raw" == "true" ]]; then
          desired=$(echo "$desired" | jq '. + {oauth: {}}')
        elif [[ "$oauth_raw" == "false" ]]; then
          desired=$(echo "$desired" | jq '. + {oauth: false}')
        fi
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
    RECONCILE_STATUS=
    _reconcile_mcp "$name" "$desired"
    # drift-conflict: no trackear en state, preservar hash anterior
    [[ "$RECONCILE_STATUS" == "drift-conflict" ]] && continue
  else
    if [[ $DRY_RUN == true ]]; then
      info "[simulado] jq inyectaria MCP $name"
      MCP_ADDED=$((MCP_ADDED + 1))
      continue
    fi
    _candidate_jq --arg n "$name" --argjson d "$desired" '.mcp[$n] = $d'
    ok "MCP $name registrado en candidato"
    MCP_ADDED=$((MCP_ADDED + 1))
  fi
  MANAGED_MCPS+=("$name")
done < <(parse_mcp_names)

_build_state() {
  local src=$1 dst=$2
  _check_failpoint "build-state"
  mkdir -p "$(dirname "$dst")" "$STATE_DIR"
  existing=$(cat "$STATE_FILE" 2>/dev/null || echo "{}")
  new_state="{}"
  for m in "${MANAGED_MCPS[@]}"; do
    val=$(jq -S -c --arg n "$m" '.mcp[$n]' "$src" 2>/dev/null || echo "null")
    hash=$(echo "$val" | sha256sum | cut -d' ' -f1)
    new_state=$(echo "$new_state" | jq --arg n "$m" --arg h "$hash" '.mcps[$n] = {lastAppliedHash: $h}')
  done
  echo "$existing" "$new_state" | jq -s '.[0] * .[1]' > "$dst"
  chmod 600 "$dst"
}

if [[ $DRY_RUN == false ]]; then
  OC_SCHEMA="${DH_OC_SCHEMA:-$ROOT_DIR/tests/fixtures/opencode-config.schema.json}"
  TMP_STATE=$(mktemp "$STATE_DIR/.opencode-managed.json.XXXXXXXX")

  _check_failpoint "pre-validate"

  # Comparar hash canónico del candidato completo vs archivo real
  # Esto detecta cambios de plugins, MCPs o cualquier config administrada
  original_hash=$(jq -S -c . "$OC_FILE" 2>/dev/null | sha256sum | cut -d' ' -f1 || echo "no-file")
  candidate_hash=$(jq -S -c . "$TMP_CANDIDATE" 2>/dev/null | sha256sum | cut -d' ' -f1 || echo "no-candidate")
  config_changed=false
  [[ "$original_hash" != "$candidate_hash" ]] && config_changed=true

  if $config_changed; then
    if [[ "${DH_TEST_MODE:-0}" == "1" && "$DH_FAIL_AT" == "invalid-candidate" ]]; then
      echo '}}}}INVALID' >> "$TMP_CANDIDATE"
    fi
    if ! jq empty "$TMP_CANDIDATE" >/dev/null 2>&1; then
      critical "Candidato JSON invalido -- cambios NO aplicados"
      rm -f "$TMP_CANDIDATE" "$TMP_STATE"
      exit 1
    elif ! python3 "$ROOT_DIR/scripts/validate-opencode-config.py" \
         --config "$TMP_CANDIDATE" --schema "$OC_SCHEMA" >/dev/null 2>&1; then
      critical "Candidato no pasa validacion de schema -- cambios NO aplicados"
      rm -f "$TMP_CANDIDATE" "$TMP_STATE"
      exit 1
    else
      if (( ${#MANAGED_MCPS[@]} > 0 )) && ! _build_state "$TMP_CANDIDATE" "$TMP_STATE"; then
        critical "No se pudo construir state -- cambios NO aplicados"
        rm -f "$TMP_CANDIDATE" "$TMP_STATE"
        exit 1
      else
        # Backups solo si el archivo existía antes de la transacción
        BACKUP_OC=""
        BACKUP_STATE=""
        if $OC_EXISTED_BEFORE; then
          BACKUP_OC="${OC_FILE}.bak.$(date +%s)"
          cp "$OC_FILE" "$BACKUP_OC" || { critical "No se pudo crear backup de configuración"; exit 1; }
          chmod 600 "$BACKUP_OC" || { critical "No se pudo fijar permisos del backup de configuración"; exit 1; }
          ok "Backup creado: $BACKUP_OC"
        fi
        if $STATE_EXISTED_BEFORE && (( ${#MANAGED_MCPS[@]} > 0 )) && [[ -f "$STATE_FILE" ]]; then
          BACKUP_STATE="${STATE_FILE}.bak.$(date +%s)"
          cp "$STATE_FILE" "$BACKUP_STATE" || { critical "No se pudo crear backup de estado"; exit 1; }
          chmod 600 "$BACKUP_STATE" || { critical "No se pudo fijar permisos del backup de estado"; exit 1; }
          ok "Backup creado: $BACKUP_STATE"
        fi

        _check_failpoint "backup-config"
        _check_failpoint "backup-state"

        _write_journal "apply-config" "$BACKUP_OC" "" "$OC_EXISTED_BEFORE" "false"
        _check_failpoint "journal-write"
        _check_failpoint "move-config"
        mv "$TMP_CANDIDATE" "$OC_FILE"
        chmod 600 "$OC_FILE"
        _check_failpoint "chmod-config"
        _check_failpoint "crash-after-config"

        if (( ${#MANAGED_MCPS[@]} > 0 )); then
          _write_journal "apply-state" "$BACKUP_OC" "$BACKUP_STATE" "$OC_EXISTED_BEFORE" "$STATE_EXISTED_BEFORE"
          _check_failpoint "move-state"
          mv "$TMP_STATE" "$STATE_FILE"
          chmod 600 "$STATE_FILE"
          _check_failpoint "chmod-state"
          _check_failpoint "crash-after-state"
        fi

        _clear_journal
        info "Configuracion aplicada (plugins y/o MCPs actualizados)"
        $OC_EXISTED_BEFORE && info "Backup: $BACKUP_OC"
      fi
    fi
  else
    if (( ${#MANAGED_MCPS[@]} > 0 )); then
      if _build_state "$OC_FILE" "$TMP_STATE"; then
        BACKUP_STATE=""
        if $STATE_EXISTED_BEFORE && [[ -f "$STATE_FILE" ]]; then
          _check_failpoint "backup-state"
          BACKUP_STATE="${STATE_FILE}.bak.$(date +%s)"
          cp "$STATE_FILE" "$BACKUP_STATE" || { critical "No se pudo crear backup de estado"; exit 1; }
          chmod 600 "$BACKUP_STATE" || { critical "No se pudo fijar permisos del backup de estado"; exit 1; }
          ok "Backup creado: $BACKUP_STATE"
        fi

        _write_journal "apply-state" "" "$BACKUP_STATE" "$OC_EXISTED_BEFORE" "$STATE_EXISTED_BEFORE"
        _check_failpoint "move-state"
        mv "$TMP_STATE" "$STATE_FILE"
        _check_failpoint "chmod-state"
        chmod 600 "$STATE_FILE"
        _clear_journal
      fi
    fi
    summary=""
    [[ $MCP_SKIPPED -gt 0 ]] && summary="${MCP_SKIPPED} personalizados omitidos"
    rm -f "$TMP_CANDIDATE"
    if [[ -n "$summary" ]]; then
      ok "MCPs: ${summary}"
    else
      ok "No hay cambios en la configuracion"
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
  doctor_args=(--profile "$PROFILE" --strict --skip-oauth --install-check)
  if $SKIP_DOCKER; then doctor_args+=(--skip-docker); fi
  $EXPERIMENTAL_DATA_TOOLS && doctor_args+=(--experimental-data-tools)
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
  configured=$(jq --arg n "$name" '.mcp // {} | has($n)' "$OC_FILE" 2>/dev/null || printf 'false')
  [[ "$configured" == "true" ]] || continue
  oauth=$(parse_mcp_field "$name" "oauth_required")
  if [[ "$oauth" == "true" ]]; then
    printf '     opencode mcp auth %s\n' "$name"
  fi
done < <(parse_mcp_names) || true

printf '     Configura GITHUB_PERSONAL_ACCESS_TOKEN para el MCP de GitHub\n'
printf '     https://github.com/settings/tokens (permisos: repo, read:org, read:user)\n'

printf '\n  2. Verifica estado con doctor.sh\n'
printf '     bash scripts/doctor.sh\n'
printf '\n  3. Si es primera instalación, reinicia OpenCode\n'
printf '\n'
