#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MANIFEST="$ROOT_DIR/bootstrap/manifest.yaml"
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

parse_mcp_headers_json() {
  local name=$1
  awk -v n="$name" '
    /^mcp_servers:/{in_mcp=1; next}
    in_mcp {
      if ($0 ~ "^  " n ":" && !found) { found=1; next }
      if (found && $0 ~ "^    headers:") { in_headers=1; next }
      if (in_headers && $0 ~ /^      [a-z]/) {
        gsub(/^      /, "")
        split($0, parts, ": ")
        key = parts[1]
        sub(/^"/, "", parts[2]); sub(/"$/, "", parts[2])
        val = parts[2]
        for(i=3; i<=length(parts); i++) val = val ": " parts[i]
        if (first) printf ","
        printf "\"%s\": \"%s\"", key, val
        first=1
        next
      }
      if (found && $0 ~ /^  [a-z]/) { found=0; in_headers=0 }
      if (in_headers && $0 !~ /^      / && $0 !~ /^[[:space:]]*$/) { in_headers=0 }
    }
    BEGIN { printf "{" }
    END { printf "}" }
  ' "$MANIFEST"
}

# Parseadores de perfiles
profile_includes() {
  local field=$1 item=$2
  awk -v p="$PROFILE" -v f="$field" -v i="$item" '
    $0 ~ "^profiles:" { in_profiles=1; next }
    in_profiles && $0 ~ "^  " p ":" { in_profile=1; next }
    in_profile && $0 ~ "^    " f ":" {
      if (index($0, "\"" i "\"") > 0 || index($0, "'\''" i "'\''") > 0) { found=1; exit }
      sub(/^[[:space:]]*[a-z_]+:[[:space:]]*/, "")
      if (index($0, i) > 0) { found=1; exit }
    }
    in_profile && !/^    / && $0 !~ /^[[:space:]]*$/ { in_profile=0 }
    END { exit found ? 0 : 1 }
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
  if profile_includes "optional_packages" "$pkg"; then
    dpkg -s "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
  else
    skip "Paquete opcional $pkg (no incluido en perfil $PROFILE)"
  fi
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

install_tool_if_in_profile() {
  local profile_key=$1 label=$2 check=$3 install_cmd=$4
  if profile_includes "tools" "$profile_key"; then
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

if profile_includes "tools" "gh"; then
  if dpkg -s gh >/dev/null 2>&1; then
    ok "GitHub CLI ya instalado"
  else
    info 'Instalando GitHub CLI...'
    sudo_run apt-get install -y --no-install-recommends gh
  fi
else
  skip "GitHub CLI (no incluido en perfil $PROFILE)"
fi

if profile_includes "tools" "aws"; then
  if command -v aws >/dev/null 2>&1; then
    ok "AWS CLI ya instalado"
  else
    info 'Instalando AWS CLI...'
    # ponytail: inline curl-pipe, add checksum verification if installation becomes frequent
    run bash -c 'curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip && unzip -q /tmp/awscliv2.zip -d /tmp/ && sudo /tmp/aws/install && rm -rf /tmp/aws /tmp/awscliv2.zip'
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
      critical "opencode.json existe pero no es JSON válido"
      critical "  Backup: cp \"$OC_FILE\" \"${OC_FILE}.bak.$(date +%s)\""
      critical "  No se realizaron cambios. Corrige el JSON o elimina el archivo para regenerarlo."
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
if profile_includes "tools" "docker"; then
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

if profile_includes "plugins" "ponytail"; then
  PLUGIN_LIST=$(jq -r '(.plugin // [])[]' "$OC_FILE" 2>/dev/null || true)
  if echo "$PLUGIN_LIST" | grep -q '@dietrichgebert/ponytail'; then
    ok "Ponytail ya registrado"
  else
    info 'Registrando Ponytail...'
    if [[ $DRY_RUN == true ]]; then
      info "[simulado] Agregar ponytail como plugin"
    else
      TMP=$(mktemp)
      jq '.plugin = ((.plugin // []) + ["@dietrichgebert/ponytail@latest"] | unique)' "$OC_FILE" > "$TMP" && mv "$TMP" "$OC_FILE"
      chmod 600 "$OC_FILE"
      ok "Ponytail registrado en opencode.json"
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
MCP_EXISTING=0

_mcp_jq() {
  local tmp_next
  tmp_next=$(mktemp)
  jq "$@" "$TMP_CANDIDATE" > "$tmp_next" && mv "$tmp_next" "$TMP_CANDIDATE"
}

while IFS= read -r name; do
  [[ -z "$name" ]] && continue
  if ! profile_includes "mcps" "$name"; then
    skip "MCP $name (no incluido en perfil $PROFILE)"
    continue
  fi
  type=$(parse_mcp_field "$name" "type")
  cmd=$(parse_mcp_field "$name" "command")

  exists=$(jq --arg n "$name" '.mcp // {} | has($n)' "$TMP_CANDIDATE" 2>/dev/null || false)
  if [[ $exists == true ]]; then
    ok "MCP $name ya configurado"
    MCP_EXISTING=$((MCP_EXISTING + 1))
    continue
  fi

  info "Agregando MCP $name..."
  if [[ $DRY_RUN == true ]]; then
    info "[simulado] jq injectaría MCP $name"
    MCP_ADDED=$((MCP_ADDED + 1))
    continue
  fi

  if [[ $type == local && -n "$cmd" ]]; then
    if echo "$cmd" | jq -e '. | type == "array"' >/dev/null 2>&1; then
      cmd_array=$cmd
    else
      cmd_array=$(printf '%s' "$cmd" | jq -R 'split(" ")')
    fi
    local cmd_first cmd_enabled
    cmd_first=$(echo "$cmd_array" | jq -r '.[0] // ""')
    cmd_enabled=true
    if [[ "$cmd_first" == "docker" ]] && { [[ $SKIP_DOCKER == true ]] || ! command -v docker >/dev/null 2>&1; }; then
      cmd_enabled=false
      warn "MCP $name requiere Docker — registrado como deshabilitado"
    fi
    _mcp_jq --arg n "$name" --argjson cmd "$cmd_array" --arg e "$cmd_enabled" \
      '.mcp[$n] = {type: "local", command: $cmd, enabled: ($e == "true")}'
  elif [[ $type == remote ]]; then
    url=$(parse_mcp_field "$name" "url")
    if [[ -n "$url" ]]; then
      headers_json=$(parse_mcp_headers_json "$name")
      if [[ "$headers_json" != "{}" ]]; then
        _mcp_jq --arg n "$name" --arg u "$url" --argjson h "$headers_json" \
          '.mcp[$n] = {type: "remote", url: $u, enabled: true, headers: $h}'
      else
        _mcp_jq --arg n "$name" --arg u "$url" \
          '.mcp[$n] = {type: "remote", url: $u, enabled: true}'
      fi
    else
      skip "MCP remoto $name: sin URL. Configúralo manualmente en opencode.json"
      continue
    fi
  else
    skip "MCP $name: tipo desconocido '$type'. Configúralo manualmente"
    continue
  fi
  ok "MCP $name registrado en candidato"
  MCP_ADDED=$((MCP_ADDED + 1))
done < <(parse_mcp_names)

if [[ $DRY_RUN == false && $MCP_ADDED -gt 0 ]]; then
  if jq empty "$TMP_CANDIDATE" >/dev/null 2>&1; then
    BACKUP="${OC_FILE}.bak.$(date +%s)"
    cp "$OC_FILE" "$BACKUP"
    chmod 600 "$BACKUP"
    mv "$TMP_CANDIDATE" "$OC_FILE"
    chmod 600 "$OC_FILE"
    ok "Configuración aplicada transaccionalmente (${MCP_ADDED} nuevos, ${MCP_EXISTING} existentes)"
    info "Backup: $BACKUP"
  else
    critical "Candidato JSON inválido — cambios NO aplicados"
    rm -f "$TMP_CANDIDATE"
  fi
elif [[ $DRY_RUN == false && $MCP_ADDED -eq 0 ]]; then
  rm -f "$TMP_CANDIDATE"
  ok "No hay MCPs nuevos que agregar"
fi

info "MCPs excluidos del bootstrap: alegra-test (incompatible), remotos sin url (configurar manualmente)"

# ---------------------------------------------------------------------------
# Fase 8: Verificación
# ---------------------------------------------------------------------------
phase "Verificación"

if [[ -f "$ROOT_DIR/scripts/doctor.sh" ]]; then
  info 'Ejecutando doctor.sh...'
  if run bash "$ROOT_DIR/scripts/doctor.sh" --strict; then
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
