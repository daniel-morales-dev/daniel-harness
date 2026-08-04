#!/usr/bin/env bash
# tests/drift-three-run.test.sh
# P0: Verifica que la personalizacion de MCPs se preserve indefinidamente
set -euo pipefail
umask 077

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT_DIR/tests/helpers/nvm-stub.sh"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

PASS=0; FAIL=0
pass() { printf '  [ok] %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf '  [FAIL] %s\n' "$*"; FAIL=$((FAIL + 1)); }

HOME_DIR="$TMP_DIR/home"
STUBS="$TMP_DIR/stubs"
mkdir -p "$HOME_DIR/.config/daniel-harness/secrets/tunnels" "$HOME_DIR/.nvm" "$STUBS"

for stub in sudo apt-get dpkg curl node npm; do
  cat > "$STUBS/$stub" <<'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$STUBS/$stub"
done

cat > "$STUBS/sudo" <<'EOF'
#!/bin/bash
if [[ "$1" == "-n" && "$2" == "true" ]]; then exit 0; fi
if [[ "$1" == "-v" ]]; then exit 0; fi
exec "$@"
EOF
chmod +x "$STUBS/sudo"

create_nvm_curl_stub "$STUBS"

for tool in node npm opencode codegraph rtk engram gentle-ai dh; do
  cat > "$STUBS/$tool" <<'EOF'
#!/bin/bash
exit 0
EOF
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
  review) if [[ "$2" == "mode" ]]; then echo "receipt-driven development: on"; fi ;;
  skill-registry) mkdir -p "$ROOT_DIR/.atl" 2>/dev/null; touch "$ROOT_DIR/.atl/skill-registry.md" 2>/dev/null; echo "ok" ;;
  sync) echo "ok" ;;
esac
exit 0
GENTLE
chmod +x "$STUBS/gentle-ai"

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

OC_FILE="$HOME_DIR/.config/opencode/opencode.json"
STATE_FILE="$HOME_DIR/.config/daniel-harness/state/opencode-managed.json"

# Helper: run bootstrap, ignore exit (doctor criticals unrelated to drift)
run_bootstrap() {
  local label=$1 out=$2
  set +e
  bash "$ROOT_DIR/scripts/bootstrap.sh" --profile alegra > "$out" 2>&1
  set -e
  # Return 0 if MCP section ran (opencode.json updated or drift detected)
  grep -q 'Servidores MCP\|MCP' "$out"
}

echo "=== Run 1: bootstrap alegra ==="
run_bootstrap "run1" "$TMP_DIR/run1.out" && pass "run1: MCP section executed" || fail "run1: MCP section failed"
[[ -f "$OC_FILE" ]] && pass "run1: opencode.json created" || fail "run1: opencode.json missing"
[[ -f "$STATE_FILE" ]] && pass "run1: state file created" || fail "run1: state file missing"

GH_HASH_RUN1=$(jq -r '.mcps.github.lastAppliedHash // "none"' "$STATE_FILE" 2>/dev/null || echo "none")
pass "run1: github hash=$GH_HASH_RUN1"

echo "=== Run 2: modificar github manualmente y re-bootstrap ==="
jq '.mcp.github.url = "https://custom.github.com/mcp"' "$OC_FILE" > "$TMP_DIR/oc-tmp.json" && mv "$TMP_DIR/oc-tmp.json" "$OC_FILE"
pass "github MCP personalizado"

run_bootstrap "run2" "$TMP_DIR/run2.out" && pass "run2: MCP section executed" || fail "run2: MCP section failed"

GH_URL=$(jq -r '.mcp.github.url // "missing"' "$OC_FILE")
[[ "$GH_URL" == "https://custom.github.com/mcp" ]] && pass "run2: github URL preservada" || fail "run2: github URL sobreescrita: $GH_URL"

GH_HASH_RUN2=$(jq -r '.mcps.github.lastAppliedHash // "none"' "$STATE_FILE" 2>/dev/null || echo "none")
[[ "$GH_HASH_RUN2" == "$GH_HASH_RUN1" ]] && pass "run2: github hash NO se actualizo" || fail "run2: github hash CAMBIO"

LIN_URL=$(jq -r '.mcp.linear.url // "missing"' "$OC_FILE")
[[ "$LIN_URL" == "https://mcp.linear.app/mcp" ]] && pass "run2: linear URL correcta" || fail "run2: linear URL incorrecta: $LIN_URL"

echo "=== Run 3: tercer bootstrap ==="
run_bootstrap "run3" "$TMP_DIR/run3.out" && pass "run3: MCP section executed" || fail "run3: MCP section failed"

GH_URL_RUN3=$(jq -r '.mcp.github.url // "missing"' "$OC_FILE")
[[ "$GH_URL_RUN3" == "https://custom.github.com/mcp" ]] && pass "run3: github URL preservada" || fail "run3: github URL sobreescrita: $GH_URL_RUN3"

GH_HASH_RUN3=$(jq -r '.mcps.github.lastAppliedHash // "none"' "$STATE_FILE" 2>/dev/null || echo "none")
[[ "$GH_HASH_RUN3" == "$GH_HASH_RUN1" ]] && pass "run3: github hash NO se actualizo" || fail "run3: github hash CAMBIO"

LIN_URL_RUN3=$(jq -r '.mcp.linear.url // "missing"' "$OC_FILE")
[[ "$LIN_URL_RUN3" == "https://mcp.linear.app/mcp" ]] && pass "run3: linear URL correcta" || fail "run3: linear URL incorrecta"

echo ""
echo "=== Resultados: $PASS pasaron, $FAIL fallaron ==="
(( FAIL == 0 ))
