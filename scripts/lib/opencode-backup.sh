# scripts/lib/opencode-backup.sh
# Backup/restore system for opencode.json — sourced, not executed
set -euo pipefail

opencode_backup_create() {
  local source=${1:?source path required}
  local config_dir=${2:?HARNESS_CONFIG_DIR required}

  [[ -f "$source" ]] || { printf 'no source\n' >&2; exit 1; }
  jq empty "$source" 2>/dev/null || { printf 'invalid\n' >&2; exit 1; }

  local backup_dir="$config_dir/backups"
  mkdir -p "$backup_dir"
  chmod 700 "$backup_dir"

  local sum prefix ts filename
  sum=$(sha256sum "$source" | cut -d' ' -f1)
  prefix=${sum:0:8}
  ts=$(date +%Y%m%d-%H%M%S)
  filename="opencode-${ts}-${prefix}.json"
  local dest="$backup_dir/$filename"

  cp "$source" "$dest"
  chmod 600 "$dest"

  local dest_sum
  dest_sum=$(sha256sum "$dest" | cut -d' ' -f1)
  [[ "$sum" == "$dest_sum" ]] || { rm -f "$dest"; printf 'checksum mismatch\n' >&2; exit 1; }

  printf '%s\n' "$dest"
}

opencode_backup_list() {
  local config_dir=${1:?HARNESS_CONFIG_DIR required}
  local backup_dir="$config_dir/backups"
  local files=()

  if [[ -d "$backup_dir" ]]; then
    while IFS= read -r -d '' f; do
      files+=("$f")
    done < <(find "$backup_dir" -maxdepth 1 -name 'opencode-*.json' -print0 2>/dev/null | sort -z)
  fi

  if [[ ${#files[@]} -eq 0 ]]; then
    printf 'No hay backups.\n'
    return 0
  fi

  printf '  #  Backup                               Fecha         Tamaño  SHA256\n'
  local i=1 f name date size sum
  for f in "${files[@]}"; do
    name=$(basename "$f")
    date=$(stat -c '%y' "$f" 2>/dev/null | cut -d' ' -f1 || echo '-')
    size=$(numfmt --to=iec 2>/dev/null < <(stat -c '%s' "$f" 2>/dev/null) || stat -c '%s' "$f" 2>/dev/null || echo '?')
    sum=$(sha256sum "$f" 2>/dev/null | cut -b1-8 || echo '--------')
    printf '%3d  %-38s  %-10s  %5s  %s\n' "$i" "$name" "$date" "$size" "$sum"
    i=$((i + 1))
  done
}

opencode_backup_restore() {
  local input=${1:?backup path or ID required}
  local target=${2:?target path required}
  local config_dir=${3:?HARNESS_CONFIG_DIR required}
  local backup_dir="$config_dir/backups"
  local backup=""

  if [[ -f "$input" ]]; then
    backup="$input"
  else
    [[ -d "$backup_dir" ]] || { printf 'no backup dir\n' >&2; return 1; }
    local matches=()
    while IFS= read -r -d '' f; do
      matches+=("$f")
    done < <(find "$backup_dir" -maxdepth 1 -name "opencode-${input}*.json" -print0 2>/dev/null)
    [[ ${#matches[@]} -eq 1 ]] || { printf 'ambiguous or not found\n' >&2; return 1; }
    backup="${matches[0]}"
  fi

  [[ -f "$backup" ]] || { printf 'backup not found\n' >&2; return 1; }
  jq empty "$backup" 2>/dev/null || { printf 'backup corrupted\n' >&2; return 1; }

  if [[ -f "$target" ]]; then
    opencode_backup_create "$target" "$config_dir" >/dev/null || true
  fi

  cp "$backup" "$target"
  chmod 600 "$target"
  printf 'restaurado: %s\n' "$target"
}

opencode_backup_diff() {
  local backup=${1:?backup path required}
  local original=${2:?original path required}

  for f in "$backup" "$original"; do
    jq empty "$f" 2>/dev/null || { printf 'invalid JSON: %s\n' "$f" >&2; return 1; }
  done

  printf '=== top-level keys ===\n'
  diff <(jq -r 'keys | sort[]' "$backup") <(jq -r 'keys | sort[]' "$original") \
    && printf '  (igual)\n' \
    || true

  printf '\n=== mcp server keys ===\n'
  if jq -e '.mcp' "$backup" >/dev/null 2>&1 && jq -e '.mcp' "$original" >/dev/null 2>&1; then
    diff <(jq -r '.mcp | keys | sort[]' "$backup") <(jq -r '.mcp | keys | sort[]' "$original") \
      && printf '  (igual)\n' \
      || true
  else
    printf '  (mcp ausente en uno o ambos)\n'
  fi

  printf '\n=== plugins ===\n'
  if jq -e '.plugins' "$backup" >/dev/null 2>&1 && jq -e '.plugins' "$original" >/dev/null 2>&1; then
    diff <(jq -r '.plugins | sort[]' "$backup") <(jq -r '.plugins | sort[]' "$original") \
      && printf '  (igual)\n' \
      || true
  else
    printf '  (plugins ausente en uno o ambos)\n'
  fi
}

export -f opencode_backup_create opencode_backup_list opencode_backup_restore opencode_backup_diff
