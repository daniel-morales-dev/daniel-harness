# tests/helpers/nvm-stub.sh
# Helper compartido para crear un stub de curl que instala NVM correctamente.
# Uso: source tests/helpers/nvm-stub.sh && create_nvm_curl_stub "$STUBS"
# produce "$STUBS/curl" que reconoce -o <archivo> y escribe el instalador alli.

create_nvm_curl_stub() {
  local stubs=$1
  cat > "$stubs/curl" <<'CURLSCRIPT'
#!/bin/bash
outfile=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--output) outfile="$2"; shift 2 ;;
    -fsSL|--fail|--silent|--show-error|--location|-s|-S|-L|-f) shift ;;
    http*|https*) shift ;;
    *) shift ;;
  esac
done
if [[ -z "${outfile:-}" ]]; then
  echo "[nvm-stub] FATAL: curl llamado sin -o <archivo>" >&2
  exit 1
fi
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
exit 0
CURLSCRIPT
  chmod +x "$stubs/curl"
}
