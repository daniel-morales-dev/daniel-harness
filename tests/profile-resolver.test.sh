#!/usr/bin/env bash
# P1: Profile resolver — herencia, dedup, bordes, parsing
set -euo pipefail
umask 077

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

PASS=0
FAIL=0
pass() { printf '  [ok] %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf '  [FAIL] %s\n' "$*"; FAIL=$((FAIL + 1)); }

# Create temp manifest with profiles for testing
MANIFEST="$TMP_DIR/manifest.yaml"
cat > "$MANIFEST" <<'EOF'
profiles:
  base:
    tools: ["opencode", "git"]
    mcps: ["codegraph"]
  child:
    extends: base
    tools: ["docker"]
    mcps: ["engram"]
  grandchild:
    extends: child
    mcps: ["linear"]
  standalone:
    tools: ["vim"]
    mcps: ["custom-mcp"]
  self-ref:
    extends: self-ref
    mcps: ["infinite"]
  cycle-a:
    extends: cycle-b
    mcps: ["a"]
  cycle-b:
    extends: cycle-a
    mcps: ["b"]
  unknown-parent:
    extends: does-not-exist
    mcps: ["orphan"]
EOF

source "$ROOT_DIR/scripts/profile-resolver.sh"

# Override MANIFEST for the sourced functions
MANIFEST="$MANIFEST"

# --- Test: exact inheritance ---
printf '=== Exact inheritance ===\n'
tools=$(get_profile_tools "child" | sort | tr '\n' ' ')
[[ "$tools" == "docker git opencode " ]] && pass "child inherits base tools" || fail "child tools: $tools"

mcps=$(get_profile_mcps "child" | sort | tr '\n' ' ')
[[ "$mcps" == "codegraph engram " ]] && pass "child inherits base mcps" || fail "child mcps: $mcps"

# --- Test: multi-level inheritance ---
printf '\n=== Multi-level inheritance ===\n'
tools=$(get_profile_tools "grandchild" | sort | tr '\n' ' ')
[[ "$tools" == "docker git opencode " ]] && pass "grandchild inherits all parent tools" || fail "grandchild tools: $tools"

mcps=$(get_profile_mcps "grandchild" | sort | tr '\n' ' ')
[[ "$mcps" == "codegraph engram linear " ]] && pass "grandchild inherits all parent mcps" || fail "grandchild mcps: $mcps"

# --- Test: deduplication ---
printf '\n=== Deduplication ===\n'
mcps=$(get_profile_mcps "grandchild" | sort | tr '\n' ' ')
# codegraph and engram should appear exactly once
count_codegraph=$(echo "$mcps" | grep -o 'codegraph' | wc -l)
[[ "$count_codegraph" -eq 1 ]] && pass "codegraph deduplicated" || fail "codegraph appears $count_codegraph times"

# --- Test: standalone (no inheritance) ---
printf '\n=== Standalone (no inheritance) ===\n'
tools=$(get_profile_tools "standalone" | sort | tr '\n' ' ')
[[ "$tools" == "vim " ]] && pass "standalone has own tools only" || fail "standalone tools: $tools"

# --- Test: profile_includes ---
printf '\n=== profile_includes ===\n'
profile_includes "child" "tools" "docker" && pass "child includes docker" || fail "child should include docker"
profile_includes "child" "tools" "opencode" && pass "child inherits opencode" || fail "child should inherit opencode"
profile_includes "grandchild" "mcps" "codegraph" && pass "grandchild includes codegraph" || fail "grandchild should inherit codegraph"
profile_includes "standalone" "tools" "opencode" && fail "standalone should not inherit opencode" || pass "standalone correctly lacks opencode"

# --- Test: parse_mcp_names ---
printf '\n=== parse_mcp_names ===\n'
# Manifest has mcp_servers section
cat > "$TMP_DIR/manifest-full.yaml" <<'EOF'
profiles:
  test: {mcps: ["codegraph", "engram"]}
mcp_servers:
  codegraph:
    command: codegraph serve --mcp
    type: local
  engram:
    command: engram mcp --tools=agent
    type: local
EOF
names=$(MANIFEST="$TMP_DIR/manifest-full.yaml" bash -c 'source "'"$ROOT_DIR"'/scripts/profile-resolver.sh"; parse_mcp_names' 2>/dev/null || true)
echo "$names" | grep -q 'codegraph' && pass "parse_mcp_names finds codegraph" || fail "parse_mcp_names missing codegraph"
echo "$names" | grep -q 'engram' && pass "parse_mcp_names finds engram" || fail "parse_mcp_names missing engram"

# --- Test: parse_mcp_field ---
printf '\n=== parse_mcp_field ===\n'
field=$(MANIFEST="$TMP_DIR/manifest-full.yaml" bash -c 'source "'"$ROOT_DIR"'/scripts/profile-resolver.sh"; parse_mcp_field codegraph type' 2>/dev/null || true)
[[ "$field" == "local" ]] && pass "parse_mcp_field codegraph type=local" || fail "parse_mcp_field: $field"

# --- Test: Cycle detection ---
printf '\n=== Cycle detection ===\n'
result=$(MANIFEST="$MANIFEST" bash -c 'source "'"$ROOT_DIR"'/scripts/profile-resolver.sh"; get_profile_tools self-ref' 2>&1 || true)
echo "$result" | grep -qE '(error|ciclo)' && fail "self-ref should be handled gracefully" || pass "self-ref handled by equality guard"

result=$(MANIFEST="$MANIFEST" bash -c 'source "'"$ROOT_DIR"'/scripts/profile-resolver.sh"; get_profile_tools cycle-a' 2>&1 || true)
echo "$result" | grep -qE '(error|ciclo)' && pass "cycle-a→cycle-b→cycle-a detected" || fail "cycle-a not detected ($result)"

# --- Test: Unknown parent ---
printf '\n=== Unknown parent ===\n'
result=$(MANIFEST="$MANIFEST" bash -c 'source "'"$ROOT_DIR"'/scripts/profile-resolver.sh"; get_profile_tools unknown-parent' 2>&1 || true)
echo "$result" | grep -qE '(error|no existe)' && pass "unknown parent detected" || fail "unknown parent not detected ($result)"

# --- Test: Unknown profile ---
printf '\n=== Unknown profile ===\n'
result=$(MANIFEST="$MANIFEST" bash -c 'source "'"$ROOT_DIR"'/scripts/profile-resolver.sh"; get_profile_tools does-not-exist-either' 2>&1 || true)
echo "$result" | grep -qE '(error|no existe)' && pass "unknown profile detected" || fail "unknown profile not detected ($result)"

# --- Summary ---
printf '\n========================================\n'
printf '  Profile resolver: %d pasaron, %d fallaron\n' "$PASS" "$FAIL"
printf '========================================\n'
(( FAIL == 0 ))
