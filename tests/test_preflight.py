#!/usr/bin/env python3
"""P1: Preflight output validation with valid fixtures."""

import json
import subprocess
import sys
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent


def test_preflight_structure():
    result = subprocess.run(
        ["bash", "bin/dh", "preflight"],
        capture_output=True, text=True, timeout=5,
        cwd=str(ROOT_DIR),
    )
    assert result.returncode == 0, f"preflight failed: {result.stderr}"
    parsed = json.loads(result.stdout)

    required_keys = [
        "context", "harnessRoot", "policies", "policyFiles",
        "scope", "relationships", "readRepositories", "writeRepositories",
        "availableRelatedRepositories", "activeReadRepositories",
        "activeWriteRepositories", "scopeReason", "modelTrust",
        "mcpCapabilities", "tunnelStatus",
    ]
    for key in required_keys:
        assert key in parsed, f"preflight missing '{key}'"

    assert isinstance(parsed.get("project"), (str, type(None)))
    assert isinstance(parsed.get("readRepositories"), list)
    assert isinstance(parsed.get("writeRepositories"), list)
    assert isinstance(parsed.get("availableRelatedRepositories"), list)

    # scope starts as single-repo
    assert parsed.get("scope") == "single-repo", f"scope should be single-repo, got {parsed.get('scope')}"

    # current repo should NOT appear in availableRelatedRepositories
    current_path = parsed.get("path")
    if current_path:
        assert current_path not in parsed.get("availableRelatedRepositories", []), \
            "current repo should not be in availableRelatedRepositories"

    # modelTrust should be present
    assert parsed.get("modelTrust") is not None, "modelTrust should be set"

    # mcpCapabilities should be dict
    assert isinstance(parsed.get("mcpCapabilities"), dict)

    # tunnelStatus should be dict
    assert isinstance(parsed.get("tunnelStatus"), dict)

    print("[ok] preflight structure and defaults correct")


def test_preflight_issue_linked():
    """Preflight should include linked issue when available."""
    result = subprocess.run(
        ["bash", "bin/dh", "preflight", "--issue", "LIN-123"],
        capture_output=True, text=True, timeout=5,
        cwd=str(ROOT_DIR),
    )
    assert result.returncode == 0
    parsed = json.loads(result.stdout)
    assert "linkedIssue" in parsed or "issue" in parsed, \
        "preflight should include issue field when --issue is provided"


if __name__ == "__main__":
    test_preflight_structure()
    test_preflight_issue_linked()
    print("\n=== Todos los tests pasaron ===")
