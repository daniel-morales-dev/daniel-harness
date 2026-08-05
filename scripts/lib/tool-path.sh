#!/usr/bin/env bash
# scripts/lib/tool-path.sh
# Funcion compartida: asegura que un binario sea visible en LOCAL_BIN/PATH
# Dependencias: LOCAL_BIN debe estar definida, DRY_RUN opcional
# Usada por: bootstrap.sh, tests/tool-path-exposure.test.sh

type -t critical >/dev/null 2>&1 || critical() { printf '  [critico] %s\n' "$*"; }

_ensure_tool_visible() {
  if [[ ${DRY_RUN:-false} == true ]]; then
    return 0
  fi
  local name=$1; shift

  if command -v "$name" >/dev/null 2>&1; then
    local current_path
    current_path=$(command -v "$name")
    [[ "$current_path" == "$LOCAL_BIN/$name" ]] && return 0
    if [[ ! -e "$LOCAL_BIN/$name" ]]; then
      ln -s "$current_path" "$LOCAL_BIN/$name" 2>/dev/null || true
    fi
    command -v "$name" >/dev/null 2>&1 && return 0
  fi

  local candidate
  for candidate in "$@"; do
    [[ -x "$candidate" ]] || continue
    if [[ -e "$LOCAL_BIN/$name" ]]; then
      command -v "$name" >/dev/null 2>&1 && return 0
      continue
    fi
    ln -s "$candidate" "$LOCAL_BIN/$name" 2>/dev/null || continue
    if command -v "$name" >/dev/null 2>&1; then
      return 0
    fi
    rm -f "$LOCAL_BIN/$name"
  done
  critical "$name no encontrado en PATH tras la instalacion"
  return 1
}
