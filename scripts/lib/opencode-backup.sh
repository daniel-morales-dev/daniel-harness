# scripts/lib/opencode-backup.sh
# Backup/restore system for opencode.json — sourced, not executed
set -euo pipefail

# ID único: timestamp-UTC + componente aleatorio de 6 caracteres
_backup_id() {
  printf '%s-%06x' "$(date -u +%Y%m%d-%H%M%S)" $((RANDOM % 16777216))
}

# Verificar y canonicalizar ruta de backup
_backup_canonicalize() {
  local path=$1
  readlink -f "$path" 2>/dev/null || { printf '%s\n' "$path"; return 1; }
}

# Crear backup de opencode.json con metadata
opencode_backup_create() {
  local source=${1:?source path required}
  local config_dir=${2:?HARNESS_CONFIG_DIR required}
  local backup_dir="$config_dir/backups"
  local harness_version="${HARNESS_VERSION:-unknown}"

  [[ -f "$source" ]] || { printf 'error: source not found\n' >&2; exit 1; }
  jq empty "$source" 2>/dev/null || { printf 'error: invalid JSON\n' >&2; exit 1; }

  mkdir -p "$backup_dir"
  chmod 700 "$backup_dir"

  local sum bid ts id dest meta_source meta_dest tmp tmp_meta
  sum=$(sha256sum "$source" | cut -d' ' -f1)
  bid=$(_backup_id)
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # Backup file: temp en mismo directorio → rename
  dest="$backup_dir/opencode-${bid}.json"
  meta_source="$dest"  # backup es el source de la metadata
  meta_dest="$backup_dir/opencode-${bid}.json.meta"

  # Escribir backup a temp
  tmp="$backup_dir/.opencode-${bid}.json.tmp.$$"
  cp "$source" "$tmp"
  chmod 600 "$tmp"

  local tmp_sum
  tmp_sum=$(sha256sum "$tmp" | cut -d' ' -f1)
  [[ "$sum" == "$tmp_sum" ]] || { rm -f "$tmp"; printf 'error: checksum mismatch\n' >&2; exit 1; }
  mv "$tmp" "$dest"
  chmod 600 "$dest"

  # Escribir metadata a temp → rename
  tmp_meta="$backup_dir/.opencode-${bid}.json.meta.tmp.$$"
  jq -n \
    --arg id "$bid" \
    --arg sha256 "$sum" \
    --arg sourcePath "$source" \
    --arg dateUtc "$ts" \
    --arg mode "600" \
    --arg hv "$harness_version" \
    --arg rt "opencode-config" \
    '{backupId: $id, sha256: $sha256, sourcePath: $sourcePath, dateUtc: $dateUtc, mode: $mode, harnessVersion: $hv, resourceType: $rt}' \
    > "$tmp_meta"
  chmod 600 "$tmp_meta"
  mv "$tmp_meta" "$meta_dest"
  chmod 600 "$meta_dest"

  printf '%s\n' "$dest"
}

