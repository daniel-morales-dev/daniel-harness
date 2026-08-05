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
    printf 'Uso: bootstrap.sh [--dry-run] [--profile core|alegra|migration|full] [--skip-docker] [--reset-managed] [--non-interactive] [--experimental-data-tools]\n'
    exit 0
  fi
done

DRY_RUN=false
SKIP_DOCKER=false
PROFILE=core
CONNECT=false
RESET_MANAGED=false
NON_INTERACTIVE=false
EXPERIMENTAL_DATA_TOOLS=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --skip-docker) SKIP_DOCKER=true; shift ;;
    --connect) CONNECT=true; shift ;;
    --reset-managed) RESET_MANAGED=true; shift ;;
    --non-interactive) NON_INTERACTIVE=true; shift ;;
    --profile) PROFILE=$2; shift 2 ;;
    --profile=*) PROFILE=${1#*=}; shift ;;
    --experimental-data-tools) EXPERIMENTAL_DATA_TOOLS=true; shift ;;
    --help|-h) printf 'Uso: bootstrap.sh [--dry-run] [--profile core|alegra|migration|full] [--skip-docker] [--connect] [--reset-managed] [--non-interactive] [--experimental-data-tools]\n'; exit 0 ;;
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

# Version check: capability-based validation
if [[ $DRY_RUN == false ]] && command -v opencode >/dev/null 2>&1; then
  _oc_version=$(opencode --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1 || echo "0.0.0")
  ok "OpenCode v$_oc_version"
  opencode agent list >/dev/null 2>&1 || { critical "opencode agent list falló"; exit 1; }
  ok "Capacidad: opencode agent list verificada"
else
  info "OpenCode version check omitido (dry-run o no instalado aun)"
fi

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

# ── Journal allowlist de paths — validación antes de rollback ──
JOURNAL_ALLOWLIST_PATHS=(
  "$CONFIG_ROOT/opencode/opencode.json"
  "$HARNESS_CONFIG_DIR/state/"
  "$HARNESS_CONFIG_DIR/secrets/"
  "$CONFIG_ROOT/opencode/agents/"
)

_journal_path_is_allowed() {
  local p
  p=$(readlink -f "$1" 2>/dev/null || echo "$1")
  for allowed in "${JOURNAL_ALLOWLIST_PATHS[@]}"; do
    local ap
    ap=$(readlink -f "$allowed" 2>/dev/null || echo "$allowed")
    if [[ "$p" == "$ap" ]] || [[ "$p" == "$ap/"* ]]; then
      return 0
    fi
  done
  return 1
}

# Validar journal — propietario, modo, JSON, schema, paths
_validate_journal() {
  local jf=$1
  # Archivo regular
  [[ -f "$jf" ]] || { critical "Journal no es archivo regular"; return 1; }
  [[ ! -L "$jf" ]] || { critical "Journal es symlink"; return 1; }
  # Propietario
  [[ "$(stat -c '%u' "$jf")" == "$(id -u)" ]] || { critical "Journal: propietario incorrecto"; return 1; }
  # Modo
  [[ "$(stat -c '%a' "$jf")" == "600" ]] || { critical "Journal: modo $perm (requerido 600)"; return 1; }
  # JSON válido
  jq empty "$jf" 2>/dev/null || { critical "Journal: JSON inválido"; return 1; }
  # Schema
  local jv
  jv=$(jq -r '.journalVersion // ""' "$jf" 2>/dev/null || echo "")
  [[ "$jv" == "2" ]] || { critical "Journal: version $jv (requerida 2)"; return 1; }
  # Validar todos los paths de resources
  local i=0 count
  count=$(jq '.resources | length' "$jf" 2>/dev/null || echo 0)
  while [[ $i -lt $count ]]; do
    for ftype in finalPath tempPath backupPath; do
      local fp
      fp=$(jq -r ".resources[$i].$ftype // ''" "$jf" 2>/dev/null || echo "")
      [[ -z "$fp" ]] && continue
      _journal_path_is_allowed "$fp" || {
        critical "Journal: path no permitido en resources[$i].$ftype: $fp"
        return 1
      }
    done
    # IDs únicos
    local id
    id=$(jq -r ".resources[$i].id // ''" "$jf" 2>/dev/null || echo "")
    [[ -n "$id" ]] || { critical "Journal: resources[$i] sin id"; return 1; }
    # applyOrder único
    local order
    order=$(jq -r ".resources[$i].applyOrder // 0" "$jf" 2>/dev/null || echo 0)
    local j
    j=0
    while [[ $j -lt $count ]]; do
      [[ $j -eq $i ]] && { j=$((j + 1)); continue; }
      local o2
      o2=$(jq -r ".resources[$j].applyOrder // 0" "$jf" 2>/dev/null || echo 0)
      [[ "$order" -eq "$o2" ]] && [[ $i -ne $j ]] && {
        critical "Journal: applyOrder duplicado $order en resources[$i] y resources[$j]"
        return 1
      }
      j=$((j + 1))
    done
    i=$((i + 1))
  done
  return 0
}

