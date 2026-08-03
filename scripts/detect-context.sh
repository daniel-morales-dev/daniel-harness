#!/usr/bin/env bash
# Detecta el contexto del proyecto activo. Sin dependencias externas.
# Útil para que agentes carguen las reglas correctas automáticamente.
# Salida: pares clave=valor (proyecto, contexto, path, detectado_por)

set -euo pipefail

PROJECT_DIR="${1:-$PWD}"
CONFIG_ROOT=${XDG_CONFIG_HOME:-"$HOME/.config"}
HARNESS_CONFIG_DIR=${DANIEL_HARNESS_CONFIG_DIR:-"$CONFIG_ROOT/daniel-harness"}
REGISTRY="$HARNESS_CONFIG_DIR/project-registry.yaml"

# 1. Buscar en project-registry.yaml
if [[ -f "$REGISTRY" ]]; then
  while IFS='|' read -r name ctx path; do
    normalized_dir=$(realpath "$PROJECT_DIR" 2>/dev/null || echo "$PROJECT_DIR")
    normalized_path=$(realpath "$path" 2>/dev/null || echo "$path")
    if [[ "$normalized_dir" == "$normalized_path" ||
          "$normalized_dir" == "$normalized_path/"* ]]; then
      echo "proyecto=$name"
      echo "contexto=$ctx"
      echo "path=$path"
      echo "detectado_por=project-registry"
      exit 0
    fi
  done < <(awk '
    /^families:/ { in_families=1; next }
    in_families && /^    projects:/ { in_proj=1; next }
    in_proj && /^      - id:/ { gsub(/^      - id:[[:space:]]*/, ""); gsub(/^"|"$/, ""); name=$0; next }
    in_proj && /^        path:/ { gsub(/^        path:[[:space:]]*/, ""); gsub(/^"|"$/, ""); path=$0; next }
    in_proj && /^        context:/ {
      gsub(/^        context:[[:space:]]*/, ""); gsub(/^"|"$/, ""); ctx=$0
      if (name && path && ctx) print name "|" ctx "|" path
      name=""; path=""; ctx=""; next
    }
    in_families && /^  - / { in_proj=0 }
    /^[a-z]/ && $0 != "families:" { in_families=0; in_proj=0 }
  ' "$REGISTRY")
fi

# 2. Heurística por lenguaje (NUNCA asigna Alegra — solo registry explícito)
if [[ -f "$PROJECT_DIR/composer.json" ]]; then
  echo "contexto=generic-php"
  echo "detectado_por=composer.json"
elif [[ -f "$PROJECT_DIR/package.json" ]]; then
  if command -v jq >/dev/null 2>&1 && jq -e '.devDependencies.typescript // "" | length > 0' "$PROJECT_DIR/package.json" >/dev/null 2>&1; then
    echo "contexto=generic-typescript"
    echo "detectado_por=package.json+typescript"
  else
    echo "contexto=generic-node"
    echo "detectado_por=package.json"
  fi
elif [[ -f "$PROJECT_DIR/go.mod" ]]; then
  echo "contexto=generic-go"
  echo "detectado_por=go.mod"
else
  echo "contexto=generic"
  echo "detectado_por=default"
fi
