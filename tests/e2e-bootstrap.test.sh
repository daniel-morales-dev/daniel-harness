#!/usr/bin/env bash
# E2E: bootstrap real con stubs en HOME aislado
set -euo pipefail
umask 077

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

HOME_TMP="$TMP_DIR/home"
CONFIG_TMP="$TMP_DIR/config"
STUBS="$TMP_DIR/stubs"
OC_FILE="$CONFIG_TMP/opencode/opencode.json"
PASS=0
FAIL=0

pass() { printf '  [ok] %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf '  [FAIL] %s\n' "$*"; FAIL=$((FAIL + 1)); }

# Helper: run command, capture exit code
run_check() {
  local label=$1; shift
  set +e
  "$@" > "$TMP_DIR/${label// /_}.out" 2>&1; local rc=$?
  set -e
  printf '%s' "$rc"
}

# --- Setup: stubs and fake HOME ---
printf '=== Setup: stubs ===\n'
mkdir -p "$STUBS" "$HOME_TMP" "$HOME_TMP/.nvm" "$CONFIG_TMP"

# Stub sudo
cat > "$STUBS/sudo" <<'SUDO'
#!/bin/bash
if [[ "$1" == "-n" && "$2" == "true" ]]; then exit 0; fi
if [[ "$1" == "-v" ]]; then exit 0; fi
exec "$@"
SUDO
chmod +x "$STUBS/sudo"

cat > "$STUBS/apt-get" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$STUBS/apt-get"

cat > "$STUBS/dpkg" <<'EOF'
#!/bin/bash
if [[ "$1" == "-s" ]]; then echo "Status: install ok installed"; exit 0; fi
exit 0
EOF
chmod +x "$STUBS/dpkg"

cat > "$STUBS/curl" <<'EOF'
#!/bin/bash
cat <<'NVMSCRIPT'
#!/bin/bash
NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
mkdir -p "$NVM_DIR"
cat > "$NVM_DIR/nvm.sh" <<'NVMEOF'
nvm() { case "$1" in --version) echo "0.40.4" ;; install) mkdir -p "$NVM_DIR/versions/node/v24.0.0/bin"
cat > "$NVM_DIR/versions/node/v24.0.0/bin/node" <<'NODEEOF'
#!/bin/bash
echo "v24.0.0"
NODEEOF
chmod +x "$NVM_DIR/versions/node/v24.0.0/bin/node" ;;
alias) ;; *) ;; esac; }
NVMEOF
chmod +x "$NVM_DIR/nvm.sh"
NVMSCRIPT
EOF
chmod +x "$STUBS/curl"

cat > "$STUBS/node" <<'NODE'
#!/bin/bash
echo "v24.0.0"; exit 0
NODE
chmod +x "$STUBS/node"

cat > "$STUBS/npm" <<'NPM'
#!/bin/bash
exit 0
NPM
chmod +x "$STUBS/npm"

cat > "$STUBS/opencode" <<'OPENCODE'
#!/bin/bash
if [[ "$1" == "mcp" && "$2" == "debug" ]]; then echo "connected"; exit 0; fi
exit 0
OPENCODE
chmod +x "$STUBS/opencode"

cat > "$STUBS/gentle-ai" <<GENTLE
#!/bin/bash
case "\$1" in
  version) echo "gentle-ai 9.9.9 (stub)" ;;
  doctor) echo "Status:  healthy" ;;
  review) if [[ "\$2" == "mode" ]]; then echo "receipt-driven development: on (decided by default)"; fi ;;
  skill-registry) mkdir -p "$ROOT_DIR/.atl" 2>/dev/null; touch "$ROOT_DIR/.atl/skill-registry.md" 2>/dev/null; echo "ok" ;;
  sync) echo "ok" ;;
esac
exit 0
GENTLE
chmod +x "$STUBS/gentle-ai"

for tool in codegraph rtk engram; do
  cat > "$STUBS/$tool" <<EOF
#!/bin/bash
exit 0
EOF
  chmod +x "$STUBS/$tool"