# Recuperar journal residual al iniciar
_recover_journal() {
  local jf=$1
  warn "Journal residual encontrado: $jf"

  _validate_journal "$jf" || {
    critical "Journal inválido — no se ejecutará recuperación automática"
    critical "Para recuperación manual:"
    critical "  Inspeccionar: $jf"
    critical "  Backups en: $HARNESS_CONFIG_DIR/backups/"
    critical "  Luego eliminar journal: rm -f $jf"
    exit 1
  }

  local phase
  phase=$(jq -r '.phase // "unknown"' "$jf" 2>/dev/null || echo "unknown")

  if [[ "$phase" == "committed" ]]; then
    # Verificar que todos los resources están aplicados correctamente
    local i=0 count
    count=$(jq '.resources | length' "$jf" 2>/dev/null || echo 0)
    local all_ok=true
    while [[ $i -lt $count ]]; do
      local final candid_sha
      final=$(jq -r ".resources[$i].finalPath // ''" "$jf" 2>/dev/null || echo "")
      candid_sha=$(jq -r ".resources[$i].candidateSha256 // ''" "$jf" 2>/dev/null || echo "")
      if [[ -f "$final" && -n "$candid_sha" ]]; then
        local actual_sha
        actual_sha=$(sha256sum "$final" | cut -d' ' -f1)
        if [[ "$actual_sha" != "$candid_sha" ]]; then
          critical "Journal committed pero $final no coincide con candidateSha256"
          all_ok=false
        fi
      fi
      i=$((i + 1))
    done
    if $all_ok; then
      warn "Journal committed verificado — limpiando"
      _clear_journal
      return 0
    else
      critical "Journal committed inconsistente — conservando journal y backups"
      exit 1
    fi
  fi

  # Transacción incompleta
  critical "Recuperando transacción incompleta (fase: $phase)"
  _rollback_resources "$jf" || {
    critical "Rollback falló — journal conservado en $jf"
    critical "Backups disponibles en $HARNESS_CONFIG_DIR/backups/"
    exit 1
  }
  ok "Recuperación completada — transacción anterior revertida"
}

# Rollback de todos los resources (orden inverso de applyOrder)
_rollback_resources() {
  local jf=$1
  local restore_failed=false
  local count
  count=$(jq '.resources | length' "$jf" 2>/dev/null || echo 0)

  # Procesar en orden inverso de applyOrder
  while [[ $count -gt 0 ]]; do
    count=$((count - 1))
    local id final tmp backup existed rtype linktarg status cand_sha orig_sha actual_sha
    eval "$(jq -r ".resources[$count] | @sh \"id=\(.id) final=\(.finalPath) tmp=\(.tempPath) backup=\(.backupPath) existed=\(.existedBefore) rtype=\(.resourceType) linktarg=\(.linkTarget) status=\(.status) cand_sha=\(.candidateSha256) orig_sha=\(.originalSha256)\"" "$jf" 2>/dev/null || true)"

    if [[ "$status" == "prepared" ]]; then
      continue  # nunca se tocó
    fi

    actual_sha=$(sha256sum "$final" 2>/dev/null | cut -d' ' -f1 || echo "")

    if [[ "$rtype" == "symlink" ]]; then
      # Restaurar symlink solo si reemplazamos managed copy por symlink original
      if [[ -f "$final" && ! -L "$final" && "$actual_sha" == "$cand_sha" ]]; then
        rm -f "$final"
        if [[ -n "$linktarg" ]]; then
          ln -s "$linktarg" "$final" 2>/dev/null || {
            critical "Rollback: no se pudo recrear symlink $final -> $linktarg"
            restore_failed=true
          }
        fi
      fi
      continue
    fi

    # Archivos regulares
    if [[ "$existed" == "true" ]]; then
      if [[ -f "$backup" ]]; then
        local temp_rb="${final}.rollback.$$"
        cp "$backup" "$temp_rb" || { critical "Rollback: cp falló para $final"; restore_failed=true; continue; }
        chmod 600 "$temp_rb"
        local temp_sha
        temp_sha=$(sha256sum "$temp_rb" | cut -d' ' -f1)
        local backup_sha
        backup_sha=$(sha256sum "$backup" | cut -d' ' -f1)
        if [[ "$temp_sha" != "$backup_sha" ]]; then
          rm -f "$temp_rb"
          critical "Rollback: checksum mismatch al restaurar $final"
          restore_failed=true
          continue
        fi
        mv "$temp_rb" "$final" || { critical "Rollback: mv falló para $final"; restore_failed=true; continue; }
        chmod 600 "$final"
      else
        critical "Rollback: backup no existe para $final"
        restore_failed=true
      fi
    elif [[ "$existed" == "false" ]]; then
      # Solo eliminar si el hash actual coincide con candidateSha256 (no fue modificado externamente)
      if [[ "$actual_sha" == "$cand_sha" ]]; then
        rm -f "$final" || { critical "Rollback: no se pudo eliminar $final"; restore_failed=true; }
      else
        critical "Rollback: $final no existía antes y fue modificado externamente — conservando"
        restore_failed=true
      fi
    fi

    # Limpiar temp si existe
    [[ -f "$tmp" ]] && rm -f "$tmp"
  done

  $restore_failed && return 1
  return 0
}

# ── Detectar journal residual y recuperar ───────────────────────
if [[ -f "$JOURNAL_FILE" ]]; then
  _recover_journal "$JOURNAL_FILE" || exit 1
fi

# Trap para transacción actual
trap _rollback EXIT
trap '_rollback; exit 1' INT TERM

_rollback() {
  local rc=$?
  trap '' EXIT INT TERM
  if [[ -f "$JOURNAL_FILE" ]]; then
    _validate_journal "$JOURNAL_FILE" 2>/dev/null || {
      critical "Rollback: journal inválido — conservando para revisión"
      exit $rc
    }
    local phase
    phase=$(jq -r '.phase // "unknown"' "$JOURNAL_FILE" 2>/dev/null || echo "unknown")
    critical "Rollback transacción incompleta (fase: $phase)"
    _rollback_resources "$JOURNAL_FILE" && _clear_journal || {
      critical "Rollback: journal conservado para reintento manual"
    }
  fi
  rm -f "$TMP_CANDIDATE" "$TMP_STATE"
  # Limpiar temporales de secretos y managed files
  for tf in "$TMP_GITHUB" "$TMP_NAVI_URL" "$TMP_NAVI_CID"; do
    [[ -n "$tf" && -f "$tf" ]] && rm -f "$tf"
  done
  exit $rc
}

