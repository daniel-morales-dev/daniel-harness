#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MANIFEST="$ROOT_DIR/bootstrap/manifest.yaml"
DRY_RUN=false
SKIP_DOCKER=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --skip-docker) SKIP_DOCKER=true; shift ;;
    --help|-h) printf 'Uso: bootstrap.sh [--dry-run] [--skip-docker]\n'; exit 0 ;;
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

if [[ $DRY_RUN == false ]]; then
  if ! sudo -n true 2>/dev/null; then
    printf 'Se necesita acceso sudo.\n'
    sudo -v || exit 1
  fi
fi

# Parseadores del manifest (sin dependencia de yq)
parse_section() {
  local section=$1
  awk -v sec="$section" '
    $0 ~ "^" sec ":" { in_section=1; next }
    in_section && /^[a-z]/ && !/^  / { in_section=0 }
    in_section
  ' "$MANIFEST"
}

parse_nested_list() {
  local parent=$1 child=$2
  awk -v parent="$parent" -v child="$child" '
    $0 ~ "^" parent ":" { in_parent=1; next }
    in_parent && $0 ~ "^  " child ":" { in_child=1; next }
    in_child && /^    - / { gsub(/^    - /,""); print; next }
    in_child && !/^      / && !/^    - / { in_child=0 }
    in_parent && !/^  / && !/^$/ { in_parent=0 }
  ' "$MANIFEST"
}

parse_value() {
  local section=$1
  local key=$2
  awk -v sec="$section" -v k="$key" '
    $0 ~ "^" sec ":" { in_section=1; next }
    in_section && $0 ~ "^  " k ":" {
      sub(/^  [a-z_]+:[[:space:]]*/,"")
      sub(/^["\x27]/,""); sub(/["\x27]$/,"")
      print
      exit
    }
    in_section && !/^  / { in_section=0 }
  ' "$MANIFEST"
}

parse_mcp_names() {
  awk '/^mcp_servers:/{found=1; next} found && /^  [a-z][a-z0-9_-]*:$/ {
    gsub(/^[[:space:]]+/,""); gsub(/:$/,""); print; next
  } found && !/^    / && !/^  $/{found=0}' "$MANIFEST"
}

parse_mcp_field() {
  local name=$1 field=$2
  awk -v n="$name" -v f="$field" '
    /^mcp_servers:/{in_mcp=1; next}
    in_mcp {
      if ($0 ~ "^  " n ":" && !found) { found=1; next }
      if (found && $0 ~ "^    " f ":") {
        sub(/^[[:space:]]*[a-z_]+:[[:space:]]*/, "")
        gsub(/^["\x27]/, ""); gsub(/["\x27]$/, "")
        print; exit
      }
      if (found && $0 ~ /^  [a-z]/) { found=0 }
    }
  ' "$MANIFEST"
}

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
  dpkg -s "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
done