done

cat > "$STUBS/dh" <<'DH'
#!/bin/bash
echo "dh stub"; exit 0
DH
chmod +x "$STUBS/dh"

mkdir -p "$CONFIG_TMP/daniel-harness/secrets/tunnels"
for tunnel in alegra-hopper alegra-production k-agencia-mysql k-agencia-mongodb k-agencia-garage; do
  printf 'echo %s tunnel stub\n' "$tunnel" > "$CONFIG_TMP/daniel-harness/secrets/tunnels/$tunnel.command"
  chmod 600 "$CONFIG_TMP/daniel-harness/secrets/tunnels/$tunnel.command"
done

cat > "$HOME_TMP/.nvm/nvm.sh" <<'NVMINIT'
nvm() { case "$1" in --version) echo "0.40.4" ;; install) ;; alias) ;; *) ;; esac; }
NVMINIT

cat > "$CONFIG_TMP/daniel-harness/config.yaml" <<'EOF'
version: "1"
trust: trusted
EOF

export PATH="$STUBS:$PATH"
export HOME="$HOME_TMP"
export XDG_CONFIG_HOME="$CONFIG_TMP"
export NVM_DIR="$HOME_TMP/.nvm"

# --- Phase 1: Bootstrap --profile core ---
printf '\n=== Phase 1: bootstrap --profile core ===\n'
rc=$(run_check "bootstrap-core" bash "$ROOT_DIR/scripts/bootstrap.sh" --profile core)
[[ $rc -eq 0 ]] && pass "bootstrap core exit code 0" || fail "bootstrap core exit code $rc"
grep -q 'Bootstrap completado y saludable' "$TMP_DIR/bootstrap-core.out" && pass "bootstrap core completed healthy" || {
  cat "$TMP_DIR/bootstrap-core.out"
  fail "bootstrap core not healthy"
}

# --- Phase 2: Validate opencode.json ---
printf '\n=== Phase 2: opencode.json validation ===\n'
jq empty "$OC_FILE" && pass "opencode.json is valid JSON" || fail "opencode.json is not valid JSON"
[[ $(jq 'has("mcp")' "$OC_FILE") == "true" ]] && pass "mcp section exists" || fail "mcp section missing"
[[ $(jq 'has("plugin")' "$OC_FILE") == "true" ]] && pass "plugin section exists" || fail "plugin section missing"
jq -e '.mcp | has("codegraph")' "$OC_FILE" >/dev/null && pass "MCP codegraph configured" || fail "MCP codegraph missing"
jq -e '.mcp | has("engram")' "$OC_FILE" >/dev/null && pass "MCP engram configured" || fail "MCP engram missing"
jq -e '.mcp | has("linear") | not' "$OC_FILE" >/dev/null && pass "MCP linear not in core" || fail "MCP linear should not be in core"
jq -e '[.mcp[] | has("disabledTools")] | any | not' "$OC_FILE" >/dev/null && pass "no MCP has disabledTools" || fail "some MCP still has disabledTools"
jq -e '.plugin | index("@dietrichgebert/ponytail@latest") != null' "$OC_FILE" >/dev/null && pass "Ponytail plugin registered" || fail "Ponytail plugin missing"
jq -e '.mcp.codegraph.type == "local"' "$OC_FILE" >/dev/null && pass "codegraph is local" || fail "codegraph type mismatch"
jq -e '.mcp.engram.type == "local"' "$OC_FILE" >/dev/null && pass "engram is local" || fail "engram type mismatch"

# --- Phase 3: Agents and skills ---
printf '\n=== Phase 3: Agents and skills ===\n'
for a in alegra-microservice-engineer code-reviewer alegra-microservice-test-engineer php-engineer migration-parity-reviewer; do
  [[ -L "$CONFIG_TMP/opencode/agents/$a.md" ]] && pass "agent $a" || fail "agent $a missing"
done
for s in monolith-to-micro-migration task-lifecycle; do
  [[ -d "$CONFIG_TMP/opencode/skills/$s" ]] && pass "skill $s" || fail "skill $s missing"