_check_failpoint() {
  local point=$1
  if [[ "${DH_TEST_MODE:-0}" == "1" && "$DH_FAIL_AT" == "$point" ]]; then
    critical "Failpoint alcanzado: $point"
    exit 1
  fi
}

# ── Journal array helpers ────────────────────────────────────────
# Journal es un JSON con {journalVersion, phase, resources:[{id,applyOrder,...status}]}

_fsync() {
  python3 -c "import os,sys; fd=os.open(sys.argv[1],os.O_RDONLY); os.fsync(fd); os.close(fd)" "$1"
}

_fsync_file() {
  python3 -c "import os,sys; fd=os.open(sys.argv[1],os.O_RDONLY); os.fsync(fd); os.close(fd)" "$1"
}

# mv seguro: renameat2 vía Python
# dst no existe → RENAME_NOREPLACE (falla si concurrente crea dst)
# dst existe → verificamos hash, luego rename atómico
_mv_safe() {
  local src=$1 dst=$2 orig_sha=${3:-}
  python3 -c "
import ctypes, os, sys, ctypes.util
SYS = {'x86_64': 316, 'aarch64': 276}.get(os.uname().machine, 316)
flags = int(sys.argv[3])
libc = ctypes.CDLL(ctypes.util.find_library('c'), use_errno=True)
src, dst = sys.argv[1].encode(), sys.argv[2].encode()
libc.syscall.restype = ctypes.c_long
ret = libc.syscall(SYS, -100, src, -100, dst, flags)
if ret != 0:
    sys.exit(ctypes.get_errno())
" "$src" "$dst" "1"
  local rn=$?
  if [[ $rn -eq 0 ]]; then
    chmod 600 "$dst"
    return 0
  fi
  if [[ $rn -eq 17 ]]; then
    if [[ -n "$orig_sha" ]]; then
      local current
      current=$(sha256sum "$dst" 2>/dev/null | cut -d' ' -f1 || echo "")
      if [[ "$current" == "$orig_sha" ]]; then
        python3 -c "
import ctypes, os, sys, ctypes.util
SYS = {'x86_64': 316, 'aarch64': 276}.get(os.uname().machine, 316)
libc = ctypes.CDLL(ctypes.util.find_library('c'), use_errno=True)
src, dst = sys.argv[1].encode(), sys.argv[2].encode()
libc.syscall.restype = ctypes.c_long
ret = libc.syscall(SYS, -100, src, -100, dst, 0)
if ret != 0:
    sys.exit(1)
" "$src" "$dst" && { chmod 600 "$dst"; rm -f "$src"; return 0; } || { rm -f "$src"; return 1; }
      fi
    fi
    rm -f "$src"
    return 2
  fi
  rm -f "$src"
  return 1
}

# Inicializar journal como array vacío (atómico: temp → fsync → rename)
_init_journal() {
  local tmp="${JOURNAL_FILE}.$$.tmp"
  jq -n '{journalVersion: "2", phase: "preparing", resources: []}' > "$tmp"
  chmod 600 "$tmp"
  _fsync "$tmp"
  mv "$tmp" "$JOURNAL_FILE"
  chmod 600 "$JOURNAL_FILE"
  _fsync "$JOURNAL_FILE"
}

# Agregar resource al journal (atómico)
_journal_add_resource() {
  local id=$1 final=$2 tmp=$3 backup=$4 existed=$5 mode=$6 order=$7 rtype=${8:-file} linktarg=${9:-} orig_sha=${10:-}
  local t="${JOURNAL_FILE}.$$.tmp"
  jq --arg id "$id" \
    --arg final "$final" \
    --arg tmp "$tmp" \
    --arg backup "$backup" \
    --argjson existed "$existed" \
    --arg mode "$mode" \
    --argjson order "$order" \
    --arg rtype "$rtype" \
    --arg linktarg "$linktarg" \
    --arg orig "$orig_sha" \
    '.resources += [{
      id: $id, finalPath: $final, tempPath: $tmp, backupPath: $backup,
      existedBefore: $existed, expectedMode: $mode, applyOrder: $order,
      resourceType: $rtype, linkTarget: $linktarg,
      originalSha256: $orig, candidateSha256: "", status: "prepared"
    }]' "$JOURNAL_FILE" > "$t" && mv "$t" "$JOURNAL_FILE"
  chmod 600 "$JOURNAL_FILE"
  _fsync "$JOURNAL_FILE"
}

# Actualizar fase y/o un resource en el journal (atómico)
_journal_update() {
  local phase=${1:-} resource_id=${2:-} updates=${3:-}
  local t="${JOURNAL_FILE}.$$.tmp"
  if [[ -n "$phase" ]]; then
    jq --arg p "$phase" '.phase = $p' "$JOURNAL_FILE" > "$t"
    if [[ -s "$t" ]]; then
      mv "$t" "$JOURNAL_FILE"
    fi
  fi
  if [[ -n "$resource_id" && -n "$updates" ]]; then
    if echo "$updates" | jq empty >/dev/null 2>&1; then
      jq --arg id "$resource_id" --argjson upd "$updates" \
        '.resources = [.resources[] | if .id == $id then . + $upd else . end]' \
        "$JOURNAL_FILE" > "$t" && mv "$t" "$JOURNAL_FILE"
    fi
  fi
  chmod 600 "$JOURNAL_FILE"
  _fsync "$JOURNAL_FILE"
}

