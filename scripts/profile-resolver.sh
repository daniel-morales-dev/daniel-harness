#!/usr/bin/env bash
# Perfil resolutor compartido — fuente única para herencia extends
# Uso: source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/profile-resolver.sh"
# Requiere: MANIFEST apuntando a bootstrap/manifest.yaml

if [[ -z "${MANIFEST:-}" ]]; then
  MANIFEST=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bootstrap/manifest.yaml
fi

_get_profile_field() {
  local p=$1 field=$2
  awk -v p="$p" -v f="$field" '
    $0 ~ "^profiles:" { in_profiles=1; next }
    in_profiles && $0 ~ "^  " p ":" { in_profile=1; next }
    in_profile && $0 ~ "^    " f ":" {
      sub(/^[[:space:]]*[a-z_]+:[[:space:]]*/, "")
      gsub(/^\[|\]$/, "")
      gsub(/["\x27]/, "")
      gsub(/[[:space:]]*,[[:space:]]*/, "\n")
      print; exit
    }
    in_profile && !/^    / && !/^[[:space:]]*$/ { in_profile=0 }
  ' "$MANIFEST"
}

_get_profile_extend() {
  local p=$1
  awk -v p="$p" '
    $0 ~ "^profiles:" { in_profiles=1; next }
    in_profiles && $0 ~ "^  " p ":" { in_profile=1; next }
    in_profile && $0 ~ "^    extends:" {
      sub(/^[[:space:]]*extends:[[:space:]]*/, "")
      gsub(/^["\x27]/, ""); gsub(/["\x27]$/, "")
      print; exit
    }
    in_profile && !/^    / && !/^[[:space:]]*$/ { in_profile=0 }
  ' "$MANIFEST"
}

# Merge field across inheritance chain (unique values, parent preserved)
_resolve_profile_field() {
  local p=$1 field=$2
  local result="" seen=""
  while [[ -n "$p" ]]; do
    local items
    items=$(_get_profile_field "$p" "$field")
    if [[ -n "$items" ]]; then
      while IFS= read -r item; do
        [[ -z "$item" ]] && continue
        if ! echo "$seen" | grep -qxF "$item" 2>/dev/null; then
          result="${result}${item}"$'\n'
          seen="${seen}${item}"$'\n'
        fi
      done <<< "$items"
    fi
    local last_p=$p
    p=$(_get_profile_extend "$p")
    [[ "$p" == "$last_p" ]] && break
  done
  echo "$result" | grep -v '^$' || true
}

get_profile_tools()   { _resolve_profile_field "$1" "tools"; }
get_profile_mcps()    { _resolve_profile_field "$1" "mcps"; }
get_profile_plugins() { _resolve_profile_field "$1" "plugins"; }
get_profile_optional_packages() { _resolve_profile_field "$1" "optional_packages"; }

_profile_field_contains() {
  local p=$1 field=$2 item=$3
  local items
  items=$(_get_profile_field "$p" "$field")
  echo "$items" | grep -qxF "$item" 2>/dev/null
}

profile_includes() {
  local p=$1 field=$2 item=$3
  local last_p
  while [[ -n "$p" ]]; do
    if _profile_field_contains "$p" "$field" "$item"; then
      return 0
    fi
    last_p=$p
    p=$(_get_profile_extend "$p")
    [[ "$p" == "$last_p" ]] && break
  done
  return 1
}

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
  local section=$1 key=$2
  awk -v sec="$section" -v k="$key" '
    $0 ~ "^" sec ":" { in_section=1; next }
    in_section && $0 ~ "^  " k ":" {
      sub(/^  [a-z_]+:[[:space:]]*/,"")
      sub(/^["\x27]/,""); sub(/["\x27]$/,"")
      print; exit
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