if (( ${#missing[@]} > 0 )); then
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

install_tool() {
  local name=$1
  local check_cmd=$2
  local install_cmd=$3

  if eval "$check_cmd" >/dev/null 2>&1; then
    ok "$name ya instalado"
  else
    info "Instalando $name..."
    run bash -c "$install_cmd"
  fi
}

install_tool "OpenCode"  "command -v opencode"  "curl -fsSL https://opencode.ai/install.sh | sh"
install_tool "Gentle AI" "command -v gentle-ai" "curl -fsSL https://gentle-ai.dev/install.sh | sh"
install_tool "Engram"    "command -v engram"    "curl -fsSL https://engram.sh/install.sh | sh"

if [[ -s "$NVM_DIR/nvm.sh" ]]; then
  . "$NVM_DIR/nvm.sh"
elif [[ $DRY_RUN == true ]]; then
  info "[simulado] NVM estaría disponible después de la instalación. CodeGraph puede fallar sin Node."
fi
install_tool "CodeGraph" "command -v codegraph" "npm install -g @codegraph/cli"
install_tool "RTK"       "command -v rtk"       "curl -fsSL https://rtk.dev/install.sh | sh"

if dpkg -s gh >/dev/null 2>&1; then
  ok "GitHub CLI ya instalado"
else
  info 'Instalando GitHub CLI...'
  sudo_run apt-get install -y --no-install-recommends gh
fi

if command -v aws >/dev/null 2>&1; then
  ok "AWS CLI ya instalado"
else
  info 'Instalando AWS CLI...'
  # ponytail: inline curl-pipe, add checksum verification if installation becomes frequent
  run bash -c 'curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip && unzip -q /tmp/awscliv2.zip -d /tmp/ && sudo /tmp/aws/install && rm -rf /tmp/aws /tmp/awscliv2.zip'
fi

# ---------------------------------------------------------------------------
# Fase 4: Docker (opcional)
# ---------------------------------------------------------------------------
if [[ $SKIP_DOCKER == false ]]; then
  phase "Docker"
  if command -v docker >/dev/null 2>&1; then
    ok "Docker ya instalado ($(docker --version 2>/dev/null))"
  else
    info 'Instalando Docker...'
    run bash -c 'curl -fsSL https://get.docker.com | sh'
    run sudo usermod -aG docker "$USER"
    info "Docker instalado. Cierra sesión y vuelve a entrar para usar Docker sin sudo."
  fi
else
  skip 'Docker omitido (--skip-docker)'
fi

# ---------------------------------------------------------------------------
# Fase 5: Plugins de OpenCode
# ---------------------------------------------------------------------------
phase "Plugins de OpenCode"

OC_CONFIG="${OPENCODE_CONFIG:-$HOME/.config/opencode/opencode.json}"
if [[ -f "$OC_CONFIG" ]]; then
  PLUGIN_LIST=$(jq -r '(.plugin // [])[]' "$OC_CONFIG" 2>/dev/null || true)
  if echo "$PLUGIN_LIST" | grep -q '@dietrichgebert/ponytail'; then
    ok "Ponytail ya registrado"
  else
    info 'Registrando Ponytail...'
    if [[ $DRY_RUN == true ]]; then
      info "[simulado] Agregar ponytail como plugin"
    else
      TMP=$(mktemp)
      jq '.plugin = ((.plugin // []) + ["@dietrichgebert/ponytail@latest"] | unique)' "$OC_CONFIG" > "$TMP" && mv "$TMP" "$OC_CONFIG"
      chmod 600 "$OC_CONFIG"
      ok "Ponytail registrado en opencode.json"
    fi
  fi
else
  info "opencode.json no encontrado en $OC_CONFIG"
fi

# ---------------------------------------------------------------------------
# Fase 6: Configuración del harness
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
# Fase 7: Servidores MCP (mediante opencode.json)
# ---------------------------------------------------------------------------
phase "Servidores MCP"

OC_FILE="${OPENCODE_CONFIG_FILE:-$HOME/.config/opencode/opencode.json}"

if [[ ! -f "$OC_FILE" ]]; then
  info "opencode.json no encontrado en $OC_FILE; los MCPs se configurarán cuando exista"
else
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    type=$(parse_mcp_field "$name" "type")
    cmd=$(parse_mcp_field "$name" "command")

    exists=$(jq --arg n "$name" '.mcp // {} | has($n)' "$OC_FILE" 2>/dev/null || false)
    if [[ $exists == true ]]; then
      ok "MCP $name ya configurado en opencode.json"
      continue
    fi

    info "Agregando MCP $name a opencode.json..."
    if [[ $DRY_RUN == true ]]; then
      info "[simulado] jq injectaría MCP $name"
    else
      TMP=$(mktemp)
      if [[ $type == local && -n "$cmd" ]]; then
        cmd_array=$(printf '%s' "$cmd" | jq -R 'split(" ")')
        jq --arg n "$name" --argjson cmd "$cmd_array" \
          '.mcp[$n] = {type: "local", command: $cmd, enabled: true}' \
          "$OC_FILE" > "$TMP" && mv "$TMP" "$OC_FILE"
      else
        skip "MCP remoto $name: bootstrap no configura servidores remotos. Configúralo manualmente en opencode.json"
        continue
      fi
      chmod 600 "$OC_FILE"
      ok "MCP $name registrado"
    fi
  done < <(parse_mcp_names)

  info "MCPs excluidos del bootstrap: alegra-test (incompatible), remotos sin URL (configurar manualmente)"
fi

# ---------------------------------------------------------------------------
# Fase 8: Verificación
# ---------------------------------------------------------------------------
phase "Verificación"

if [[ -f "$ROOT_DIR/scripts/doctor.sh" ]]; then
  info 'Ejecutando doctor.sh...'
  run bash "$ROOT_DIR/scripts/doctor.sh" || true
fi

# ---------------------------------------------------------------------------
# Resumen
# ---------------------------------------------------------------------------
printf '\n========================================\n'
printf '  Bootstrap completado\n'
if [[ $DRY_RUN == true ]]; then
  printf '  (simulación, no se realizaron cambios)\n'
fi
printf '========================================\n'
printf '\nPróximos pasos:\n'
printf '  1. Autentica MCPs OAuth:\n'

while IFS= read -r name; do
  oauth=$(parse_mcp_field "$name" "oauth_required")
  if [[ "$oauth" == "true" ]]; then
    printf '     opencode mcp auth %s\n' "$name"
  fi
done < <(parse_mcp_names)

printf '\n  2. Verifica estado con doctor.sh\n'
printf '     bash scripts/doctor.sh\n'
printf '\n  3. Si es primera instalación, reinicia OpenCode\n'
printf '\n'
