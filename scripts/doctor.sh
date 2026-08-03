#!/usr/bin/env bash
set -u

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CONFIG_ROOT=${XDG_CONFIG_HOME:-"$HOME/.config"}
HARNESS_CONFIG_DIR=${DANIEL_HARNESS_CONFIG_DIR:-"$CONFIG_ROOT/daniel-harness"}
OPENCODE_CONFIG_FILE=${OPENCODE_CONFIG_FILE:-"$CONFIG_ROOT/opencode/opencode.json"}
REPOSITORY_DIR=${DANIEL_HARNESS_REPO:-"$ROOT_DIR"}
WARNINGS=0
CRITICAL=0

ok() { printf '[ok] %s\n' "$*"; }
warn() { printf '[warn] %s\n' "$*"; WARNINGS=$((WARNINGS + 1)); }
critical() { printf '[critical] %s\n' "$*"; CRITICAL=$((CRITICAL + 1)); }

tool_status() {
  local label=$1
  local command_name=$2

  if command -v "$command_name" >/dev/null 2>&1; then
    ok "$label available"
  else
    warn "$label not found"
  fi
}

check_permissions() {
  local path=$1
  local expected_type=$2
  local mode

  if [[ ! -e "$path" ]]; then
    warn "$path not found"
    return
  fi

  mode=$(stat -c '%a' "$path" 2>/dev/null || true)
  if [[ ! $mode =~ ^[0-7]{3,4}$ ]]; then
    warn "could not inspect permissions for $path"
    return
  fi

  if (( (8#$mode & 077) != 0 )); then
    critical "$path permissions are $mode; $expected_type must not allow group or other access"
  else
    ok "$path permissions are $mode"
  fi
}

check_port() {
  local port=$1
  local label=$2

  if command -v timeout >/dev/null 2>&1 && timeout 1 bash -c "</dev/tcp/127.0.0.1/$port" 2>/dev/null; then
    ok "$label port $port is open"
  else
    warn "$label port $port is closed or unreachable"
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

print_mcp_status() {
  local row name enabled kind executable status

  while IFS= read -r row; do
    IFS=$'\t' read -r name enabled kind executable <<<"$row"
    status=configured

    if [[ $kind == local && -n $executable ]]; then
      if command -v "$executable" >/dev/null 2>&1; then
        status=available
      else
        status=command-not-found
      fi
    elif [[ $kind == remote ]]; then
      status=not-probed
    fi

    printf '[mcp] name=%s enabled=%s type=%s status=%s\n' "$name" "$enabled" "$kind" "$status"
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

printf 'Daniel Harness doctor\n\n'

printf 'Tools\n'
tool_status Git git
tool_status 'GitHub CLI' gh
tool_status OpenCode opencode
tool_status 'Gentle AI' gentle-ai
tool_status RTK rtk
tool_status CodeGraph codegraph
tool_status Docker docker
tool_status jq jq
tool_status 'AWS CLI' aws

if command -v mariadb >/dev/null 2>&1 || command -v mysql >/dev/null 2>&1; then
  ok 'MariaDB/MySQL client available'
else
  warn 'MariaDB/MySQL client not found'
fi

printf '\nConfiguration\n'
check_permissions "$HARNESS_CONFIG_DIR" directory
check_permissions "$HARNESS_CONFIG_DIR/secrets" directory
check_permissions "$HARNESS_CONFIG_DIR/config.yaml" file
check_permissions "$HARNESS_CONFIG_DIR/connections.yaml" file
check_permissions "$HARNESS_CONFIG_DIR/project-registry.yaml" file

printf '\nOpenCode MCPs\n'
if [[ ! -f "$OPENCODE_CONFIG_FILE" ]]; then
  warn 'OpenCode configuration not found; MCP inventory unavailable'
elif ! command -v jq >/dev/null 2>&1; then
  warn 'jq not found; OpenCode configuration was not inspected'
elif ! jq empty "$OPENCODE_CONFIG_FILE" >/dev/null 2>&1; then
  warn 'OpenCode configuration is not valid JSON; MCP inventory was skipped'
else
  print_mcp_status

  if has_hardcoded_sensitive_values; then
    critical 'OpenCode configuration contains hardcoded sensitive values; values were not displayed'
  else
    ok 'No supported hardcoded-secret patterns detected in OpenCode JSON'
  fi

  if has_restricted_models && has_broad_bash_permission; then
    critical 'Restricted model profiles exist while OpenCode grants broad Bash access'
  fi
fi

printf '\nLocal ports\n'
check_port 60001 'Alegra hopper MySQL'
check_port 55000 'Alegra production MySQL'
check_port 3306 'K Agencia MySQL'
check_port 27017 'K Agencia MongoDB'
check_port 3900 'K Agencia Garage'

printf '\nRepository\n'
if git -C "$REPOSITORY_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  ok 'Git repository detected'
  warn 'Repository visibility not verified; doctor does not call hosting APIs'
else
  critical 'Repository directory is not a Git worktree'
fi

printf '\nSummary: %d critical, %d warning(s)\n' "$CRITICAL" "$WARNINGS"
(( CRITICAL == 0 ))
