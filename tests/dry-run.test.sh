#!/usr/bin/env bash
# tests/dry-run.test.sh
# P1: --help y --dry-run no deben modificar HOME
set -euo pipefail
umask 077

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

PASS=0; FAIL=0
pass() { printf '  [ok] %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf '  [FAIL] %s\n' "$*"; FAIL=$((FAIL + 1)); }

snapshot_home() {
  local output=$1 path rel kind digest target
  : > "$output"
  while IFS= read -r -d '' path; do
    rel=${path#"$HOME_DIR"}
    [[ -n "$rel" ]] || rel=.
    digest=-
    target=-
    if [[ -L "$path" ]]; then
      kind=symlink
      target=$(readlink "$path")
    elif [[ -f "$path" ]]; then
      kind=file
      digest=$(sha256sum "$path" | cut -d' ' -f1)
    elif [[ -d "$path" ]]; then
      kind=directory
    else
      kind=other
    fi
    printf '%s|%s|%s|%s|%s|%s\n' \
      "$rel" "$kind" "$(stat -c '%a' "$path")" "$(stat -c '%u:%g' "$path")" \
      "$(stat -c '%y' "$path")" "$digest:$target" >> "$output"
  done < <(find "$HOME_DIR" -xdev -print0 | sort -z)
}

run_unchanged() {
  local label=$1 profile=$2
  local output="$TMP_DIR/${label}.out"
  local before="$TMP_DIR/${label}.before" after="$TMP_DIR/${label}.after"
  snapshot_home "$before"
  set +e
  timeout 60 bash "$ROOT_DIR/scripts/bootstrap.sh" --dry-run --profile "$profile" > "$output" 2>&1
  local rc=$?
  set -e
  [[ $rc -eq 0 ]] && pass "$label: exit 0" || fail "$label: exit $rc"
  snapshot_home "$after"
  cmp -s "$before" "$after" && pass "$label: HOME sin cambios" || {
    fail "$label: HOME cambió"
    diff -u "$before" "$after" || true
  }
  grep -q '\[simulado\]' "$output" && pass "$label: imprime plan" || fail "$label: no imprime plan"
}

# --- Setup: HOME limpio ---
HOME_DIR="$TMP_DIR/home-clean"
mkdir -p "$HOME_DIR"
export HOME="$HOME_DIR"
export XDG_CONFIG_HOME="$HOME_DIR/.config"
export NVM_DIR="$HOME_DIR/.nvm"

echo "=== Test 1: --help no modifica nada ==="
snapshot_home "$TMP_DIR/help.before"
set +e
timeout 30 bash "$ROOT_DIR/scripts/bootstrap.sh" --help > /dev/null 2>&1
RC=$?
set -e
if [[ $RC -eq 0 ]]; then pass "help exit code 0"; else fail "help exit code $RC"; fi
snapshot_home "$TMP_DIR/help.after"
cmp -s "$TMP_DIR/help.before" "$TMP_DIR/help.after" && pass "help: HOME sin cambios" || fail "help: HOME cambió"

echo "=== Test 2: HOME vacío ==="
run_unchanged "empty-core" core

echo "=== Test 3: config existente ==="
mkdir -p "$HOME_DIR/.config/opencode"
printf '%s\n' '{"$schema":"https://opencode.ai/config.json","agent":{"custom":{"mode":"subagent"}},"plugin":["external@1"],"mcp":{"custom":{"type":"remote","url":"https://example.invalid"}}}' > "$HOME_DIR/.config/opencode/opencode.json"
chmod 600 "$HOME_DIR/.config/opencode/opencode.json"
run_unchanged "existing-config" alegra

echo "=== Test 4: journal, backups y secretos residuales ==="
mkdir -p "$HOME_DIR/.config/daniel-harness/state" "$HOME_DIR/.config/daniel-harness/backups" \
  "$HOME_DIR/.config/daniel-harness/secrets/github" "$HOME_DIR/.config/daniel-harness/secrets/navi"
chmod 700 "$HOME_DIR/.config/daniel-harness" "$HOME_DIR/.config/daniel-harness/state" \
  "$HOME_DIR/.config/daniel-harness/backups" "$HOME_DIR/.config/daniel-harness/secrets" \
  "$HOME_DIR/.config/daniel-harness/secrets/github" "$HOME_DIR/.config/daniel-harness/secrets/navi"
printf '%s\n' '{"journalVersion":"2","phase":"applying","resources":[]}' > "$HOME_DIR/.config/daniel-harness/state/.bootstrap-journal.json"
printf '%s\n' 'backup-data' > "$HOME_DIR/.config/daniel-harness/backups/opencode-config-pre-1.bak"
printf '%s\n' 'Bearer synthetic-dry-run-token' > "$HOME_DIR/.config/daniel-harness/secrets/github/authorization"
printf '%s\n' 'https://synthetic.invalid/navi' > "$HOME_DIR/.config/daniel-harness/secrets/navi/url"
printf '%s\n' 'synthetic-client-id' > "$HOME_DIR/.config/daniel-harness/secrets/navi/client-id"
chmod 600 "$HOME_DIR/.config/daniel-harness/state/.bootstrap-journal.json" \
  "$HOME_DIR/.config/daniel-harness/backups/opencode-config-pre-1.bak" \
  "$HOME_DIR/.config/daniel-harness/secrets/github/authorization" \
  "$HOME_DIR/.config/daniel-harness/secrets/navi/url" \
  "$HOME_DIR/.config/daniel-harness/secrets/navi/client-id"
run_unchanged "residual-full" full
grep -q 'MCP sentry' "$TMP_DIR/residual-full.out" && pass "full: plan incluye sentry" || fail "full: plan incompleto"
if grep -qE 'synthetic-dry-run-token|synthetic-client-id|synthetic\.invalid/navi' "$TMP_DIR/residual-full.out"; then
  fail "full: secreto expuesto en output"
else
  pass "full: output sin secretos"
fi

[[ -f "$HOME_DIR/.config/daniel-harness/state/.bootstrap-journal.json" ]] \
  && pass "journal residual preservado" || fail "journal residual consumido"

echo ""
echo "=== Resultados: $PASS pasaron, $FAIL fallaron ==="
(( FAIL == 0 ))
