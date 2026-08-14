#!/usr/bin/env bash
# Product integration coverage for the typed transaction coordinator.
set -euo pipefail
umask 077

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT_DIR/tests/helpers/nvm-stub.sh"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
PASS=0
FAIL=0
pass() { printf '  [ok] %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf '  [FAIL] %s\n' "$*"; FAIL=$((FAIL + 1)); }

HOME_DIR="$TMP_DIR/home"
STUBS="$TMP_DIR/stubs"
mkdir -p "$HOME_DIR/.config/daniel-harness/secrets/tunnels" "$HOME_DIR/.nvm" "$STUBS"
for tool in sudo apt-get dpkg curl node npm opencode codegraph rtk engram gentle-ai dh gh aws unzip; do
  cat > "$STUBS/$tool" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
  chmod +x "$STUBS/$tool"
done
cat > "$STUBS/sudo" <<'STUB'
#!/usr/bin/env bash
[[ "${1:-}" == -n && "${2:-}" == true ]] && exit 0
[[ "${1:-}" == -v ]] && exit 0
exec "$@"
STUB
create_nvm_curl_stub "$STUBS"
cat > "$STUBS/opencode" <<'STUB'
#!/usr/bin/env bash
case "$1:${2:-}:${3:-}" in
  --version::) echo 'opencode 1.18.18' ;;
  agent:list:--help|mcp:--help:|mcp:debug:--help|mcp:auth:--help|debug:config:--help) ;;
  agent:list:*) printf '%s\n' alegra-microservice-engineer alegra-microservice-test-engineer alegra-code-reviewer php-engineer migration-parity-reviewer ;;
  mcp:debug:*) echo connected ;;
esac
STUB
cat > "$STUBS/gentle-ai" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  --version) echo 'gentle-ai 2.3.0' ;;
  skill-registry|sync) ;;
  doctor) echo 'Status:  healthy' ;;
esac
STUB
chmod +x "$STUBS/opencode" "$STUBS/gentle-ai"
python3 -c "
import yaml
from pathlib import Path
cfg = yaml.safe_load((Path('$ROOT_DIR/examples/config.example.yaml')).read_text())
cfg['models'] = [model for model in cfg['models'] if model.get('trust') != 'restricted']
Path('$HOME_DIR/.config/daniel-harness/config.yaml').write_text(yaml.dump(cfg))
"
export PATH="$STUBS:$PATH" HOME="$HOME_DIR" XDG_CONFIG_HOME="$HOME_DIR/.config" NVM_DIR="$HOME_DIR/.nvm"
export GITHUB_PERSONAL_ACCESS_TOKEN='ghp_fixture_not_real'
export DH_TEST_MODE=1
export DH_TRANSACTION_ALLOW_TMP=1

run_bootstrap() {
  local label=$1
  shift
  set +e
  "$@" bash "$ROOT_DIR/scripts/bootstrap.sh" --profile "${DH_TEST_PROFILE:-alegra}" > "$TMP_DIR/$label.out" 2>&1
  local rc=$?
  set -e
  printf '%s' "$rc"
}

AGENT_DIR="$HOME_DIR/.config/opencode/agents"
STATE_DIR="$HOME_DIR/.config/daniel-harness/state"
JOURNAL="$STATE_DIR/.bootstrap-journal.json"
MANAGED_STATE="$STATE_DIR/opencode-managed.state"
CONFIG="$HOME_DIR/.config/opencode/opencode.json"

echo '=== First run ==='
[[ $(run_bootstrap first env) == 0 ]] && pass 'first run succeeds' || fail 'first run fails'
[[ -f "$CONFIG" && -f "$STATE_DIR/opencode-managed.json" && -f "$MANAGED_STATE" && ! -e "$JOURNAL" ]] && pass 'coordinator committed config and states' || fail 'missing committed resources'
for agent in alegra-microservice-engineer alegra-microservice-test-engineer alegra-code-reviewer php-engineer migration-parity-reviewer; do
  [[ -f "$AGENT_DIR/$agent.md" && ! -L "$AGENT_DIR/$agent.md" && $(stat -c '%a' "$AGENT_DIR/$agent.md") == 600 ]] && pass "$agent managed" || fail "$agent invalid"
