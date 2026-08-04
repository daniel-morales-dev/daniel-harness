#!/usr/bin/env bash
# tests/clean-runtime.test.sh
# Verifica que bootstrap instala python3-jsonschema en entorno limpio
set -euo pipefail
umask 077

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR" /tmp/daniel-harness-apt-get.args' EXIT

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

cat > "$STUBS/apt-get" <<'APTSCRIPT'
#!/bin/bash
echo "$@" >> /tmp/daniel-harness-apt-get.args
if [[ "$1" == "update" ]]; then exit 0; fi
if [[ "$1" == "install" && "$2" == "-y" ]]; then
  shift 2
  for pkg in "$@"; do
    if [[ "$pkg" == "python3-jsonschema" ]]; then
      pip install jsonschema 2>/dev/null
    fi
  done
fi
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

cat > "$STUBS/curl" <<'CURLSCRIPT'
#!/bin/bash
# Handle -o <file>: write installer script to target file
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) outfile="$2"; shift 2 ;;
    -fsSL|--fail|--silent|--show-error|--location) shift ;;
    http*|https*) shift ;;
    *) shift ;;
  esac
done
if [[ -n "${outfile:-}" ]]; then
  cat > "$outfile" <<'NVMSCRIPT'
#!/bin/bash
NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
mkdir -p "$NVM_DIR"
cat > "$NVM_DIR/nvm.sh" <<'NVMEOF'
nvm() {
  case "$1" in
    --version) echo "0.40.4" ;;
    install) mkdir -p "$NVM_DIR/versions/node/v24.0.0/bin"
             cat > "$NVM_DIR/versions/node/v24.0.0/bin/node" <<'NODEEOF'
#!/bin/bash
echo "v24.0.0"
NODEEOF
      chmod +x "$NVM_DIR/versions/node/v24.0.0/bin/node" ;;
    alias) ;;
    *) ;;
  esac
}
NVMEOF
chmod +x "$NVM_DIR/nvm.sh"
NVMSCRIPT
fi
CURLSCRIPT
chmod +x "$STUBS/curl"

for tool in node npm opencode codegraph rtk engram gentle-ai dh; do
  cat > "$STUBS/$tool" <<'TOOLSCRIPT'
#!/bin/bash
exit 0
TOOLSCRIPT
  chmod +x "$STUBS/$tool"
done

cat > "$STUBS/opencode" <<'OPENCODE'
#!/bin/bash
if [[ "$1" == "mcp" && "$2" == "debug" ]]; then echo "connected"; exit 0; fi
exit 0
OPENCODE
chmod +x "$STUBS/opencode"

cat > "$STUBS/gentle-ai" <<'GENTLE'
#!/bin/bash
case "$1" in
  version) echo "gentle-ai 9.9.9 (stub)" ;;
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

grep -q 'python3-jsonschema' /tmp/daniel-harness-apt-get.args 2>/dev/null && \
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
