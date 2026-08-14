#!/usr/bin/env bash
# tests/clean-runtime.test.sh
# Verifica que bootstrap instala python3-jsonschema en entorno limpio
set -euo pipefail
umask 077

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT_DIR/tests/helpers/nvm-stub.sh"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

PASS=0; FAIL=0
pass() { printf '  [ok] %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf '  [FAIL] %s\n' "$*"; FAIL=$((FAIL + 1)); }

echo "=== Fase 1: Verificacion estatica del manifest ==="
if grep -qE '^\s+- python3-jsonschema\s*$' "$ROOT_DIR/bootstrap/manifest.yaml"; then
  pass "python3-jsonschema en manifest system_packages.required"
else
  fail "python3-jsonschema NO esta en system_packages.required"
fi

echo "=== Fase 2: bootstrap con stubs de entorno limpio ==="
HOME_DIR="$TMP_DIR/home"
STUBS="$TMP_DIR/stubs"
mkdir -p "$HOME_DIR/.config/daniel-harness/secrets/tunnels" "$HOME_DIR/.nvm" "$STUBS"

cat > "$STUBS/sudo" <<'EOF'
#!/bin/bash
if [[ "$1" == "-n" && "$2" == "true" ]]; then exit 0; fi
if [[ "$1" == "-v" ]]; then exit 0; fi
exec "$@"
EOF
chmod +x "$STUBS/sudo"

APT_LOG="$TMP_DIR/apt-get.args"
export APT_LOG
cat > "$STUBS/apt-get" <<APTSCRIPT
#!/bin/bash
printf '%s\n' "\$*" >> "\$APT_LOG"
exit 0
APTSCRIPT
chmod +x "$STUBS/apt-get"

cat > "$STUBS/dpkg" <<'DPKGSCRIPT'
#!/bin/bash
if [[ "$1" == "-s" ]]; then
  if [[ "$2" == "python3-jsonschema" ]]; then
    echo "dpkg-query: package '$2' is not installed and no information is available"
    exit 1
  fi
  echo "Status: install ok installed"
  exit 0
fi
exit 0
DPKGSCRIPT
chmod +x "$STUBS/dpkg"

create_nvm_curl_stub "$STUBS"

for tool in node npm opencode codegraph rtk engram gentle-ai dh; do
  cat > "$STUBS/$tool" <<'TOOLSCRIPT'
#!/bin/bash
exit 0
TOOLSCRIPT
  chmod +x "$STUBS/$tool"
done

cat > "$STUBS/opencode" <<'OPENCODE'
#!/bin/bash
case "$1:${2:-}:${3:-}" in
  --version::) echo "opencode 1.18.18"; exit 0 ;;
  agent:list:--help|mcp:--help:|mcp:debug:--help|mcp:auth:--help|debug:config:--help) exit 0 ;;
  agent:list:*) echo "alegra-microservice-engineer alegra-code-reviewer alegra-microservice-test-engineer php-engineer migration-parity-reviewer"; exit 0 ;;
  mcp:debug:*) echo "connected"; exit 0 ;;
esac
exit 0
OPENCODE
chmod +x "$STUBS/opencode"

cat > "$STUBS/gentle-ai" <<'GENTLE'
#!/bin/bash
case "$1" in
  --version|version) echo "gentle-ai 2.3.0" ;;
  doctor) echo "Status:  healthy" ;;
  review) if [[ "$2" == "mode" ]]; then echo "receipt-driven development: on (decided by default)"; fi ;;
  skill-registry) mkdir -p "$ROOT_DIR/.atl" 2>/dev/null; touch "$ROOT_DIR/.atl/skill-registry.md" 2>/dev/null; echo "ok" ;;
  sync) echo "ok" ;;
esac
exit 0
GENTLE
chmod +x "$STUBS/gentle-ai"

# Config fixture sin restricted models (doctor.sh flagia agents con bash
# sin wildcard deny cuando hay modelos restricted)
python3 -c "
import yaml
from pathlib import Path
cfg = yaml.safe_load((Path('$ROOT_DIR/examples/config.example.yaml')).read_text())
cfg['models'] = [m for m in cfg['models'] if m.get('trust') != 'restricted']
Path('$HOME_DIR/.config/daniel-harness/config.yaml').write_text(yaml.dump(cfg))
"

export PATH="$STUBS:$PATH"
export HOME="$HOME_DIR"
export XDG_CONFIG_HOME="$HOME_DIR/.config"
export NVM_DIR="$HOME_DIR/.nvm"
export DH_TEST_MODE=1
export DH_TRANSACTION_ALLOW_TMP=1

echo "=== Fase 2a: bootstrap --profile core ==="
if bash "$ROOT_DIR/scripts/bootstrap.sh" --profile core > "$TMP_DIR/bootstrap.out" 2>&1; then
  pass "bootstrap core exit code 0"
else
  fail "bootstrap core fallo"
  cat "$TMP_DIR/bootstrap.out"
fi

grep -q 'Bootstrap completado y saludable' "$TMP_DIR/bootstrap.out" && \
  pass "bootstrap completado y saludable" || \
  fail "bootstrap no reporto saludable"

OC_FILE="$HOME_DIR/.config/opencode/opencode.json"
if [[ -f "$OC_FILE" ]]; then
  pass "opencode.json creado"
  jq empty "$OC_FILE" && pass "opencode.json es JSON valido" || fail "opencode.json no es JSON valido"
else
  fail "opencode.json no fue creado"
fi

grep -q 'python3-jsonschema' "$APT_LOG" 2>/dev/null && \
  pass "bootstrap solicito python3-jsonschema via apt-get" || \
  fail "bootstrap no solicito python3-jsonschema"

echo "=== Fase 3: validator directo ==="
if python3 "$ROOT_DIR/scripts/validate-opencode-config.py" \
  --config "$OC_FILE" \
  --schema "$ROOT_DIR/tests/fixtures/opencode-config.schema.json" > "$TMP_DIR/validate.out" 2>&1; then
  pass "validator exit code 0"
else
  fail "validator exit code != 0"
fi
grep -q '\[ok\] Schema válido' "$TMP_DIR/validate.out" && \
  pass "Schema válido" || \
  fail "Schema válido no encontrado"
grep -q 'jsonschema no instalado' "$TMP_DIR/validate.out" && \
  fail "jsonschema no instalado" || \
  pass "No hay error de jsonschema"

echo ""
echo "=== Resultados: $PASS pasaron, $FAIL fallaron ==="
(( FAIL == 0 ))
