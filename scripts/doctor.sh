#!/usr/bin/env bash
set -u

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CONFIG_ROOT=${XDG_CONFIG_HOME:-"$HOME/.config"}
HARNESS_CONFIG_DIR=${DANIEL_HARNESS_CONFIG_DIR:-"$CONFIG_ROOT/daniel-harness"}
OPENCODE_CONFIG_DIR=${OPENCODE_CONFIG_DIR:-"$CONFIG_ROOT/opencode"}
OPENCODE_CONFIG_FILE=${OPENCODE_CONFIG_FILE:-"$OPENCODE_CONFIG_DIR/opencode.json"}
REPOSITORY_DIR=${DANIEL_HARNESS_REPO:-"$ROOT_DIR"}
STRICT=false
PROFILE=
WARNINGS=0
CRITICAL=0

# ponytail: hardcoded matrix, source of truth is bootstrap/manifest.yaml
PROFILE_TOOLS_required="core:opencode gentle-ai engram codegraph rtk dh
alegra:opencode gentle-ai engram codegraph rtk dh gh aws
migration:opencode gentle-ai engram codegraph rtk dh gh aws docker
full:opencode gentle-ai engram codegraph rtk dh gh aws docker"

PROFILE_MCPS_required="core:codegraph engram
alegra:codegraph engram linear context7 wiki-alegra github
migration:codegraph engram linear context7 wiki-alegra github mcp-raia-lib
full:codegraph engram linear context7 wiki-alegra github mcp-raia-lib sentry"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --strict) STRICT=true; shift ;;
    --profile) PROFILE=$2; shift 2 ;;
    --profile=*) PROFILE=${1#*=}; shift ;;
    --help|-h) printf 'Uso: doctor.sh [--strict] [--profile core|alegra|migration|full]\n'; exit 0 ;;
    *) printf 'Argumento desconocido: %s\n' "$1" >&2; exit 1 ;;
  esac
done

ok() { printf '[ok] %s\n' "$*"; }
warn() { printf '[aviso] %s\n' "$*"; WARNINGS=$((WARNINGS + 1)); }
critical() { printf '[crítico] %s\n' "$*"; CRITICAL=$((CRITICAL + 1)); }

get_profile_tools() {
  local p=$1
  echo "$PROFILE_TOOLS_required" | awk -F: -v p="$p" '$1 == p { print $2 }'
}

get_profile_mcps() {
  local p=$1
  echo "$PROFILE_MCPS_required" | awk -F: -v p="$p" '$1 == p { print $2 }'
}

tool_status() {
  local label=$1
  local command_name=$2
  local severity=${3:-warn}

  if command -v "$command_name" >/dev/null 2>&1; then
    ok "$label disponible"
  else
    if [[ $severity == critical ]]; then
      critical "$label no encontrado (requerido por perfil $PROFILE)"
    else
      warn "$label no encontrado"
    fi
  fi
}

