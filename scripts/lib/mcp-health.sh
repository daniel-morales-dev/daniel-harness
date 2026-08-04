#!/usr/bin/env bash
# Funciones compartidas para diagnóstico de estado MCP
# Usada por: doctor.sh, tests/doctor-mcp-status.test.sh

classify_mcp_debug_output() {
  local output=$1
  if echo "$output" | grep -qiE '(authentication required|auth-required|auth.*failed|missing credentials|401 unauthorized|auth.*required)'; then
    echo "auth-required"
  elif echo "$output" | grep -qiE '^connected$|^healthy$'; then
    echo "connected"
  elif echo "$output" | grep -qiE '(not connected|not.*found|connection refused|broken pipe|error|failed)'; then
    echo "inaccesible"
  elif [[ -z "$output" ]]; then
    echo "desconocido"
  else
    echo "inaccesible"
  fi
}