# Actualizar journal completo (atómico: temp → fsync → rename)
_journal_write_full() {
  local content=$1
  printf '%s\n' "$content" > "${JOURNAL_FILE}.tmp"
  chmod 600 "${JOURNAL_FILE}.tmp"
  _fsync "${JOURNAL_FILE}.tmp"
  mv "${JOURNAL_FILE}.tmp" "$JOURNAL_FILE"
  chmod 600 "$JOURNAL_FILE"
  _fsync "$JOURNAL_FILE"
}

_clear_journal() {
  rm -f "$JOURNAL_FILE" || { critical "No se pudo eliminar journal"; return 1; }
  _fsync "$(dirname "$JOURNAL_FILE")" 2>/dev/null || true
}

# Registrar si los archivos existían antes de la transacción
OC_EXISTED_BEFORE=false
[[ -f "$OC_FILE" ]] && OC_EXISTED_BEFORE=true
STATE_EXISTED_BEFORE=false
[[ -f "$STATE_FILE" ]] && STATE_EXISTED_BEFORE=true

# Temporales de secretos
TMP_GITHUB=""
TMP_NAVI_URL=""
TMP_NAVI_CID=""

# Inicializar journal
_init_journal

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
# Fase 7: Configuración del harness (links y configs, NO agentes)
# ---------------------------------------------------------------------------
phase "Configuración del harness"

if [[ -f "$ROOT_DIR/scripts/install.sh" ]]; then
  INSTALL_ARGS=(--skip-resources --skip-agents)
  $RESET_MANAGED && INSTALL_ARGS+=(--reset-managed)
  $NON_INTERACTIVE && INSTALL_ARGS+=(--non-interactive)
  $EXPERIMENTAL_DATA_TOOLS && INSTALL_ARGS+=(--experimental-data-tools)
  info 'Ejecutando install.sh (configs y agentes — fase de deploy)...'
  run bash "$ROOT_DIR/scripts/install.sh" "${INSTALL_ARGS[@]}"
else
  info 'install.sh no encontrado'
fi
_ensure_tool_visible "dh" "$LOCAL_BIN/dh" || exit 1

if command -v gentle-ai >/dev/null 2>&1; then
  info 'Verificando Gentle AI...'
  if [[ $DRY_RUN == false ]]; then
    ga_version=$(gentle-ai --version 2>/dev/null || echo "unknown")
    ok "Gentle AI $ga_version"

    if gentle-ai skill-registry refresh --force >/dev/null 2>&1; then
      ok "Gentle AI skill-registry actualizado"
    else
      warn "gentle-ai skill-registry refresh falló — ejecuta manual: gentle-ai skill-registry refresh --force"
    fi

    if gentle-ai sync >/dev/null 2>&1; then
      ok "Gentle AI sincronizado"
    else
      critical "gentle-ai sync falló — revisa que GAIA_KEY esté configurada"
      exit 1
    fi

    if gentle-ai doctor 2>/dev/null | grep -q "healthy"; then
      ok "Gentle AI saludable"
    else
      warn "gentle-ai doctor no reporta healthy"
    fi
  else
    info "[simulado] gentle-ai, sync, doctor"
  fi
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

# ── Secret migration: GitHub, Navi ──────────────────────────────
# Temp files in same directory as target, coordinated via journal
SECRETS_MIGRATED=0
SECRETS_PENDING=0

# Escribir contenido a temp en el mismo directorio que el destino
_secret_prepare_temp() {
  local path=$1 content=$2
  local dir
  dir=$(dirname "$path")
  mkdir -p "$dir" || return 1
  chmod 700 "$dir" || return 1
  local tmp
  tmp=$(mktemp "$dir/.$(basename "$path").tmp.XXXXXXXX") || return 1
  printf '%s\n' "$content" > "$tmp" || { rm -f "$tmp"; return 1; }
  chmod 600 "$tmp" || { rm -f "$tmp"; return 1; }
  local sha
  sha=$(sha256sum "$tmp" | cut -d' ' -f1)
  printf '%s\t%s\n' "$tmp" "$sha"
}

# Validar ruta de secreto contra rutas administradas
_validar_ruta_secreta() {
  local path=$1
  local can
  can=$(readlink -f "$path" 2>/dev/null || echo "")
  [[ "$can" == "$HARNESS_CONFIG_DIR/secrets/"* ]] || return 1
  # Validar padres
  local dir="$can"
  while [[ "$dir" != "$HARNESS_CONFIG_DIR" ]]; do
    dir=$(dirname "$dir")
    if [[ -e "$dir" ]]; then
      [[ ! -L "$dir" ]] || return 1
      [[ "$(stat -c '%u' "$dir")" == "$(id -u)" ]] || return 1
      [[ "$(stat -c '%a' "$dir")" == "700" ]] || return 1
    fi
  done
  return 0
}

# Mapping único de resource ID → applyOrder
_apply_order_for_id() {
  case "$1" in
    githubAuthorization) echo 10 ;;
    naviUrl)            echo 20 ;;
    naviClientId)       echo 30 ;;
    opencodeConfig)     echo 40 ;;
    mcpState)           echo 50 ;;
    managedFilesState)  echo 60 ;;
    *)                  echo 99 ;;
  esac
}