check_permissions() {
  local path=$1
  local expected_type=$2
  local mode

  if [[ ! -e "$path" ]]; then
    warn "$path no existe"
    return
  fi

  mode=$(stat -c '%a' "$path" 2>/dev/null || true)
  if [[ ! $mode =~ ^[0-7]{3,4}$ ]]; then
    warn "no se pudieron revisar los permisos de $path"
    return
  fi

  if (( (8#$mode & 077) != 0 )); then
    critical "$path tiene permisos $mode; $expected_type no debe permitir acceso a grupo u otros"
  else
    ok "$path tiene permisos $mode"
  fi
}

is_port_open() {
  local host=$1
  local port=$2

  command -v timeout >/dev/null 2>&1 && timeout 1 bash -c "</dev/tcp/$host/$port" 2>/dev/null
}

list_required_tunnels() {
  local connections_file="$HARNESS_CONFIG_DIR/connections.yaml"

  [[ -f "$connections_file" ]] || return

  awk '
    function clean(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      gsub(/^"|"$/, "", value)
      return value
    }
    function emit() {
      if (id != "" && required == "true" && host != "" && port != "" && command_ref != "") {
        print id "\t" host "\t" port "\t" command_ref
      }
    }
    /^  - id:/ {
      emit()
      id = $0
      sub(/^  - id:[[:space:]]*/, "", id)
      id = clean(id)
      host = ""
      port = ""
      required = ""
      command_ref = ""
      next
    }
    /^    host:/ {
      host = $0
      sub(/^    host:[[:space:]]*/, "", host)
      host = clean(host)
      next
    }
    /^    port:/ {
      port = $0
      sub(/^    port:[[:space:]]*/, "", port)
      port = clean(port)
      next
    }
    /^      required:/ {
      required = $0
      sub(/^      required:[[:space:]]*/, "", required)
      required = clean(required)
      next
    }
    /^      commandRef:/ {
      command_ref = $0
      sub(/^      commandRef:[[:space:]]*/, "", command_ref)
      command_ref = clean(command_ref)
      next
    }
    END { emit() }
  ' "$connections_file"
}

check_tunnels() {
  local row id host port command_ref command_path count=0

  while IFS= read -r row; do
    IFS=$'\t' read -r id host port command_ref <<<"$row"
    count=$((count + 1))

    if [[ ! $command_ref =~ ^secrets/tunnels/[a-z0-9][a-z0-9._-]*\.command$ ]]; then
      critical "commandRef inválido para el túnel $id"
      continue
    fi

    command_path="$HARNESS_CONFIG_DIR/$command_ref"

    if [[ $host != 127.0.0.1 && $host != localhost ]]; then
      critical "El túnel $id debe apuntar a un host local, no a $host"
      continue
    fi

    if [[ ! $port =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
      critical "Puerto local inválido para el túnel $id"
      continue
    fi

    check_permissions "$command_path" archivo

    if is_port_open "$host" "$port"; then
      ok "Túnel activo: $id ($host:$port)"
    else
      warn "Falta el túnel $id ($host:$port). Ejecuta: bash $command_path"
    fi
  done < <(list_required_tunnels)

  if (( count == 0 )); then
    warn 'No hay túneles requeridos configurados en connections.yaml'
  fi
}

has_hardcoded_sensitive_values() {
  jq -e '
    def normalized_key:
      ascii_downcase | gsub("[-_]"; "");
    def sensitive_key:
      normalized_key |
      test("^(header|headers|authorization|bearer|env|environment|.*(token|tokens|secret|secrets|password|passwords|passwd|credential|credentials|apikey|apikeys|accesskey|accesskeys|accesskeyid|privatekey|privatekeys))$");
    def sensitive_command_argument:
      type == "string" and
      test("(^|[-_/])(authorization|auth[-_]?token|token|secret|password|api[-_]?key|credential)(=|:|$)"; "i");
    def embedded_credentials:
      type == "string" and
      test("^[a-z][a-z0-9+.-]*://[^/@[:space:]]+:[^/@[:space:]]+@"; "i");
    def external_reference:
      type == "string" and test("^\\{(env|file):[^}]+\\}$"; "i");
    def contains_literal:
      if type == "string" then
        length > 0 and (external_reference | not)
      elif type == "object" or type == "array" then
        any(.[]; contains_literal)
      elif type == "null" then
        false
      else
        true
      end;
    [
      .. | objects | to_entries[]? |
      select(
        ((.key | sensitive_key) and (.value | contains_literal)) or
        (.value | embedded_credentials) or
        (
          ((.key | ascii_downcase) == "command") and
          ([.value | .. | strings | select(sensitive_command_argument)] | length > 0)
        )
      )
    ] | length > 0
  ' "$OPENCODE_CONFIG_FILE" >/dev/null 2>&1
}

has_broad_bash_permission() {
  jq -e '
    def broad:
      . == "allow" or
      (type == "object" and ((.["*"] // "") == "allow"));
    ((.permission.bash // "deny") | broad) or
    any((.agent // {})[]?; ((.permission.bash // "deny") | broad))
  ' "$OPENCODE_CONFIG_FILE" >/dev/null 2>&1
}

has_restricted_models() {
  local harness_config="$HARNESS_CONFIG_DIR/config.yaml"
  [[ -f "$harness_config" ]] && grep -Eiq '^[[:space:]]*trust:[[:space:]]*restricted[[:space:]]*$' "$harness_config"
}

check_mcp_live() {
  local name=$1
  if ! command -v opencode >/dev/null 2>&1; then
    echo "opencode-no-instalado"
    return
  fi
  local debug_out
  debug_out=$(opencode mcp debug "$name" 2>&1 || true)
  if echo "$debug_out" | grep -qiE '(connected|healthy|ok|running)'; then
    echo "connected"
  elif echo "$debug_out" | grep -qi 'auth'; then
    echo "auth-required"
  elif [[ -z "$debug_out" || "$debug_out" == *"not found"* ]]; then
    echo "desconocido"
  else
    echo "inaccesible"
  fi
}

print_mcp_status() {
  local row name enabled kind executable status live

  while IFS= read -r row; do
    IFS=$'\t' read -r name enabled kind executable <<<"$row"
    status=configurado
    live=

    if [[ $enabled == false ]]; then
      status=deshabilitado
    elif [[ $kind == local && -n $executable ]]; then
      if command -v "$executable" >/dev/null 2>&1; then
        live=$(check_mcp_live "$name")
        status=$live
      else
        status=comando-no-encontrado
      fi
    elif [[ $kind == remote ]]; then
      live=$(check_mcp_live "$name")
      status=$live
    fi

    printf '[mcp] nombre=%s habilitado=%s tipo=%s estado=%s\n' "$name" "$enabled" "$kind" "$status"
  done < <(
    jq -r '
      (.mcp // {}) | to_entries[] |
      [
        .key,
        ((if .value.enabled == null then true else .value.enabled end) | tostring),
        (if .value.type then .value.type elif .value.command then "local" elif .value.url then "remote" else "unknown" end),
        (.value.command[0] // "")
      ] | @tsv
    ' "$OPENCODE_CONFIG_FILE"
  )
}

check_gentle_ai() {
  local version review_mode doctor_output

  if ! command -v gentle-ai >/dev/null 2>&1; then
    warn 'Gentle AI no encontrado'
    return
  fi

  version=$(gentle-ai version 2>/dev/null || true)
  ok "Gentle AI disponible: ${version:-versión desconocida}"

  if review_mode=$(gentle-ai review mode status --cwd "$REPOSITORY_DIR" 2>/dev/null); then
    ok "$(printf '%s\n' "$review_mode" | sed -n '1p')"
  else
    warn 'No se pudo consultar el modo RDD de Gentle AI'
  fi

  doctor_output=$(gentle-ai doctor 2>/dev/null || true)
  if grep -Fq 'Status:  healthy' <<<"$doctor_output"; then
    ok 'Ecosistema Gentle AI saludable'
  else
    warn 'gentle-ai doctor reporta estado degradado'
  fi

  if [[ -f "$REPOSITORY_DIR/.atl/skill-registry.md" ]]; then
    ok 'Skill registry de Gentle AI disponible'
  else
    warn 'Skill registry ausente; ejecuta gentle-ai skill-registry refresh --force'
  fi
}

validate_profile_agents() {
  local agent_dir="$OPENCODE_CONFIG_DIR/agents"
  local required=("alegra-microservice-engineer" "code-reviewer" "alegra-microservice-test-engineer" "php-engineer" "migration-parity-reviewer")
  local missing=0

  for agent in "${required[@]}"; do
    if [[ -f "$agent_dir/$agent.md" || -L "$agent_dir/$agent.md" ]]; then
      ok "Agente $agent presente"
    else
      critical "Agente $agent no encontrado (requerido)"
      missing=$((missing + 1))
    fi
  done

  if [[ -L "$agent_dir/senior-engineer.md" ]]; then
    warn "Agente legacy senior-engineer todavía presente; ejecuta install.sh para limpiar"
  fi
  if [[ -L "$agent_dir/test-engineer.md" ]]; then
    warn "Agente legacy test-engineer todavía presente; ejecuta install.sh para limpiar"
  fi
}

validate_profile_skills() {
  local skill_dir="$OPENCODE_CONFIG_DIR/skills"
  local required=("monolith-to-micro-migration" "task-lifecycle")

  for skill in "${required[@]}"; do
    if [[ -d "$skill_dir/$skill" || -L "$skill_dir/$skill" ]]; then
      ok "Skill $skill presente"
    else
      critical "Skill $skill no encontrada (requerida)"
    fi
  done
}

printf 'Diagnóstico de Daniel Harness\n'
if [[ -n "$PROFILE" ]]; then
  printf 'Perfil: %s\n\n' "$PROFILE"
fi

printf 'Herramientas\n'
tool_status Git git
tool_status 'GitHub CLI' gh
tool_status OpenCode opencode
check_gentle_ai
tool_status RTK rtk
tool_status CodeGraph codegraph
tool_status 'DH CLI' dh
tool_status Docker docker
tool_status jq jq
tool_status 'AWS CLI' aws

if command -v mariadb >/dev/null 2>&1 || command -v mysql >/dev/null 2>&1; then
  ok 'Cliente MariaDB/MySQL disponible'
else
  warn 'Cliente MariaDB/MySQL no encontrado'
fi

if [[ -n "$PROFILE" ]]; then
  printf '\nValidación de perfil %s\n' "$PROFILE"
  profile_tools=$(get_profile_tools "$PROFILE")
  if [[ -n "$profile_tools" ]]; then
    for tool in $profile_tools; do
      tool_status "$tool" "$tool" critical
    done
  fi
fi

printf '\nConfiguración\n'
check_permissions "$HARNESS_CONFIG_DIR" directorio
check_permissions "$HARNESS_CONFIG_DIR/secrets" directorio
check_permissions "$HARNESS_CONFIG_DIR/config.yaml" archivo
check_permissions "$HARNESS_CONFIG_DIR/connections.yaml" archivo
check_permissions "$HARNESS_CONFIG_DIR/project-registry.yaml" archivo

if [[ -n "$PROFILE" ]]; then
  validate_profile_agents
  validate_profile_skills
fi

printf '\nMCPs de OpenCode\n'
if [[ ! -f "$OPENCODE_CONFIG_FILE" ]]; then
  warn 'No se encontró la configuración de OpenCode; inventario MCP no disponible'
elif ! command -v jq >/dev/null 2>&1; then
  warn 'jq no está disponible; no se inspeccionó la configuración de OpenCode'
elif ! jq empty "$OPENCODE_CONFIG_FILE" >/dev/null 2>&1; then
  warn 'La configuración de OpenCode no es JSON válido; se omitió el inventario MCP'
else
  print_mcp_status

  if has_hardcoded_sensitive_values; then
    critical 'OpenCode contiene valores sensibles hardcodeados; no se mostraron los valores'
  else
    jq_status=$?
    if (( jq_status == 1 )); then
      ok 'No se detectaron patrones soportados de secretos hardcodeados en OpenCode'
    else
      critical 'No se pudo evaluar si OpenCode contiene valores sensibles hardcodeados'
    fi
  fi

  if has_restricted_models; then
    if has_broad_bash_permission; then
      critical 'Hay modelos restricted mientras OpenCode concede acceso Bash amplio'
    else
      jq_status=$?
      if (( jq_status != 1 )); then
        critical 'No se pudo evaluar el acceso Bash de modelos restricted'
      fi
    fi

    agent_dir="$OPENCODE_CONFIG_DIR/agents"
    if [[ -d "$agent_dir" ]]; then
      for agent_file in "$agent_dir/"*.md; do
        [[ -f "$agent_file" ]] || continue
        if grep -Eq '^\s+bash:\s+(allow|ask)$' "$agent_file" 2>/dev/null; then
          critical "Agente $(basename "$agent_file" .md) tiene bash sin wildcard deny con modelos restricted"
        fi
      done
    fi
  fi

  if [[ -n "$PROFILE" ]]; then
    profile_mcps=$(get_profile_mcps "$PROFILE")
    if [[ -n "$profile_mcps" ]]; then
      for mcp in $profile_mcps; do
        configured=$(jq --arg n "$mcp" '.mcp // {} | has($n)' "$OPENCODE_CONFIG_FILE" 2>/dev/null || false)
        if [[ $configured == false ]]; then
          critical "MCP $mcp no configurado (requerido por perfil $PROFILE)"
        fi
      done
    fi
  fi
fi

printf '\nTúneles locales\n'
check_tunnels

printf '\nRepositorio\n'
if git -C "$REPOSITORY_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  ok 'Repositorio Git detectado'
  warn 'Visibilidad no verificada; doctor no llama APIs del hosting'
else
  critical 'La ruta del repositorio no es un worktree Git'
fi

printf '\nResumen: %d crítico(s), %d aviso(s)\n' "$CRITICAL" "$WARNINGS"
if [[ $STRICT == true ]] && (( CRITICAL > 0 )); then
  exit 1
fi
(( CRITICAL == 0 ))
