#!/usr/bin/env python3
"""P0: Validate generated opencode.json against official OpenCode schema."""

import json
import subprocess
import tempfile
from pathlib import Path

import pytest

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
    # OpenCode capabilities required by the production compatibility gate.
    oc_stub = """#!/bin/bash
if [[ "$1" == "--version" ]]; then echo "opencode 1.18.18"; exit 0; fi
if [[ "$1" == "agent" && "$2" == "list" ]]; then
  if [[ "$3" == "--help" ]]; then exit 0; fi
  printf '%s\\n' alegra-microservice-engineer alegra-microservice-test-engineer alegra-code-reviewer php-engineer migration-parity-reviewer
  exit 0
fi
if [[ "$1" == "mcp" && ( "$2" == "--help" || "$2" == "auth" || ( "$2" == "debug" && "$3" == "--help" ) ) ]]; then exit 0; fi
if [[ "$1" == "mcp" && "$2" == "debug" ]]; then echo "connected"; exit 0; fi
if [[ "$1" == "debug" && "$2" == "config" && "$3" == "--help" ]]; then exit 0; fi
exit 0
"""
    (stubs / "opencode").write_text(oc_stub)
    (stubs / "opencode").chmod(0o755)
    gentle_stub = """#!/bin/bash
case "$1" in
  --version|version) echo "gentle-ai 2.3.0" ;;
  skill-registry|sync) exit 0 ;;
  doctor) echo "Status:  healthy" ;;
esac
exit 0
"""
    (stubs / "gentle-ai").write_text(gentle_stub)
    (stubs / "gentle-ai").chmod(0o755)
    return stubs


def run_bootstrap(home_dir, stubs, profile="core"):
    env = {
        "PATH": f"{stubs}:{home_dir}/.nvm/versions/node/v24.0.0/bin:/usr/bin:/bin",
        "HOME": str(home_dir),
        "XDG_CONFIG_HOME": str(home_dir / ".config"),
            "NVM_DIR": str(home_dir / ".nvm"),
            "DH_TEST_MODE": "1",
            "DH_TRANSACTION_ALLOW_TMP": "1",
        }
    # Setup nvm and config
    (home_dir / ".nvm").mkdir(parents=True)
    (home_dir / ".nvm" / "nvm.sh").write_text("nvm() { :; }\n")
    (home_dir / ".nvm" / "versions" / "node" / "v24.0.0" / "bin").mkdir(parents=True)
    (home_dir / ".nvm" / "versions" / "node" / "v24.0.0" / "bin" / "node").write_text("#!/bin/bash\necho v24.0.0\n")
    (home_dir / ".nvm" / "versions" / "node" / "v24.0.0" / "bin" / "node").chmod(0o755)
    (home_dir / ".config" / "daniel-harness" / "secrets" / "tunnels").mkdir(parents=True)
    (home_dir / ".config" / "daniel-harness" / "config.yaml").write_text('version: "1"\nmodels:\n  - id: default\n    trust: trusted\n    allowArbitraryShell: false\n    allowedCapabilities: []\n')

    result = subprocess.run(
        ["bash", str(BOOTSTRAP), "--profile", profile],
        env=env,
        capture_output=True,
        text=True,
        timeout=60,
    )
    oc_file = home_dir / ".config" / "opencode" / "opencode.json"
    journal_file = home_dir / ".config" / "daniel-harness" / "state" / ".bootstrap-journal.json"
    if not oc_file.exists():
        detail = [
            f"opencode.json not created (profile={profile}, rc={result.returncode})",
            "--- STDOUT (last 100 lines) ---",
        ]
        detail.extend(result.stdout.splitlines()[-100:])
        detail.append("--- STDERR (last 100 lines) ---")
        detail.extend(result.stderr.splitlines()[-100:])
        detail.append("--- HOME ---")
        detail.append(str(home_dir))
        detail.append(f"--- PROFILE: {profile} ---")
        if journal_file.exists():
            try:
                journal = json.loads(journal_file.read_text())
                resources = journal.get("resources", [])
                detail.append(
                    "--- JOURNAL SUMMARY --- "
                    f"phase={journal.get('phase')} resources="
                    + ", ".join(
                        f"{item.get('id')}:{item.get('status')}:{item.get('type')}:"
                        f"final={bool(item.get('finalPath'))}:candidate={bool(item.get('tempPath'))}"
                        for item in resources
                    )
                )
            except (OSError, ValueError):
                detail.append("--- JOURNAL SUMMARY --- unreadable")
        pytest.fail("\n".join(detail))
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
        if "GITHUB_PERSONAL_ACCESS_TOKEN" not in auth and "{file:" not in auth:
            errors.append("alegra: github Authorization must reference GITHUB_PERSONAL_ACCESS_TOKEN or {file:...}")
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


def test_profile_core():
    _run_profile_test("core")


def test_profile_alegra():
    _run_profile_test("alegra")


def _run_profile_test(profile):
    schema = load_schema()
    import jsonschema

    with tempfile.TemporaryDirectory(prefix=f"oc-schema-{profile}-") as tmp:
        base = Path(tmp)
        stubs = setup_stubs(base)
        oc_file = run_bootstrap(base, stubs, profile)

        assert oc_file.exists(), f"opencode.json not created for profile {profile}"
        config = json.loads(oc_file.read_text())

        try:
            jsonschema.validate(config, schema)
        except jsonschema.ValidationError as e:
            lines = oc_file.read_text().splitlines()
            detail = "\n".join(lines[:50])
            pytest.fail(
                f"{profile}: schema validation failed: {e.message}\n"
                f"  path: {' → '.join(str(p) for p in e.path)}\n"
                f"  config (first 50 lines):\n{detail}"
            )

        sem_errors = validate_mcp_semantics(config, profile)
        if sem_errors:
            pytest.fail(
                f"{profile}: MCP semantics errors:\n" +
                "\n".join(f"  - {e}" for e in sem_errors)
            )
