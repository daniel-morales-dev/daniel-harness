#!/usr/bin/env bash
# Gate de release: OpenCode real debe resolver referencias {file:...}.
set -euo pipefail
umask 077

TMP_DIR=$(mktemp -d)
SERVER_PID=""
PASS=0
FAIL=0

cleanup() {
  [[ -z "$SERVER_PID" ]] || kill "$SERVER_PID" 2>/dev/null || :
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

pass() { printf '  [ok] %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf '  [FAIL] %s\n' "$*"; FAIL=$((FAIL + 1)); }

command -v opencode >/dev/null 2>&1 || {
  printf '[FAIL] opencode real no está disponible\n' >&2
  exit 1
}

HOME="$TMP_DIR/home"
export HOME
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$TMP_DIR/data"
export XDG_STATE_HOME="$TMP_DIR/state"
export XDG_CACHE_HOME="$TMP_DIR/cache"
export OPENCODE_DISABLE_PROJECT_CONFIG=1
export OPENCODE_DISABLE_DEFAULT_PLUGINS=1
export OPENCODE_DISABLE_EXTERNAL_SKILLS=1
export OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1

SECRETS="$HOME/.config/daniel-harness/secrets/runtime-smoke"
CONFIG="$TMP_DIR/opencode.json"
REQUESTS="$TMP_DIR/requests.log"
mkdir -p "$SECRETS"
chmod 700 "$HOME/.config" "$HOME/.config/daniel-harness" "$HOME/.config/daniel-harness/secrets" "$SECRETS"

printf '%s' 'http://127.0.0.1:18766/first' > "$SECRETS/url"
printf '%s' 'Bearer runtime-smoke-first' > "$SECRETS/authorization"
printf '%s' 'runtime-smoke-client-first' > "$SECRETS/client-id"
chmod 600 "$SECRETS/url" "$SECRETS/authorization" "$SECRETS/client-id"

cat > "$CONFIG" <<EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "mcp": {
    "runtime-smoke": {
      "type": "remote",
      "url": "{file:$SECRETS/url}",
      "headers": {"Authorization": "{file:$SECRETS/authorization}"},
      "oauth": {"clientId": "{file:$SECRETS/client-id}"}
    }
  }
}
EOF

export OPENCODE_CONFIG="$CONFIG"

python3 - "$REQUESTS" <<'PY' &
import http.server
import sys

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        with open(sys.argv[1], "a", encoding="utf-8") as output:
            output.write(f"{self.path}\t{self.headers.get('Authorization', '')}\n")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2024-11-05","capabilities":{},"serverInfo":{"name":"runtime-smoke","version":"1"}}}')
    do_POST = do_GET
    def log_message(self, *_):
        pass

http.server.ThreadingHTTPServer(("127.0.0.1", 18766), Handler).serve_forever()
PY
SERVER_PID=$!

if opencode debug config --pure | jq -e \
  --rawfile url "$SECRETS/url" \
  --rawfile authorization "$SECRETS/authorization" \
  --rawfile client_id "$SECRETS/client-id" \
  '.mcp["runtime-smoke"].url == $url and .mcp["runtime-smoke"].headers.Authorization == $authorization and .mcp["runtime-smoke"].oauth.clientId == $client_id' \
  >/dev/null; then
  pass 'debug config resuelve Authorization, URL y oauth.clientId'
else
  fail 'debug config no resolvió las tres referencias'
fi

set +e
opencode mcp list --pure >/dev/null 2>&1
first_rc=$?
set -e
if [[ "$first_rc" == 0 ]] && grep -Fqx '/first	Bearer runtime-smoke-first' "$REQUESTS"; then
  pass 'Authorization y URL se resolvieron en runtime'
else
  fail 'Authorization y URL no llegaron al servidor local'
fi

printf '%s' 'http://127.0.0.1:18766/second' > "$SECRETS/url"
printf '%s' 'Bearer runtime-smoke-second' > "$SECRETS/authorization"

set +e
opencode mcp list --pure >/dev/null 2>&1
second_rc=$?
set -e
if [[ "$second_rc" == 0 ]] && grep -Fqx '/second	Bearer runtime-smoke-second' "$REQUESTS"; then
  pass 'Authorization y URL se releen sin reescribir configuración'
else
  fail 'no se observó recarga dinámica de Authorization y URL'
fi

printf '\n=== Resultados: %d pasaron, %d fallaron ===\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