# Listar backups disponibles (con metadata si existe)
opencode_backup_list() {
  local config_dir=${1:?HARNESS_CONFIG_DIR required}
  local backup_dir="$config_dir/backups"
  local files=()

  if [[ -d "$backup_dir" ]]; then
    while IFS= read -r -d '' f; do
      files+=("$f")
    done < <(find "$backup_dir" -maxdepth 1 -name 'opencode-*.json' ! -name '*.meta' -print0 2>/dev/null | sort -z)
  fi

  if [[ ${#files[@]} -eq 0 ]]; then
    printf 'No hay backups.\n'
    return 0
  fi

  printf '  #  Backup ID                          Fecha         Tamaño  SHA256    Estado\n'
  local i=1 f name date size sha meta_id meta_valid note
  for f in "${files[@]}"; do
    meta="${f}.meta"
    name=$(basename "$f" .json)
    # Extraer ID del nombre: opencode-<ID>.json
    bid="${name#opencode-}"
    date=$(stat -c '%y' "$f" 2>/dev/null | cut -d' ' -f1 || echo '-')
    size=$(stat -c '%s' "$f" 2>/dev/null || echo '?')
    sha=$(sha256sum "$f" 2>/dev/null | cut -b1-8 || echo '--------')

    if [[ -f "$meta" ]]; then
      if jq empty "$meta" >/dev/null 2>&1; then
        meta_id=$(jq -r '.backupId // ""' "$meta" 2>/dev/null || echo "")
        if [[ "$meta_id" == "$bid" ]]; then
          note="verificado"
        else
          note="id mismatch"
        fi
      else
        note="meta corrupto"
      fi
    else
      note="legacy"
    fi

    printf '%3d  %-36s  %-10s  %5s  %s  %s\n' "$i" "$bid" "$date" "$size" "$sha" "$note"
    i=$((i + 1))
  done
}

# Buscar backups: modernos, legacy, cualquier evidencia
opencode_backup_find_all() {
  local target=${1:?target opencode.json path required}
  local config_dir=${2:?HARNESS_CONFIG_DIR required}
  local target_dir
  target_dir=$(dirname "$target")
  local found=0

  # Backups modernos del harness
  local backup_dir="$config_dir/backups"
  if [[ -d "$backup_dir" ]]; then
    local count
    count=$(find "$backup_dir" -maxdepth 1 -name 'opencode-*.json' ! -name '*.meta' 2>/dev/null | wc -l)
    if [[ "$count" -gt 0 ]]; then
      printf '[backups] %d backup(s) moderno(s) en %s\n' "$count" "$backup_dir"
      found=$((found + count))
    fi
  fi

  # Backups legacy (opencode.json.bak.*)
  if ls "$target_dir"/opencode.json.bak.* >/dev/null 2>&1; then
    local legacy_count
    legacy_count=$(ls -1 "$target_dir"/opencode.json.bak.* 2>/dev/null | wc -l)
    printf '[backups] %d backup(s) legacy en %s\n' "$legacy_count" "$target_dir"
    found=$((found + legacy_count))
  fi

  return "$found"
}

# Restaurar backup
opencode_backup_restore() {
  local input=${1:?backup path or ID required}
  local target=${2:?target path required}
  local config_dir=${3:?HARNESS_CONFIG_DIR required}
  local backup_dir="$config_dir/backups"
  local backup="" meta=""

  if [[ -f "$input" ]]; then
    backup="$input"
    meta="${backup}.meta"
  else
    [[ -d "$backup_dir" ]] || { printf 'error: no backup dir\n' >&2; return 1; }
    local matches=()
    while IFS= read -r -d '' f; do
      matches+=("$f")
    done < <(find "$backup_dir" -maxdepth 1 -name "opencode-${input}*.json" ! -name '*.meta' -print0 2>/dev/null)
    [[ ${#matches[@]} -eq 1 ]] || { printf 'error: ambiguous or not found: %s\n' "$input" >&2; return 1; }
    backup="${matches[0]}"
    meta="${backup}.meta"
  fi

  [[ -f "$backup" ]] || { printf 'error: backup not found\n' >&2; return 1; }
  jq empty "$backup" 2>/dev/null || { printf 'error: backup corrupted\n' >&2; return 1; }

  # Validar metadata si existe
  local meta_valid=true
  if [[ -f "$meta" ]]; then
    jq empty "$meta" 2>/dev/null || meta_valid=false
    if $meta_valid; then
      local meta_sha
      meta_sha=$(jq -r '.sha256 // ""' "$meta" 2>/dev/null || echo "")
      if [[ -n "$meta_sha" ]]; then
        local actual_sha
        actual_sha=$(sha256sum "$backup" | cut -d' ' -f1)
        if [[ "$actual_sha" != "$meta_sha" ]]; then
          printf 'aviso: metadata SHA-256 no coincide con el backup\n' >&2
        fi
      fi
    else
      printf 'aviso: metadata corrupta, verificando solo JSON\n' >&2
    fi
  else
    printf 'aviso: backup legacy sin metadata — integridad historica no demostrable\n' >&2
  fi

  # Safety backup del target actual
  if [[ -f "$target" ]]; then
    local safety
    safety=$(opencode_backup_create "$target" "$config_dir") || {
      printf 'error: safety backup fallo — restore abortado\n' >&2
      return 1
    }
    printf '  safety backup: %s\n' "$safety"
  fi

  # Restaurar: temp en mismo directorio → rename atómico
  local target_dir
  target_dir=$(dirname "$target")
  local tmp
  tmp=$(mktemp "$target_dir/.opencode-restore.tmp.$$.XXXXXXXX")
  cp "$backup" "$tmp"
  chmod 600 "$tmp"

  local tmp_sha backup_sha
  tmp_sha=$(sha256sum "$tmp" | cut -d' ' -f1)
  backup_sha=$(sha256sum "$backup" | cut -d' ' -f1)
  if [[ "$tmp_sha" != "$backup_sha" ]]; then
    rm -f "$tmp"
    printf 'error: checksum mismatch en restore\n' >&2
    return 1
  fi

  mv "$tmp" "$target"
  chmod 600 "$target"

  local final_sha
  final_sha=$(sha256sum "$target" | cut -d' ' -f1)
  [[ "$final_sha" == "$backup_sha" ]] || {
    printf 'error: checksum final no coincide\n' >&2
    return 1
  }

  jq empty "$target" >/dev/null 2>&1 || { printf 'error: target JSON invalido post-restore\n' >&2; return 1; }
  printf 'restaurado: %s\n' "$target"
}

# Diff estructural (nombres y hashes, nunca valores)
opencode_backup_diff() {
  local backup=${1:?backup path required}
  local original=${2:?original path required}

  for f in "$backup" "$original"; do
    jq empty "$f" 2>/dev/null || { printf 'error: invalid JSON: %s\n' "$f" >&2; return 1; }
  done

  _diff_section() {
    local label=$1 filter=$2
    local tmp_b tmp_o
    tmp_b=$(mktemp) && tmp_o=$(mktemp)
    trap 'rm -f "$tmp_b" "$tmp_o"' RETURN

    jq -r "$filter" "$backup" 2>/dev/null | sort > "$tmp_b" || true
    jq -r "$filter" "$original" 2>/dev/null | sort > "$tmp_o" || true

    printf '\n=== %s ===\n' "$label"
    if ! diff "$tmp_b" "$tmp_o" >/dev/null 2>&1; then
      diff "$tmp_b" "$tmp_o" 2>/dev/null || true
    else
      printf '  (igual)\n'
    fi
  }

  _diff_hashed_section() {
    local label=$1 jqfilter=$2
    printf '\n=== %s ===\n' "$label"

    local b_sha o_sha
    b_sha=$(jq -S -c "$jqfilter" "$backup" 2>/dev/null | sha256sum | cut -b1-8 || echo "---")
    o_sha=$(jq -S -c "$jqfilter" "$original" 2>/dev/null | sha256sum | cut -b1-8 || echo "---")

    if [[ "$b_sha" != "$o_sha" ]]; then
      printf '  HASH: %s → %s\n' "$b_sha" "$o_sha"
      local b_keys o_keys
      b_keys=$(jq -r "$jqfilter | keys | sort[]" "$backup" 2>/dev/null | tr '\n' ' ' || echo "N/A")
      o_keys=$(jq -r "$jqfilter | keys | sort[]" "$original" 2>/dev/null | tr '\n' ' ' || echo "N/A")
      [[ "$b_keys" != "$o_keys" ]] && printf '  KEYS: %s → %s\n' "$b_keys" "$o_keys"
    else
      printf '  (igual)\n'
    fi
  }

  printf '=== top-level keys ===\n'
  _diff_section "top-level keys" 'keys | sort[]'

  printf '\n=== plugin ===\n'
  _diff_section "plugin entries" '.plugin // [] | .[]'

  printf '\n=== mcp server keys ===\n'
  _diff_hashed_section "mcp servers" '.mcp'

  printf '\n=== agent ===\n'
  _diff_hashed_section "agents" '.agent'

  printf '\n=== default_agent ===\n'
  local b_def o_def
  b_def=$(jq -r '.default_agent // "ausente"' "$backup" 2>/dev/null)
  o_def=$(jq -r '.default_agent // "ausente"' "$original" 2>/dev/null)
  if [[ "$b_def" != "$o_def" ]]; then
    printf '  %s → %s\n' "$b_def" "$o_def"
  else
    printf '  %s (igual)\n' "$b_def"
  fi

  printf '\n=== permission ===\n'
  _diff_hashed_section "permissions" '.permission'

  printf '\n=== provider ===\n'
  _diff_hashed_section "providers" '.provider'

  printf '\n=== model ===\n'
  _diff_hashed_section "models" '.model'

  printf '\n=== claves desconocidas ===\n'
  local known='$schema shell logLevel server command skills references reference watcher snapshot plugin share autoshare autoupdate disabled_providers enabled_providers model small_model default_agent subagent_depth username mode agent provider mcp formatter lsp instructions layout permission tools attachment enterprise tool_output compaction experimental'
  local tmp_b_extra tmp_o_extra
  tmp_b_extra=$(mktemp) && tmp_o_extra=$(mktemp)
  trap 'rm -f "$tmp_b_extra" "$tmp_o_extra"' RETURN

  jq -r 'keys | .[] | select(. as $k | "'"$known"'" | contains($k) | not)' "$backup" 2>/dev/null | sort > "$tmp_b_extra" || true
  jq -r 'keys | .[] | select(. as $k | "'"$known"'" | contains($k) | not)' "$original" 2>/dev/null | sort > "$tmp_o_extra" || true
  if ! diff "$tmp_b_extra" "$tmp_o_extra" >/dev/null 2>&1; then
    diff "$tmp_b_extra" "$tmp_o_extra" 2>/dev/null || true
  else
    printf '  (igual)\n'
  fi
}

export -f opencode_backup_create opencode_backup_list opencode_backup_restore opencode_backup_diff opencode_backup_find_all
