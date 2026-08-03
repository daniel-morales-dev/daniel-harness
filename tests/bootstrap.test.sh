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

# Dry-run debe completar sin errores
bash "$ROOT_DIR/scripts/bootstrap.sh" --dry-run >"$OUTPUT"
grep -F 'Bootstrap completado' "$OUTPUT" >/dev/null

# Verificar que detecta herramientas ya instaladas
grep -F 'OpenCode ya instalado' "$OUTPUT" >/dev/null
grep -F 'NVM ya instalado' "$OUTPUT" >/dev/null
grep -F 'Node.js 24 activo' "$OUTPUT" >/dev/null

# Verificar que MCPs se listan correctamente
grep -F 'MCP codegraph' "$OUTPUT" >/dev/null
grep -F 'MCP github' "$OUTPUT" >/dev/null
grep -F 'MCP excluido' "$OUTPUT" >/dev/null

# Verificar que OAuth se lista en próximos pasos
grep -F 'opencode mcp auth github' "$OUTPUT" >/dev/null
grep -F 'opencode mcp auth linear' "$OUTPUT" >/dev/null

# Verificar que no hay errores de parseo
if grep -i 'error' "$OUTPUT" | grep -v 'simulado' | grep -v 'incompatible' >/dev/null; then
  printf 'Se encontraron errores en la salida del dry-run:\n' >&2
  grep -i 'error' "$OUTPUT" >&2
  exit 1
fi

printf 'bootstrap tests passed\n'
