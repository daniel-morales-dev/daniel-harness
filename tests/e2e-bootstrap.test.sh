#!/usr/bin/env bash
# E2E: bootstrap real con stubs en HOME aislado
set -euo pipefail
umask 077

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# Home aislado por perfil — evita contaminación entre fases
HOME_CORE="$TMP_DIR/home-core"
HOME_ALEGRA="$TMP_DIR/home-alegra"
HOME_MIGRATION="$TMP_DIR/home-migration"
HOME_FULL="$TMP_DIR/home-full"
CONFIG_TMP="$TMP_DIR/config"
STUBS="$TMP_DIR/stubs"
PASS=0
FAIL=0

pass() { printf '  [ok] %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf '  [FAIL] %s\n' "$*"; FAIL=$((FAIL + 1)); }

run_check() {
  local label=$1; shift
  set +e
  "$@" > "$TMP_DIR/${label// /_}.out" 2>&1; local rc=$?
  set -e
  printf '%s' "$rc"
}

# --- Setup: stubs (compartidos) ---
printf '=== Setup: stubs ===\n'
mkdir -p "$STUBS" "$HOME_CORE" "$HOME_ALEGRA" "$HOME_MIGRATION" "$HOME_FULL" "$CONFIG_TMP"
mkdir -p "$HOME_CORE/.nvm" "$HOME_ALEGRA/.nvm" "$HOME_MIGRATION/.nvm" "$HOME_FULL/.nvm"

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

cat > "$CONFIG_TMP/daniel-harness/config.yaml" <<'EOF'
version: "1"
trust: trusted
EOF

# Pre-create config.yaml per HOME with trusted model (avoid restricted from example)
for h in "$HOME_CORE" "$HOME_ALEGRA" "$HOME_MIGRATION" "$HOME_FULL"; do
  mkdir -p "$h/.config/daniel-harness/secrets/tunnels"
  cat > "$h/.config/daniel-harness/config.yaml" <<'EOF'
version: "1"
trust: trusted
EOF
done

export PATH="$STUBS:$PATH"

# Helper: bootstrap a profile with isolated HOME
bootstrap_profile() {
  local profile=$1 _label=$2 home=$3 skip_docker=${4:-false}
  local extra=""
  [[ "$skip_docker" == "true" ]] && extra="--skip-docker"
  env PATH="$STUBS:$PATH" HOME="$home" XDG_CONFIG_HOME="$home/.config" NVM_DIR="$home/.nvm" \
    bash "$ROOT_DIR/scripts/bootstrap.sh" --profile "$profile" $extra
}

# Helper: doctor a profile with isolated HOME
doctor_profile() {
  local profile=$1 _label=$2 home=$3
  env PATH="$STUBS:$PATH" HOME="$home" XDG_CONFIG_HOME="$home/.config" NVM_DIR="$home/.nvm" \
    bash "$ROOT_DIR/scripts/doctor.sh" --profile "$profile" --strict
}

# Helper: check MCP exists in opencode.json for a profile
mcp_exists() {
  local home=$1 mcp=$2
  local oc_file="$home/.config/opencode/opencode.json"
  jq -e ".mcp | has(\"$mcp\")" "$oc_file" >/dev/null 2>&1
}

# Helper: get MCP list
mcp_list() {
  local home=$1
  local oc_file="$home/.config/opencode/opencode.json"
  jq -r '.mcp | keys[]' "$oc_file" 2>/dev/null | sort
}

# --- Phase 1: Bootstrap --profile core ---
printf '\n=== Phase 1: bootstrap --profile core ===\n'
rc=$(run_check "bootstrap-core" bootstrap_profile core core "$HOME_CORE")
[[ $rc -eq 0 ]] && pass "bootstrap core exit code 0" || fail "bootstrap core exit code $rc"
grep -q 'Bootstrap completado y saludable' "$TMP_DIR/bootstrap-core.out" && pass "bootstrap core completed healthy" || {
  cat "$TMP_DIR/bootstrap-core.out"
  fail "bootstrap core not healthy"
}

OC_CORE="$HOME_CORE/.config/opencode/opencode.json"

# --- Phase 2: Validate opencode.json (core) ---
printf '\n=== Phase 2: opencode.json validation (core) ===\n'
jq empty "$OC_CORE" && pass "core opencode.json is valid JSON" || fail "core opencode.json is not valid JSON"
[[ $(jq 'has("mcp")' "$OC_CORE") == "true" ]] && pass "mcp section exists" || fail "mcp section missing"
[[ $(jq 'has("plugin")' "$OC_CORE") == "true" ]] && pass "plugin section exists" || fail "plugin section missing"
mcp_exists "$HOME_CORE" "codegraph" && pass "MCP codegraph in core" || fail "MCP codegraph missing"
mcp_exists "$HOME_CORE" "engram" && pass "MCP engram in core" || fail "MCP engram missing"
mcp_exists "$HOME_CORE" "linear" && fail "MCP linear should NOT be in core" || pass "MCP linear not in core"
mcp_exists "$HOME_CORE" "github" && fail "MCP github should NOT be in core" || pass "MCP github not in core"
mcp_exists "$HOME_CORE" "context7" && fail "MCP context7 should NOT be in core" || pass "MCP context7 not in core"
mcp_exists "$HOME_CORE" "wiki-alegra" && fail "MCP wiki-alegra should NOT be in core" || pass "MCP wiki-alegra not in core"
jq -e '[.mcp[] | has("disabledTools")] | any | not' "$OC_CORE" >/dev/null && pass "no MCP has disabledTools" || fail "some MCP still has disabledTools"
jq -e '.plugin[] | startswith("@dietrichgebert/ponytail")' "$OC_CORE" >/dev/null && pass "Ponytail plugin registered" || fail "Ponytail plugin missing"
jq -e '.mcp.codegraph.type == "local"' "$OC_CORE" >/dev/null && pass "codegraph is local" || fail "codegraph type mismatch"
jq -e '.mcp.engram.type == "local"' "$OC_CORE" >/dev/null && pass "engram is local" || fail "engram type mismatch"

# --- Phase 3: Agents and skills ---
printf '\n=== Phase 3: Agents and skills ===\n'
for a in alegra-microservice-engineer code-reviewer alegra-microservice-test-engineer php-engineer migration-parity-reviewer; do
  [[ -L "$HOME_CORE/.config/opencode/agents/$a.md" ]] && pass "agent $a" || fail "agent $a missing"
done
for s in monolith-to-micro-migration task-lifecycle; do
  [[ -d "$HOME_CORE/.config/opencode/skills/$s" ]] && pass "skill $s" || fail "skill $s missing"
done
[[ -f "$HOME_CORE/.config/opencode/commands/migration-gap-analysis.md" ]] && pass "command migration-gap-analysis" || fail "command migration-gap-analysis missing"
[[ -L "$HOME_CORE/.local/bin/dh" ]] && pass "dh CLI linked" || fail "dh CLI missing"

# --- Phase 4: Doctor --profile core --strict ---
printf '\n=== Phase 4: doctor --profile core --strict ===\n'
rc=$(run_check "doctor-core" doctor_profile core core "$HOME_CORE")
[[ $rc -eq 0 ]] && pass "doctor core exit code 0" || fail "doctor core exit code $rc"
grep -q 'Resumen: 0 crítico(s)' "$TMP_DIR/doctor-core.out" && pass "doctor --profile core --strict passed" || {
  cat "$TMP_DIR/doctor-core.out"
  fail "doctor reported criticals"
}

# --- Phase 5: Idempotence (second core bootstrap) ---
printf '\n=== Phase 5: Idempotence ===\n'
CORE_CONFIG="$HOME_CORE/.config/daniel-harness/config.yaml"
FIRST_HASH=$(sha256sum "$CORE_CONFIG" 2>/dev/null | cut -d' ' -f1 || echo none)
BACKUPS_BEFORE=$(find "$HOME_CORE/.config/opencode/" -name 'opencode.json.bak.*' 2>/dev/null | wc -l)
rc=$(run_check "bootstrap-idempotent" bootstrap_profile core core "$HOME_CORE")
[[ $rc -eq 0 ]] && pass "second bootstrap exit code 0" || fail "second bootstrap exit code $rc"
SECOND_HASH=$(sha256sum "$CORE_CONFIG" 2>/dev/null | cut -d' ' -f1 || echo none)
[[ "$FIRST_HASH" == "$SECOND_HASH" ]] && pass "second bootstrap is idempotent (config unchanged)" || fail "second bootstrap modified config"
BACKUPS_AFTER=$(find "$HOME_CORE/.config/opencode/" -name 'opencode.json.bak.*' 2>/dev/null | wc -l)
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

# --- Phase 7: Bootstrap --profile alegra (HOME aislado) ---
printf '\n=== Phase 7: bootstrap --profile alegra ===\n'
rc=$(run_check "bootstrap-alegra" bootstrap_profile alegra alegra "$HOME_ALEGRA")
[[ $rc -eq 0 ]] && pass "bootstrap alegra exit code 0" || fail "bootstrap alegra exit code $rc"
grep -q 'Bootstrap completado y saludable' "$TMP_DIR/bootstrap-alegra.out" && pass "bootstrap alegra completed healthy" || {
  cat "$TMP_DIR/bootstrap-alegra.out"
  fail "bootstrap alegra not healthy"
}

OC_ALEGRA="$HOME_ALEGRA/.config/opencode/opencode.json"

# Verify exact MCP set for alegra: codegraph, engram, linear, context7, wiki-alegra, github
printf '\n=== Phase 7b: MCP set validation (alegra) ===\n'
ALEGRA_MCPS=$(mcp_list "$HOME_ALEGRA")
for mcp in codegraph engram linear context7 wiki-alegra github; do
  echo "$ALEGRA_MCPS" | grep -qxF "$mcp" && pass "alegra MCP $mcp" || fail "alegra MCP $mcp missing"
done
for mcp in sentry mcp-raia-lib; do
  echo "$ALEGRA_MCPS" | grep -qxF "$mcp" && fail "alegra should NOT have MCP $mcp" || pass "alegra correctly lacks MCP $mcp"
done

# --- Phase 8: Bootstrap --profile migration --skip-docker (HOME aislado) ---
printf '\n=== Phase 8: bootstrap --profile migration --skip-docker ===\n'
rc=$(run_check "bootstrap-migration" bootstrap_profile migration migration "$HOME_MIGRATION" true)
[[ $rc -eq 0 ]] && pass "bootstrap migration --skip-docker exit code 0" || fail "bootstrap migration --skip-docker exit code $rc"
grep -q 'Bootstrap completado y saludable' "$TMP_DIR/bootstrap-migration.out" && pass "bootstrap migration completed healthy" || {
  cat "$TMP_DIR/bootstrap-migration.out"
  fail "bootstrap migration not healthy"
}
grep -q 'Docker omitido' "$TMP_DIR/bootstrap-migration.out" && pass "migration --skip-docker respected" || fail "migration did not skip docker"

OC_MIGRATION="$HOME_MIGRATION/.config/opencode/opencode.json"

# Verify exact MCP set for migration: heredados de alegra + mcp-raia-lib
printf '\n=== Phase 8b: MCP set validation (migration) ===\n'
MIGRATION_MCPS=$(mcp_list "$HOME_MIGRATION")
for mcp in codegraph engram linear context7 wiki-alegra github mcp-raia-lib; do
  echo "$MIGRATION_MCPS" | grep -qxF "$mcp" && pass "migration MCP $mcp" || fail "migration MCP $mcp missing"
done
echo "$MIGRATION_MCPS" | grep -qxF "sentry" && fail "migration should NOT have MCP sentry" || pass "migration correctly lacks sentry"

# --- Phase 9: Bootstrap --profile full (HOME aislado) ---
printf '\n=== Phase 9: bootstrap --profile full ===\n'
rc=$(run_check "bootstrap-full" bootstrap_profile full full "$HOME_FULL")
[[ $rc -eq 0 ]] && pass "bootstrap full exit code 0" || fail "bootstrap full exit code $rc"
grep -q 'Bootstrap completado y saludable' "$TMP_DIR/bootstrap-full.out" && pass "bootstrap full completed healthy" || {
  cat "$TMP_DIR/bootstrap-full.out"
  fail "bootstrap full not healthy"
}

OC_FULL="$HOME_FULL/.config/opencode/opencode.json"

# Verify exact MCP set for full: heredados de alegra + mcp-raia-lib + sentry
printf '\n=== Phase 9b: MCP set validation (full) ===\n'
FULL_MCPS=$(mcp_list "$HOME_FULL")
for mcp in codegraph engram linear context7 wiki-alegra github mcp-raia-lib sentry; do
  echo "$FULL_MCPS" | grep -qxF "$mcp" && pass "full MCP $mcp" || fail "full MCP $mcp missing"
done
# no extra MCPs beyond the expected set
EXPECTED_FULL="codegraph engram linear context7 wiki-alegra github mcp-raia-lib sentry"
for mcp in $FULL_MCPS; do
  echo "$EXPECTED_FULL" | grep -qwF "$mcp" && pass "full MCP $mcp is in expected set" || fail "full has unexpected MCP $mcp"
done

# --- Phase 10: Invalid JSON rollback (sobre HOME core para evitar contaminar perfiles) ---
printf '\n=== Phase 10: Invalid JSON rollback ===\n'
BACKUPS_BEFORE_RB=$(find "$HOME_CORE/.config/opencode/" -name 'opencode.json.bak.*' 2>/dev/null | wc -l)
printf 'INVALID JSON' > "$OC_CORE"
rc=$(run_check "bootstrap-rollback" env PATH="$STUBS:$PATH" HOME="$HOME_CORE" XDG_CONFIG_HOME="$HOME_CORE/.config" NVM_DIR="$HOME_CORE/.nvm" bash "$ROOT_DIR/scripts/bootstrap.sh" --profile core)
[[ $rc -eq 1 ]] && pass "bootstrap with invalid JSON exits code 1" || fail "bootstrap with invalid JSON exit code $rc (expected 1)"
BACKUPS_AFTER_RB=$(find "$HOME_CORE/.config/opencode/" -name 'opencode.json.bak.*' 2>/dev/null | wc -l)
[[ $BACKUPS_AFTER_RB -eq $((BACKUPS_BEFORE_RB + 1)) ]] && pass "backup created (before=$BACKUPS_BEFORE_RB after=$BACKUPS_AFTER_RB)" || fail "backup count mismatch expected +1: before=$BACKUPS_BEFORE_RB after=$BACKUPS_AFTER_RB"

# --- Phase 11: Doctor live check (auth-required sobre HOME_CORE) ---
printf '\n=== Phase 11: Doctor MCP live check ===\n'
# Restore valid opencode.json (Phase 10 left it corrupt)
rm -f "$OC_CORE"
env PATH="$STUBS:$PATH" HOME="$HOME_CORE" XDG_CONFIG_HOME="$HOME_CORE/.config" NVM_DIR="$HOME_CORE/.nvm" \
  bash "$ROOT_DIR/scripts/bootstrap.sh" --profile core > "$TMP_DIR/restore.out" 2>&1 || true
jq empty "$OC_CORE" >/dev/null 2>&1 || {
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

rc=$(run_check "doctor-auth" env PATH="$STUBS:$PATH" HOME="$HOME_CORE" XDG_CONFIG_HOME="$HOME_CORE/.config" NVM_DIR="$HOME_CORE/.nvm" bash "$ROOT_DIR/scripts/doctor.sh" --profile core --strict)
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