done
[[ -f "$CONFIG_TMP/opencode/commands/migration-gap-analysis.md" ]] && pass "command migration-gap-analysis" || fail "command migration-gap-analysis missing"
[[ -L "$HOME_TMP/.local/bin/dh" ]] && pass "dh CLI linked" || fail "dh CLI missing"

# --- Phase 4: Doctor --profile core --strict ---
printf '\n=== Phase 4: doctor --profile core --strict ===\n'
rc=$(run_check "doctor-core" bash "$ROOT_DIR/scripts/doctor.sh" --profile core --strict)
[[ $rc -eq 0 ]] && pass "doctor core exit code 0" || fail "doctor core exit code $rc"
grep -q 'Resumen: 0 crítico(s)' "$TMP_DIR/doctor-core.out" && pass "doctor --profile core --strict passed" || {
  cat "$TMP_DIR/doctor-core.out"
  fail "doctor reported criticals"
}

# --- Phase 5: Idempotence (second bootstrap) ---
printf '\n=== Phase 5: Idempotence ===\n'
FIRST_HASH=$(sha256sum "$CONFIG_TMP/daniel-harness/config.yaml" 2>/dev/null | cut -d' ' -f1 || echo none)
BACKUPS_BEFORE=$(find "$CONFIG_TMP/opencode/" -name 'opencode.json.bak.*' 2>/dev/null | wc -l)
rc=$(run_check "bootstrap-idempotent" bash "$ROOT_DIR/scripts/bootstrap.sh" --profile core)
[[ $rc -eq 0 ]] && pass "second bootstrap exit code 0" || fail "second bootstrap exit code $rc"
SECOND_HASH=$(sha256sum "$CONFIG_TMP/daniel-harness/config.yaml" 2>/dev/null | cut -d' ' -f1 || echo none)
[[ "$FIRST_HASH" == "$SECOND_HASH" ]] && pass "second bootstrap is idempotent (config unchanged)" || fail "second bootstrap modified config"
BACKUPS_AFTER=$(find "$CONFIG_TMP/opencode/" -name 'opencode.json.bak.*' 2>/dev/null | wc -l)
[[ "$BACKUPS_AFTER" -eq "$BACKUPS_BEFORE" ]] && pass "no new backups created on second run" || fail "second bootstrap created unnecessary backups"
grep -q 'Bootstrap completado y saludable' "$TMP_DIR/bootstrap-idempotent.out" && pass "second bootstrap healthy" || fail "second bootstrap failed"

# --- Phase 6: Profile manifest validation ---
printf '\n=== Phase 6: Profile manifest validation ===\n'
for profile in core alegra migration full; do
  awk -v p="$profile" '
    $0 ~ "^profiles:" { in_profiles=1; next }
    in_profiles && $0 ~ "^  " p ":" { found=1; exit }
  ' "$ROOT_DIR/bootstrap/manifest.yaml" && pass "profile $profile exists in manifest" || fail "profile $profile missing from manifest"
done

# --- Phase 7: Bootstrap --profile alegra ---
printf '\n=== Phase 7: bootstrap --profile alegra ===\n'
[[ -f "$CONFIG_TMP/daniel-harness/config.yaml" ]] && FIRST_HASH_ALEGRA=$(sha256sum "$CONFIG_TMP/daniel-harness/config.yaml" | cut -d' ' -f1)
rc=$(run_check "bootstrap-alegra" bash "$ROOT_DIR/scripts/bootstrap.sh" --profile alegra)
[[ $rc -eq 0 ]] && pass "bootstrap alegra exit code 0" || fail "bootstrap alegra exit code $rc"
grep -q 'Bootstrap completado y saludable' "$TMP_DIR/bootstrap-alegra.out" && pass "bootstrap alegra completed healthy" || {
  cat "$TMP_DIR/bootstrap-alegra.out"
  fail "bootstrap alegra not healthy"
}