done

echo '=== Idempotence ==='
sleep 1
before=$(sha256sum "$CONFIG" "$MANAGED_STATE" "$AGENT_DIR"/*.md | sha256sum | cut -d' ' -f1)
mtime_before=$(stat -c '%Y' "$AGENT_DIR/php-engineer.md")
[[ $(run_bootstrap second env) == 0 ]] && pass 'second run succeeds' || fail 'second run fails'
after=$(sha256sum "$CONFIG" "$MANAGED_STATE" "$AGENT_DIR"/*.md | sha256sum | cut -d' ' -f1)
mtime_after=$(stat -c '%Y' "$AGENT_DIR/php-engineer.md")
[[ "$before" == "$after" && "$mtime_before" == "$mtime_after" && ! -e "$JOURNAL" ]] && pass 'no managed rewrite on second run' || fail 'second run rewrote managed resources'

echo '=== Managed conflict ==='
printf '\nuser change\n' >> "$AGENT_DIR/php-engineer.md"
user_hash=$(sha256sum "$AGENT_DIR/php-engineer.md" | cut -d' ' -f1)
[[ $(run_bootstrap conflict env) == 3 ]] && pass 'managed modification returns 3' || fail 'managed modification did not return 3'
[[ "$user_hash" == "$(sha256sum "$AGENT_DIR/php-engineer.md" | cut -d' ' -f1)" ]] && pass 'managed modification preserved' || fail 'managed modification overwritten'
[[ $(run_bootstrap reset env) == 3 ]] && pass 'reset-managed does not overwrite modification' || fail 'reset-managed escaped conflict'

echo '=== Secrets ==='
rm -f "$AGENT_DIR/php-engineer.md"
grep -v '^agents/php-engineer.md|' "$MANAGED_STATE" > "$MANAGED_STATE.next" && mv "$MANAGED_STATE.next" "$MANAGED_STATE"
[[ $(run_bootstrap repair env) == 0 ]] && pass 'agent baseline restored' || fail 'agent baseline restore failed'
github_secret="$HOME_DIR/.config/daniel-harness/secrets/github/authorization"
config_hash=$(sha256sum "$CONFIG" | cut -d' ' -f1)
chmod 644 "$github_secret"
[[ $(run_bootstrap github-invalid env) == 1 ]] && pass 'invalid GitHub file reference returns 1' || fail 'invalid GitHub file reference did not return 1'
[[ "$config_hash" == "$(sha256sum "$CONFIG" | cut -d' ' -f1)" ]] && pass 'invalid GitHub secret does not mutate config' || fail 'invalid GitHub secret mutated config'
chmod 600 "$github_secret"
rm -f "$HOME_DIR/.config/daniel-harness/secrets/navi/url" "$HOME_DIR/.config/daniel-harness/secrets/navi/client-id"
DH_TEST_PROFILE=full
[[ $(run_bootstrap navi-pending env -u NAVI_MCP_URL -u NAVI_OAUTH_CLIENT_ID) == 2 ]] && pass 'missing Navi pair returns 2' || fail 'missing Navi pair did not return 2'
DH_TEST_PROFILE=alegra
[[ ! -e "$HOME_DIR/.config/daniel-harness/secrets/navi/url" && ! -e "$HOME_DIR/.config/daniel-harness/secrets/navi/client-id" ]] && pass 'missing Navi pair has no partial secret' || fail 'missing Navi pair published a partial secret'

echo '=== Recovery ==='
jq 'del(.mcp.codegraph)' "$CONFIG" > "$CONFIG.next" && mv "$CONFIG.next" "$CONFIG"
[[ $(run_bootstrap crash env DH_TEST_MODE=1 DH_HARD_CRASH_AT=after-exchange-opencodeConfig) != 0 && -f "$JOURNAL" ]] && pass 'hard crash leaves journal' || fail 'hard crash did not leave journal'
[[ $(run_bootstrap recover env) == 0 && ! -e "$JOURNAL" ]] && pass 'next bootstrap recovers journal' || fail 'next bootstrap did not recover'

echo "=== Results: $PASS passed, $FAIL failed ==="
(( FAIL == 0 ))
