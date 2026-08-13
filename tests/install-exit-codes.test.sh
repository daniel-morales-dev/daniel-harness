#!/usr/bin/env bash
# Contrato top-level: install preserva estados de bootstrap y auth persistente.
set -euo pipefail
umask 077

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
PASS=0
FAIL=0

pass() { printf '  [ok] %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf '  [FAIL] %s\n' "$*"; FAIL=$((FAIL + 1)); }

make_fixture() {
  local name=$1
  local test_root="$TMP_DIR/$name/repo"
  mkdir -p "$TMP_DIR/$name"
  cp -a "$ROOT_DIR/." "$test_root"
  mkdir -p "$TMP_DIR/$name/stubs"
  cat > "$TMP_DIR/$name/stubs/sudo" <<'STUB'
#!/usr/bin/env bash
[[ "${1:-}" == "-n" && "${2:-}" == "true" ]] && exit 0
[[ "${1:-}" == "-v" ]] && exit 0
exec "$@"
STUB
  cat > "$TMP_DIR/$name/stubs/opencode" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${AUTH_CALLS:?}"
exit 0
STUB
  cat > "$test_root/scripts/bootstrap.sh" <<'STUB'
#!/usr/bin/env bash
exit "${BOOTSTRAP_RC:?}"
STUB
  cat > "$test_root/scripts/doctor.sh" <<'STUB'
#!/usr/bin/env bash
touch "${DOCTOR_CALLS:?}"
exit 0
STUB
  chmod +x "$TMP_DIR/$name/stubs/sudo" "$TMP_DIR/$name/stubs/opencode" "$test_root/scripts/bootstrap.sh" "$test_root/scripts/doctor.sh"
  printf '%s\n' "$test_root"
}

run_install() {
  local name=$1 rc=$2 test_root=$3
  shift 3
  set +e
  env PATH="$TMP_DIR/$name/stubs:$PATH" HOME="$TMP_DIR/$name/home" \
    XDG_CONFIG_HOME="$TMP_DIR/$name/home/.config" BOOTSTRAP_RC="$rc" \
    DOCTOR_CALLS="$TMP_DIR/$name/doctor.calls" AUTH_CALLS="$TMP_DIR/$name/auth.calls" \
    bash "$test_root/install" --profile alegra "$@" > "$TMP_DIR/$name/out" 2>&1
  local actual=$?
  set -e
  printf '%s' "$actual"
}

printf '=== Exit code propagation ===\n'
for expected in 0 1 2 3 4; do
  name="rc-$expected"
  test_root=$(make_fixture "$name")
  actual=$(run_install "$name" "$expected" "$test_root" --non-interactive)
  [[ "$actual" == "$expected" ]] && pass "bootstrap $expected -> install $actual" || fail "bootstrap $expected -> install $actual"
  if [[ "$expected" == 0 ]]; then
    [[ -f "$TMP_DIR/$name/doctor.calls" ]] && pass "bootstrap 0 ejecuta doctor" || fail "bootstrap 0 no ejecutó doctor"
  else
    [[ ! -e "$TMP_DIR/$name/doctor.calls" ]] && pass "bootstrap $expected no ejecuta doctor" || fail "bootstrap $expected ejecutó doctor"
  fi
done

printf '\n=== Connect non-interactive ===\n'
name=connect-non-interactive
test_root=$(make_fixture "$name")
set +e
env PATH="$TMP_DIR/$name/stubs:$PATH" HOME="$TMP_DIR/$name/home" XDG_CONFIG_HOME="$TMP_DIR/$name/home/.config" \
  BOOTSTRAP_RC=0 DOCTOR_CALLS="$TMP_DIR/$name/doctor.calls" AUTH_CALLS="$TMP_DIR/$name/auth.calls" \
  bash "$test_root/install" --profile alegra --connect --non-interactive > "$TMP_DIR/$name/out" 2>&1
actual=$?
set -e
[[ "$actual" == 1 ]] && pass "connect non-interactive devuelve 1" || fail "connect non-interactive devuelve $actual"
[[ ! -s "$TMP_DIR/$name/auth.calls" ]] && pass "connect non-interactive no invoca auth" || fail "connect non-interactive invocó auth"

printf '\n=== GitHub persistent auth ===\n'
name=persistent-auth
test_root=$(make_fixture "$name")
home="$TMP_DIR/$name/home"
secret="$home/.config/daniel-harness/secrets/github/authorization"
mkdir -p "$(dirname "$secret")" "$home/.config/opencode"
chmod 700 "$(dirname "$secret")"
printf '%s\n' 'Bearer dummy-token' > "$secret"
chmod 600 "$secret"
printf '{"mcp":{"github":{"headers":{"Authorization":"{file:%s}"}}}}\n' "$secret" > "$home/.config/opencode/opencode.json"
config_before=$(sha256sum "$home/.config/opencode/opencode.json" | cut -d' ' -f1)
secret_before=$(sha256sum "$secret" | cut -d' ' -f1)
actual=$(run_install "$name" 0 "$test_root" --connect)
config_after=$(sha256sum "$home/.config/opencode/opencode.json" | cut -d' ' -f1)
secret_after=$(sha256sum "$secret" | cut -d' ' -f1)
[[ "$actual" == 0 ]] && pass "auth persistente mantiene install saludable" || fail "auth persistente devuelve $actual"
grep -q 'GitHub: autenticación persistente válida' "$TMP_DIR/$name/out" && pass "auth persistente reconocida sin env" || fail "auth persistente no reconocida"
! grep -q 'GITHUB_PERSONAL_ACCESS_TOKEN no configurado' "$TMP_DIR/$name/out" && pass "sin warning de env ausente" || fail "warning de env ausente presente"
[[ "$secret_before" == "$secret_after" && "$config_before" == "$config_after" ]] && pass "secret y referencia no se modifican" || fail "secret o referencia cambiaron"

printf '\n=== Resultados: %d pasaron, %d fallaron ===\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