# Registrar secreto en journal (prepara temp, añade recurso)
_journal_secret_resource() {
  local id=$1 final=$2 content=$3
  _validar_ruta_secreta "$final" || {
    critical "Ruta de secreto no válida: $final"
    return 1
  }
  local result
  result=$(_secret_prepare_temp "$final" "$content") || return 1
  local tmp sha
  tmp=$(printf '%s' "$result" | cut -f1)
  sha=$(printf '%s' "$result" | cut -f2)
  local existed=false
  [[ -f "$final" ]] && existed=true
  # Crear backup si existe
  local backup=""
  if [[ -f "$final" ]]; then
    local bdir="$HARNESS_CONFIG_DIR/backups"
    mkdir -p "$bdir" && chmod 700 "$bdir"
    backup="$bdir/${id}-$(date +%s).bak"
    cp "$final" "$backup" && chmod 600 "$backup" || {
      rm -f "$tmp"
      critical "No se pudo crear backup de $final"
      return 1
    }
  fi
  # Guardar según el id
  case "$id" in
    githubAuthorization) TMP_GITHUB="$tmp" ;;
    naviUrl) TMP_NAVI_URL="$tmp" ;;
    naviClientId) TMP_NAVI_CID="$tmp" ;;
  esac
  _journal_add_resource "$id" "$final" "$tmp" "$backup" "$existed" "600" "$(_apply_order_for_id "$id")"
  return 0
}

_migrate_github_secret() {
  local auth
  auth=$(jq -r '.mcp.github.headers.Authorization // ""' "$TMP_CANDIDATE" 2>/dev/null || echo "")
  [[ -z "$auth" || "$auth" == "null" ]] && return 0

  local secret_dir="$HARNESS_CONFIG_DIR/secrets/github"
  local secret_file="$secret_dir/authorization"

  # Already file-based — validate path and return
  if [[ "$auth" == "{file:$secret_file}" ]]; then
    if [[ -f "$secret_file" ]]; then
      local perm
      perm=$(stat -c '%a' "$secret_file" 2>/dev/null || echo "000")
      if [[ "$perm" != "600" ]]; then
        chmod 600 "$secret_file" || { critical "GitHub: no se pudo fijar permiso 600"; return 1; }
      fi
    fi
    return 0
  fi

  # Resolve value from current auth form
  local value=""
  if [[ "$auth" == "Bearer {env:GITHUB_PERSONAL_ACCESS_TOKEN}" && -n "${GITHUB_PERSONAL_ACCESS_TOKEN:-}" ]]; then
    value="Bearer $GITHUB_PERSONAL_ACCESS_TOKEN"
  elif [[ "$auth" == "{env:GITHUB_PERSONAL_ACCESS_TOKEN}" && -n "${GITHUB_PERSONAL_ACCESS_TOKEN:-}" ]]; then
    value="Bearer $GITHUB_PERSONAL_ACCESS_TOKEN"
  elif [[ "$auth" =~ ^Bearer\  && "$auth" != "Bearer {env:"* ]]; then
    value="$auth"
  fi

  if [[ -z "$value" ]]; then
    if [[ $CONNECT == true && $NON_INTERACTIVE == false && -t 0 ]]; then
      info "GitHub PAT requerido (input oculto):"
      read -r -s _gh_token
      if [[ -n "$_gh_token" ]]; then
        value="Bearer $_gh_token"
        unset _gh_token
      fi
    fi
  fi

  if [[ -n "$value" ]]; then
    if _journal_secret_resource "githubAuthorization" "$secret_file" "$value"; then
      _candidate_jq --arg f "$secret_file" '.mcp.github.headers.Authorization = "{file:\($f)}"'
      info "GitHub: token preparado para migración"
      SECRETS_MIGRATED=$((SECRETS_MIGRATED + 1))
    else
      critical "GitHub: fallo al preparar secreto"
      return 1
    fi
  else
    if [[ -n "${GITHUB_PERSONAL_ACCESS_TOKEN:-}" ]]; then
      ok "GitHub: usando {env:GITHUB_PERSONAL_ACCESS_TOKEN}"
    else
      info "GitHub: token no disponible, MCP requerirá config manual"
      SECRETS_PENDING=$((SECRETS_PENDING + 1))
    fi
  fi
}

