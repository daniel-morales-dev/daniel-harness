#!/usr/bin/env python3
"""P0: Validate generated opencode.json against official OpenCode schema."""

import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent
SCHEMA_FILE = ROOT_DIR / "tests" / "fixtures" / "opencode-config.schema.json"
HARNESS_MANIFEST = ROOT_DIR / "bootstrap" / "manifest.yaml"
BOOTSTRAP = ROOT_DIR / "scripts" / "bootstrap.sh"


def load_schema():
    with open(SCHEMA_FILE) as f:
        return json.load(f)


def setup_stubs(base):
    stubs = base / "stubs"
    stubs.mkdir(parents=True)
    sudo_script = """#!/bin/bash
if [[ "$1" == "-n" && "$2" == "true" ]]; then exit 0; fi
if [[ "$1" == "-v" ]]; then exit 0; fi
exec "$@"
"""
    (stubs / "sudo").write_text(sudo_script)
    (stubs / "sudo").chmod(0o755)
    for stub in ("apt-get", "dpkg", "curl", "opencode", "gentle-ai", "codegraph",
                 "engram", "rtk", "dh", "node", "npm", "aws", "gh", "unzip"):
        (stubs / stub).write_text("#!/bin/bash\nexit 0\n")
        (stubs / stub).chmod(0o755)
    (stubs / "node").write_text("#!/bin/bash\necho v24.0.0\n")
    (stubs / "node").chmod(0o755)
    # opencode stub that reports connected
    oc_stub = """#!/bin/bash
if [[ "$1" == "mcp" && "$2" == "debug" ]]; then echo "connected"; exit 0; fi
exit 0
"""
    (stubs / "opencode").write_text(oc_stub)
    (stubs / "opencode").chmod(0o755)
    return stubs


def run_bootstrap(home_dir, stubs, profile="core"):
    env = {
        "PATH": f"{stubs}:{home_dir}/.nvm/versions/node/v24.0.0/bin:/usr/bin:/bin",
        "HOME": str(home_dir),
        "XDG_CONFIG_HOME": str(home_dir / ".config"),
        "NVM_DIR": str(home_dir / ".nvm"),
    }
    # Setup nvm and config
    (home_dir / ".nvm").mkdir(parents=True)
    (home_dir / ".nvm" / "nvm.sh").write_text("nvm() { :; }\n")
    (home_dir / ".nvm" / "versions" / "node" / "v24.0.0" / "bin").mkdir(parents=True)
    (home_dir / ".nvm" / "versions" / "node" / "v24.0.0" / "bin" / "node").write_text("#!/bin/bash\necho v24.0.0\n")
    (home_dir / ".nvm" / "versions" / "node" / "v24.0.0" / "bin" / "node").chmod(0o755)
    (home_dir / ".config" / "daniel-harness" / "secrets" / "tunnels").mkdir(parents=True)
    (home_dir / ".config" / "daniel-harness" / "config.yaml").write_text('version: "1"\n')

    result = subprocess.run(
        ["bash", str(BOOTSTRAP), "--profile", profile],
        env=env,
        capture_output=True,
        text=True,
        timeout=60,
    )
    oc_file = home_dir / ".config" / "opencode" / "opencode.json"
    if not oc_file.exists():
        print(f"STDOUT: {result.stdout[-2000:]}")
        print(f"STDERR: {result.stderr[-2000:]}")
        raise RuntimeError(f"opencode.json not created for profile {profile}")
    return oc_file


def validate_mcp_semantics(config, profile_name):
    """Check profile-specific MCP semantics."""
    mcps = config.get("mcp", {})
    errors = []

    # Local MCPs must have array command
    for name, mcp in mcps.items():
        if mcp.get("type") == "local":
            cmd = mcp.get("command")
            if not isinstance(cmd, list) or len(cmd) == 0:
                errors.append(f"{profile_name}: {name} local command must be non-empty array")

    if profile_name == "alegra":
        # GitHub: oauth == false, specific headers
        gh = mcps.get("github", {})
        if gh.get("oauth") is not False:
            errors.append("alegra: github oauth must be false")
        auth = gh.get("headers", {}).get("Authorization", "")
        if "GITHUB_PERSONAL_ACCESS_TOKEN" not in auth:
            errors.append("alegra: github Authorization must reference GITHUB_PERSONAL_ACCESS_TOKEN")
        if "X-MCP-Toolsets" not in gh.get("headers", {}):
            errors.append("alegra: github must have X-MCP-Toolsets header")

        # Linear: oauth is object
        lin = mcps.get("linear", {})
        if not isinstance(lin.get("oauth"), dict):
            errors.append("alegra: linear oauth must be an object")

        # Wiki: oauth is object
        wiki = mcps.get("wiki-alegra", {})
        if not isinstance(wiki.get("oauth"), dict):
            errors.append("alegra: wiki-alegra oauth must be an object")

        # Context7: no oauth field
        ctx = mcps.get("context7", {})
        if "oauth" in ctx:
            errors.append("alegra: context7 should not have oauth field")

    return errors


def test_all_profiles():
    schema = load_schema()
    import jsonschema

    profiles = ["core", "alegra"]

    for profile in profiles:
        with tempfile.TemporaryDirectory(prefix=f"oc-schema-{profile}-") as tmp:
            base = Path(tmp)
            stubs = setup_stubs(base)
            try:
                oc_file = run_bootstrap(base, stubs, profile)
            except RuntimeError as e:
                print(f"FAIL {profile}: {e}")
                sys.exit(1)

            config = json.loads(oc_file.read_text())

            # Validate against schema
            try:
                jsonschema.validate(config, schema)
                print(f"[ok] {profile}: schema validation passed")
            except jsonschema.ValidationError as e:
                print(f"[FAIL] {profile}: schema validation failed: {e.message}")
                for p in e.path: print(f"  path: {p}")
                sys.exit(1)

            # Validate MCP semantics
            sem_errors = validate_mcp_semantics(config, profile)
            for err in sem_errors:
                print(f"[FAIL] {profile}: {err}")
            if sem_errors:
                sys.exit(1)
            print(f"[ok] {profile}: MCP semantics passed")


if __name__ == "__main__":
    test_all_profiles()
    print("\n=== Todos los tests pasaron ===")
