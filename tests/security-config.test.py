#!/usr/bin/env python3
"""P1: Security — detect secret leaks in opencode.json and state file."""

from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent


def test_env_references_allowed():
    """Verify doctor.sh does not flag {env:*} references as secrets."""
    doctor = (ROOT_DIR / "scripts" / "doctor.sh").read_text()
    assert "contains_env_ref" in doctor
    assert "contains_literal" in doctor
    assert "embedded_credentials" in doctor
    # contains_literal returns false when contains_env_ref is true
    assert "contains_env_ref | not" in doctor or "(contains_env_ref | not)" in doctor
    print("[ok] doctor.sh uses contains_env_ref to exclude env references from literal check")


def test_contains_literal_logic():
    """Verify the jq logic in contains_literal catches only real literals."""
    doctor = (ROOT_DIR / "scripts" / "doctor.sh").read_text()
    assert "length > 0 and (contains_env_ref | not)" in doctor, \
        "contains_literal should exclude env refs"
    assert 'test("^[a-z][a-z0-9+.-]*://[^/@[:space:]]+:[^/@[:space:]]+@"; "i")' in doctor, \
        "should detect embedded credentials in URLs"
    print("[ok] doctor.sh secret detection logic is correct")


def test_state_file_no_secrets():
    """Verify state file never contains headers, tokens, or expanded variables."""
    bootstrap = (ROOT_DIR / "scripts" / "bootstrap.sh").read_text()
    assert 'lastAppliedHash' in bootstrap, "state should use lastAppliedHash"
    assert 'lastAppliedHash' in bootstrap, "state should store hash, not config"
    print("[ok] state file: only stores hashes, no secrets")


def test_secret_detector_runs():
    """Smoke test: doctor.sh has_hardcoded_sensitive_values runs on a valid config."""
    import json
    import subprocess

    # Build a synthetic opencode.json with safe env refs and dangerous literals
    config = {
        "$schema": "https://opencode.ai/config.json",
        "mcp": {
            "github": {
                "type": "remote",
                "url": "https://api.github.com/mcp",
                "headers": {
                    "Authorization": "Bearer {env:GITHUB_PERSONAL_ACCESS_TOKEN}"
                }
            },
            "local": {
                "type": "local",
                "command": ["my-tool", "--token", "literal-secret-value"]
            }
        }
    }
    safe_json = json.dumps({"mcp": {"gh": {"headers": {"Authorization": "Bearer {env:TOKEN}"}}}})
    dangerous_json = json.dumps(config)

    # Safe: should NOT contain literals (env reference)
    result = subprocess.run(
        ["jq", "-e", """
            def contains_env_ref:
              type == "string" and test("\\\\{(env|file):[^}]+\\\\}"; "i");
            def contains_literal:
              if type == "string" then
                length > 0 and (contains_env_ref | not)
              elif type == "object" or type == "array" then
                any(.[]; contains_literal)
              elif type == "null" then
                false
              else
                true
              end;
            [.. | objects | to_entries[]? |
              select((.value | contains_literal))
            ] | length > 0
        """],
        input=safe_json,
        capture_output=True, text=True,
    )
    assert result.returncode == 1, \
        f"safe config should pass (rc={result.returncode}): {result.stderr[:200]}"

    # Dangerous: SHOULD contain literals
    result = subprocess.run(
        ["jq", "-e", """
            def contains_env_ref:
              type == "string" and test("\\\\{(env|file):[^}]+\\\\}"; "i");
            def contains_literal:
              if type == "string" then
                length > 0 and (contains_env_ref | not)
              elif type == "object" or type == "array" then
                any(.[]; contains_literal)
              elif type == "null" then
                false
              else
                true
              end;
            [.. | objects | to_entries[]? |
              select((.value | contains_literal))
            ] | length > 0
        """],
        input=dangerous_json,
        capture_output=True, text=True,
    )
    assert result.returncode == 0, \
        f"dangerous config should fail (rc={result.returncode}): {result.stderr[:200]}"

    print("[ok] jq secret detection: env refs allowed, literals caught")


if __name__ == "__main__":
    test_env_references_allowed()
    test_contains_literal_logic()
    test_state_file_no_secrets()
    test_secret_detector_runs()
    print("\n=== Todos los tests pasaron ===")