_migrate_navi_secret() {
  local navi_dir="$HARNESS_CONFIG_DIR/secrets/navi"
  local url_file="$navi_dir/url"
  local cid_file="$navi_dir/client-id"
  local url_ok=false
  local cid_ok=false

  _resolve_and_prepare() {
    local candidate_key=$1 file_path=$2 env_var=$3 resource_id=$4
    local current
    current=$(jq -r "$candidate_key" "$TMP_CANDIDATE" 2>/dev/null || echo "")
    [[ -z "$current" || "$current" == "null" ]] && return 0

    if [[ "$current" =~ ^\{file: ]]; then
      _validar_ruta_secreta "$file_path" || return 1
      [[ -f "$file_path" ]] && return 0
      return 0  # archivo se creará durante apply
    fi

    local resolved=""
    if [[ "$current" == "{env:$env_var}" && -n "${!env_var:-}" ]]; then
      resolved="${!env_var}"
    elif [[ "$current" != "{"* ]]; then
      resolved="$current"
    fi

    if [[ -n "$resolved" ]]; then
      _journal_secret_resource "$resource_id" "$file_path" "$resolved" || return 1
      local file_ref="{file:$file_path}"
      _candidate_jq --arg f "$file_ref" "$candidate_key = \$f"
      return 0
    fi
    return 2  # no hay valor disponible
  }

  _resolve_and_prepare '.mcp.navi.url' "$url_file" "NAVI_MCP_URL" "naviUrl" && url_ok=true
  _resolve_and_prepare '.mcp.navi.oauth.clientId' "$cid_file" "NAVI_OAUTH_CLIENT_ID" "naviClientId" && cid_ok=true

  if $url_ok && $cid_ok; then
    info "Navi: secretos preparados para migración"
    SECRETS_MIGRATED=$((SECRETS_MIGRATED + 1))
  elif [[ "$url_ok" != "$cid_ok" ]]; then
    info "Navi: migración parcial detectada — se completará en transacción o rollback"
    SECRETS_PENDING=$((SECRETS_PENDING + 1))
  else
    info "Navi: secretos no disponibles, MCP requerirá config manual"
  fi
}

# ── Pre-apply summary ──────────────────────────────────────────────
if [[ $RESET_MANAGED == true && $DRY_RUN == false ]]; then
  printf '\n==> Resumen de cambios:\n'
  printf '  Recursos agregados: %d MCP(s)\n' "$MCP_ADDED"
  printf '  Recursos actualizados: %d MCP(s)\n' "$MCP_UPDATED"
  printf '  Recursos preservados: %d MCP(s)\n' "$MCP_SKIPPED"
  printf '  Secretos migrados: %d\n' "$SECRETS_MIGRATED"
  printf '  OAuth pendiente: %d\n' "$SECRETS_PENDING"
fi

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

# ── Allowlist canónico ──────────────────────────────────────────
_enforce_allowlist() {
  local original=$1 candidate=$2
  local tmp_o tmp_c
  tmp_o=$(mktemp) && tmp_c=$(mktemp)
  trap 'rm -f "$tmp_o" "$tmp_c"' RETURN

  if [[ ! -f "$original" || ! -s "$original" ]]; then
    local pkg
    pkg=$(jq -r '.plugin[] // "" | select(startswith("@dietrichgebert/ponytail@4.8.4"))' "$candidate" 2>/dev/null || echo "")
    [[ -n "$pkg" ]] || { critical "ALLOWLIST: Ponytail @4.8.4 no encontrado en candidato"; return 1; }
    return 0
  fi

  # Verificar modificación concurrente
  if [[ -f "$original" ]]; then
    local orig_sha
    orig_sha=$(sha256sum "$original" | cut -d' ' -f1)
    local j_orig
    j_orig=$(jq -r '.resources[] | select(.id == "opencodeConfig") | .originalSha256 // ""' "$JOURNAL_FILE" 2>/dev/null || echo "")
    if [[ -n "$j_orig" && "$orig_sha" != "$j_orig" ]]; then
      critical "ALLOWLIST: opencode.json cambió durante la instalación"
      return 1
    fi
  fi

  local o_size
  o_size=$(jq '. | length' "$original" 2>/dev/null || echo 0)
  [[ "$o_size" -gt 0 ]] || return 0

  # Copias de trabajo
  cp "$original" "$tmp_o" 2>/dev/null || printf '{}' > "$tmp_o"
  cp "$candidate" "$tmp_c" 2>/dev/null || printf '{}' > "$tmp_c"

  # Ignorar $schema (siempre añadido por el harness)
  jq 'del(.["$schema"])' "$tmp_o" > "${tmp_o}.$$" && mv "${tmp_o}.$$" "$tmp_o"
  jq 'del(.["$schema"])' "$tmp_c" > "${tmp_c}.$$" && mv "${tmp_c}.$$" "$tmp_c"

  # Retirar MCPs administrados de AMBAS
  for mcp in codegraph engram context7 github linear wiki-alegra navi sentry; do
    jq "del(.mcp.$mcp)" "$tmp_o" > "${tmp_o}.$$" && mv "${tmp_o}.$$" "$tmp_o" 2>/dev/null || true
    jq "del(.mcp.$mcp)" "$tmp_c" > "${tmp_c}.$$" && mv "${tmp_c}.$$" "$tmp_c" 2>/dev/null || true
  done

  # Retirar solo entradas Ponytail de .plugin (preservar plugins externos)
  jq '.plugin = ((.plugin // []) | map(select(startswith("@dietrichgebert/ponytail") | not)))' "$tmp_o" > "${tmp_o}.$$" && mv "${tmp_o}.$$" "$tmp_o"
  jq '.plugin = ((.plugin // []) | map(select(startswith("@dietrichgebert/ponytail") | not)))' "$tmp_c" > "${tmp_c}.$$" && mv "${tmp_c}.$$" "$tmp_c"

  # Comparación canónica
  local hash_o hash_c
  hash_o=$(jq -S -c . "$tmp_o" | sha256sum | cut -d' ' -f1 || echo "no")
  hash_c=$(jq -S -c . "$tmp_c" | sha256sum | cut -d' ' -f1 || echo "no")

  if [[ "$hash_o" != "$hash_c" ]]; then
    critical "ALLOWLIST: cambios detectados fuera de los recursos administrados"
    diff <(jq -S -c 'keys | sort[]' "$tmp_o" 2>/dev/null) \
         <(jq -S -c 'keys | sort[]' "$tmp_c" 2>/dev/null) \
         | head -20 || true
    return 1
  fi

  # Verificar que Ponytail administrada esté presente
  local ponytail
  ponytail=$(jq -r '.plugin[] // "" | select(startswith("@dietrichgebert/ponytail@4.8.4"))' "$candidate" 2>/dev/null || echo "")
  [[ -n "$ponytail" ]] || {
    critical "ALLOWLIST: Ponytail @4.8.4 no encontrado en .plugin"
    return 1
  }

  return 0
}

# Run secret migration before final validation (only when not dry-run)
if [[ $DRY_RUN == false ]]; then
  _migrate_github_secret
  if profile_includes "$PROFILE" "mcps" "navi"; then
    _migrate_navi_secret
  fi
fi

_transaction_apply() {
  local cfg_dir oc_schema cfg_orig_sha st_orig_sha config_backup state_backup
  oc_schema="${DH_OC_SCHEMA:-$ROOT_DIR/tests/fixtures/opencode-config.schema.json}"
  cfg_dir=$(dirname "$STATE_FILE")
  mkdir -p "$cfg_dir"
  TMP_STATE=$(mktemp "$cfg_dir/.opencode-managed.json.XXXXXXXX")
  cfg_orig_sha="" ; st_orig_sha=""
  [[ -f "$OC_FILE" ]] && cfg_orig_sha=$(sha256sum "$OC_FILE" | cut -d' ' -f1)
  [[ -f "$STATE_FILE" ]] && st_orig_sha=$(sha256sum "$STATE_FILE" | cut -d' ' -f1)

  _check_failpoint "pre-validate"
  _journal_update "backups-verified"

  local original_hash candidate_hash config_changed=false
  original_hash=$(jq -S -c . "$OC_FILE" 2>/dev/null | sha256sum | cut -d' ' -f1 || echo "no-file")
  candidate_hash=$(jq -S -c . "$TMP_CANDIDATE" 2>/dev/null | sha256sum | cut -d' ' -f1 || echo "no-candidate")
  [[ "$original_hash" != "$candidate_hash" ]] && config_changed=true

  if ! $config_changed; then
    if (( ${#MANAGED_MCPS[@]} > 0 )) && _build_state "$OC_FILE" "$TMP_STATE"; then
      _journal_add_resource "mcpState" "$STATE_FILE" "$TMP_STATE" "" "$STATE_EXISTED_BEFORE" "600" 50
      _journal_update "candidates-ready"
      _journal_update "" "mcpState" '{"status": "applying"}'
      local cs
      cs=$(sha256sum "$TMP_STATE" | cut -d' ' -f1)
      _journal_update "" "mcpState" '{"candidateSha256": "'"$cs"'"}'
      _mv_safe "$TMP_STATE" "$STATE_FILE" ""
      _fsync "$(dirname "$STATE_FILE")"
      _journal_update "" "mcpState" '{"status": "applied"}'
      _journal_update "committed"
      _clear_journal
    fi
    local summary=""
    [[ $MCP_SKIPPED -gt 0 ]] && summary="${MCP_SKIPPED} personalizados omitidos"
    rm -f "$TMP_CANDIDATE"
    [[ -n "$summary" ]] && ok "MCPs: ${summary}" || ok "No hay cambios en la configuracion"
    return 0
  fi

  # ── Registrar resources en journal (secretos ya registrados por _journal_secret_resource) ──
  config_backup=""
  if $OC_EXISTED_BEFORE && [[ -f "$OC_FILE" ]]; then
    config_backup="$HARNESS_CONFIG_DIR/backups/opencode-config-pre-$(date +%s).bak"
    mkdir -p "$HARNESS_CONFIG_DIR/backups" && chmod 700 "$HARNESS_CONFIG_DIR/backups"
    cp "$OC_FILE" "$config_backup" && chmod 600 "$config_backup" || { critical "No se pudo crear backup de configuración"; return 1; }
  fi
  _journal_add_resource "opencodeConfig" "$OC_FILE" "$TMP_CANDIDATE" "$config_backup" "$OC_EXISTED_BEFORE" "600" 40 file "" "$cfg_orig_sha"

  state_backup=""
  if $STATE_EXISTED_BEFORE && [[ -f "$STATE_FILE" ]] && (( ${#MANAGED_MCPS[@]} > 0 )); then
    state_backup="$HARNESS_CONFIG_DIR/backups/opencode-mcpstate-pre-$(date +%s).bak"
    mkdir -p "$HARNESS_CONFIG_DIR/backups" && chmod 700 "$HARNESS_CONFIG_DIR/backups"
    cp "$STATE_FILE" "$state_backup" && chmod 600 "$state_backup" || { critical "No se pudo crear backup de estado"; return 1; }
  fi
  _journal_add_resource "mcpState" "$STATE_FILE" "$TMP_STATE" "$state_backup" "$STATE_EXISTED_BEFORE" "600" 50 file "" "$st_orig_sha"
  _check_failpoint "backup-config"
  _check_failpoint "backup-state"

  # ── Validar candidato ──────────────────────────────────────
  if [[ "${DH_TEST_MODE:-0}" == "1" && "$DH_FAIL_AT" == "invalid-candidate" ]]; then
    echo '}}}}INVALID' >> "$TMP_CANDIDATE"
  fi
  if ! jq empty "$TMP_CANDIDATE" >/dev/null 2>&1; then
    critical "Candidato JSON invalido"
    return 1
  fi
  python3 "$ROOT_DIR/scripts/validate-opencode-config.py" \
    --config "$TMP_CANDIDATE" --schema "$oc_schema" >/dev/null 2>&1 || {
    critical "Candidato no pasa schema"
    return 1
  }
  if ! _enforce_allowlist "$OC_FILE" "$TMP_CANDIDATE"; then
    if $OC_EXISTED_BEFORE; then
      critical "Allowlist: cambios no administrados"
      return 1
    fi
    warn "Allowlist omitida (primer arranque)"
  fi
  _check_failpoint "allowlist-check"

  if (( ${#MANAGED_MCPS[@]} > 0 )) && ! _build_state "$TMP_CANDIDATE" "$TMP_STATE"; then
    critical "No se pudo construir state"
    return 1
  fi
  _journal_update "candidates-ready"

  # ── Verificar cambios concurrentes ─────────────────────────
  local i=0 count
  count=$(jq '.resources | length' "$JOURNAL_FILE" 2>/dev/null || echo 0)
  while [[ $i -lt $count ]]; do
    local final orig_sha existed
    eval "$(jq -r ".resources[$i] | @sh \"final=\(.finalPath) orig_sha=\(.originalSha256) existed=\(.existedBefore)\"" "$JOURNAL_FILE" 2>/dev/null || true)"
    if [[ "$existed" == "true" && -f "$final" && -n "$orig_sha" ]]; then
      local actual
      actual=$(sha256sum "$final" | cut -d' ' -f1)
      if [[ "$actual" != "$orig_sha" ]]; then
        local id
        id=$(jq -r ".resources[$i].id // 'unknown'" "$JOURNAL_FILE" 2>/dev/null)
        critical "CONFLICTO: $id cambió durante la instalación"
        return 2
      fi
    fi
    i=$((i + 1))
  done
  _journal_update "allowlist-passed"

  # ── Aplicar recursos en orden ─────────────────────────────
  _journal_update "applying"
  i=0
  while [[ $i -lt $count ]]; do
    local id final tmp existed orig_sha
    eval "$(jq -r ".resources[$i] | @sh \"id=\(.id) final=\(.finalPath) tmp=\(.tempPath) existed=\(.existedBefore) orig_sha=\(.originalSha256)\"" "$JOURNAL_FILE" 2>/dev/null || true)"
    [[ -n "$tmp" && -f "$tmp" ]] || { i=$((i + 1)); continue; }
    [[ -z "$final" ]] && { i=$((i + 1)); continue; }

    _journal_update "" "$id" '{"status": "applying"}'
    local cand_sha
    cand_sha=$(sha256sum "$tmp" | cut -d' ' -f1)
    _journal_update "" "$id" '{"candidateSha256": "'"$cand_sha"'"}'
    _check_failpoint "mv-${id}"

    _mv_safe "$tmp" "$final" "$orig_sha"
    local mvs_rc=$?
    if [[ $mvs_rc -eq 2 ]]; then
      critical "CONFLICTO: $id cambió externamente durante la aplicación"
      return 2
    elif [[ $mvs_rc -ne 0 ]]; then
      critical "ERROR: no se pudo aplicar $id"
      return 1
    fi
    _fsync "$(dirname "$final")"
    _journal_update "" "$id" '{"status": "applied"}'
    i=$((i + 1))
  done

  _journal_update "committed"
  _clear_journal
  info "Configuracion aplicada (plugins y/o MCPs actualizados)"
  if $OC_EXISTED_BEFORE; then
    info "Backup: $config_backup"
  fi
  return 0
}

# ── Ejecutar transacción (dry-run salta) ──────────────────────
rc=0
if [[ $DRY_RUN == false ]]; then
  set +e
  _transaction_apply; rc=$?
  set -e
  if [[ $rc -eq 1 ]]; then
    rm -f "$TMP_CANDIDATE" "$TMP_STATE"
    printf '  [dbg] exit on rc=1\n'
    exit 1
  elif [[ $rc -eq 2 ]]; then
    rm -f "$TMP_CANDIDATE" "$TMP_STATE"
    printf '  [dbg] exit on rc=2\n'
    exit 1
  fi
  printf '  [dbg] transaction rc=%d (ok)\n' "$rc"
fi
printf '  [dbg] post transaction block reached\n'

# ── Fase post-transacción: agentes administrados ─────────────
if [[ $DRY_RUN == false ]] && [[ -f "$ROOT_DIR/scripts/install.sh" ]]; then
  echo "  [dbg] entering agent post-phase" >&2
  phase "Agentes administrados"
  info 'Instalando agentes administrados...'
  INSTALL_ARGS=()
  $RESET_MANAGED && INSTALL_ARGS+=(--reset-managed)
  $NON_INTERACTIVE && INSTALL_ARGS+=(--non-interactive)
  $EXPERIMENTAL_DATA_TOOLS && INSTALL_ARGS+=(--experimental-data-tools)
  if ! run bash "$ROOT_DIR/scripts/install.sh" "${INSTALL_ARGS[@]}"; then
    critical "Fallo al instalar agentes administrados"
    exit 1
  fi
  _ensure_tool_visible "dh" "$LOCAL_BIN/dh" || exit 1
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

if [[ "$(jq -r '.mcp.github.headers.Authorization // ""' "$OC_FILE" 2>/dev/null)" == "{env:GITHUB_PERSONAL_ACCESS_TOKEN}" ]]; then
  printf '     Configura GITHUB_PERSONAL_ACCESS_TOKEN o ejecuta: dh opencode install --connect\n'
elif ! grep -q 'file:' "$OC_FILE" 2>/dev/null; then
  printf '     GitHub: token no persistido. Usa: dh opencode install --connect\n'
fi
if [[ -d "$HARNESS_CONFIG_DIR/secrets/github" ]]; then
  printf '     GitHub: token persistido en archivo seguro\n'
fi

printf '\n  2. Crea un backup de la configuracion:\n'
printf '     dh opencode backup\n'
printf '\n  3. Verifica estado con doctor.sh\n'
printf '     bash scripts/doctor.sh\n'
printf '\n  4. Si es primera instalación, reinicia OpenCode\n'
printf '\n'
