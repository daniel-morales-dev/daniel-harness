#!/usr/bin/env bash
set -euo pipefail
umask 077

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

OUTPUT="$TMP_DIR/bootstrap.out"

# Verificar sintaxis
bash -n "$ROOT_DIR/scripts/bootstrap.sh"

# Verificar que el manifest existe y es legible
[[ -f "$ROOT_DIR/bootstrap/manifest.yaml" ]]
grep -q 'version: "1"' "$ROOT_DIR/bootstrap/manifest.yaml"
grep -q 'ubuntu-24.04' "$ROOT_DIR/bootstrap/manifest.yaml"

# Dry-run debe completar sin errores (no importa qué herramientas estén instaladas)
bash "$ROOT_DIR/scripts/bootstrap.sh" --dry-run >"$OUTPUT" 2>&1 || {
  printf 'Dry-run falló. Salida:\n' >&2
  cat "$OUTPUT" >&2
  exit 1
}
grep -F 'Bootstrap completado' "$OUTPUT" >/dev/null

# Verificar que MCPs se listan (codegraph local presente, remotos sin URL excluidos)
grep -F 'MCP codegraph' "$OUTPUT" >/dev/null
grep -i 'remotos sin URL' "$OUTPUT" >/dev/null

# Verificar que no hay errores de parseo (ignorar líneas con info/skip)
if grep -i 'error' "$OUTPUT" | grep -v 'simulado' | grep -v 'incompatible' >/dev/null; then
  printf 'Se encontraron errores en la salida del dry-run:\n' >&2
  grep -i 'error' "$OUTPUT" >&2
  exit 1
fi

printf 'bootstrap tests passed\n'