# --- Phase 8: Bootstrap --profile migration --skip-docker ---
printf '\n=== Phase 8: bootstrap --profile migration --skip-docker ===\n'
rc=$(run_check "bootstrap-migration" bash "$ROOT_DIR/scripts/bootstrap.sh" --profile migration --skip-docker)
[[ $rc -eq 0 ]] && pass "bootstrap migration --skip-docker exit code 0" || fail "bootstrap migration --skip-docker exit code $rc"
grep -q 'Bootstrap completado y saludable' "$TMP_DIR/bootstrap-migration.out" && pass "bootstrap migration completed healthy" || {
  cat "$TMP_DIR/bootstrap-migration.out"
  fail "bootstrap migration not healthy"
}
grep -q 'Docker omitido' "$TMP_DIR/bootstrap-migration.out" && pass "migration --skip-docker respected" || fail "migration did not skip docker"

# --- Phase 9: Bootstrap --profile full ---
printf '\n=== Phase 9: bootstrap --profile full ===\n'
rc=$(run_check "bootstrap-full" bash "$ROOT_DIR/scripts/bootstrap.sh" --profile full)
[[ $rc -eq 0 ]] && pass "bootstrap full exit code 0" || fail "bootstrap full exit code $rc"
grep -q 'Bootstrap completado y saludable' "$TMP_DIR/bootstrap-full.out" && pass "bootstrap full completed healthy" || {
  cat "$TMP_DIR/bootstrap-full.out"
  fail "bootstrap full not healthy"
}

# --- Phase 10: Invalid JSON rollback ---
printf '\n=== Phase 10: Invalid JSON rollback ===\n'
printf 'INVALID JSON' > "$OC_FILE"
rc=$(run_check "bootstrap-rollback" bash "$ROOT_DIR/scripts/bootstrap.sh" --profile core)
[[ $rc -eq 1 ]] && pass "bootstrap with invalid JSON exits code 1" || fail "bootstrap with invalid JSON exit code $rc (expected 1)"

# Backup should have been created
BACKUPS=$(find "$CONFIG_TMP/opencode/" -name 'opencode.json.bak.*' 2>/dev/null | wc -l)
[[ $BACKUPS -ge 1 ]] && pass "backup created for invalid JSON" || fail "no backup for invalid JSON"

# --- Phase 11: Doctor live check (auth-required) ---
printf '\n=== Phase 11: Doctor MCP live check ===\n'
# Restore valid opencode.json first (Phase 10 left it corrupt)
rm -f "$OC_FILE"
bash "$ROOT_DIR/scripts/bootstrap.sh" --profile core > "$TMP_DIR/restore.out" 2>&1 || true
jq empty "$OC_FILE" >/dev/null 2>&1 || {
  fail "cannot restore opencode.json for live check"
  echo "---restore output---"
  cat "$TMP_DIR/restore.out"
}
cat > "$STUBS/opencode" <<'OPENCODE'
#!/bin/bash
if [[ "$1" == "mcp" && "$2" == "debug" ]]; then echo "auth-required"; exit 0; fi
exit 0
OPENCODE
chmod +x "$STUBS/opencode"

rc=$(run_check "doctor-auth" bash "$ROOT_DIR/scripts/doctor.sh" --profile core --strict)
[[ $rc -eq 1 ]] && pass "doctor with auth-required MCP exits code 1" || fail "doctor with auth-required MCP exit code $rc (expected 1)"
grep -q 'requiere autenticacion' "$TMP_DIR/doctor-auth.out" && pass "doctor detects auth-required MCP" || fail "doctor did not flag auth-required MCP"

# Restore opencode stub
cat > "$STUBS/opencode" <<'OPENCODE'
#!/bin/bash
if [[ "$1" == "mcp" && "$2" == "debug" ]]; then echo "connected"; exit 0; fi
exit 0
OPENCODE
chmod +x "$STUBS/opencode"

# --- Summary ---
printf '\n========================================\n'
printf '  Resultados: %d pasaron, %d fallaron\n' "$PASS" "$FAIL"
printf '========================================\n'
(( FAIL == 0 ))
