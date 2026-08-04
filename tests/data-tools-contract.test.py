#!/usr/bin/env python3
"""Verify custom tools follow OpenCode contract.

- Filename determines tool name (underscore-delimited)
- No input/output fields (use args/description/execute)
- All tools export via tool() helper
"""
import re
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent
TOOLS_DIR = ROOT_DIR / "tools"

EXPECTED_TOOLS = [
    "dh_mysql_query",
    "dh_mongodb_query",
    "dh_dynamodb_read",
    "dh_dynamodb_write",
    "dh_object_storage_read",
]

FORBIDDEN_PATTERNS = [
    (r'^\s+input[:\s]', "input field (use args instead)"),
    (r'^\s+output[:\s]', "output field (not needed)"),
    (r"name:\s*['\"]dh_", "name field in export (filename determines name)"),
]

REQUIRED_PATTERNS = [
    (r'import \{ tool \} from "@opencode-ai/plugin"', "import tool from @opencode-ai/plugin"),
    (r"export default tool\(\{", "export default tool({"),
    (r"description:", "description field"),
    (r"args:", "args field"),
    (r"async execute\(", "async execute function"),
]


def test_all_tool_files_exist():
    """Verify every expected tool file exists with underscore name."""
    for name in EXPECTED_TOOLS:
        path = TOOLS_DIR / f"{name}.ts"
        assert path.exists(), f"Missing tool file: {path.name}"


def test_tool_name_from_filename():
    """Verify each tool filename stem matches the expected tool name."""
    for name in EXPECTED_TOOLS:
        path = TOOLS_DIR / f"{name}.ts"
        assert path.exists(), f"Missing {name}"
        stem = path.stem
        assert stem == name, f"Filename stem '{stem}' != expected '{name}'"


def test_no_forbidden_patterns():
    """Verify no tool uses input, output, or name in export."""
    for name in EXPECTED_TOOLS:
        path = TOOLS_DIR / f"{name}.ts"
        content = path.read_text()
        for pattern, desc in FORBIDDEN_PATTERNS:
            match = re.search(pattern, content, re.MULTILINE)
            assert not match, f"{name}.ts: {desc} (matched: '{match.group(0).strip()}')"


def test_required_patterns():
    """Verify each tool has required OpenCode contract fields."""
    for name in EXPECTED_TOOLS:
        path = TOOLS_DIR / f"{name}.ts"
        content = path.read_text()
        for pattern, desc in REQUIRED_PATTERNS:
            assert re.search(pattern, content), f"{name}.ts: missing {desc}"


def test_ts_syntax():
    """Verify each tool file has valid TypeScript structure via regex."""
    import re
    for name in EXPECTED_TOOLS:
        path = TOOLS_DIR / f"{name}.ts"
        content = path.read_text()
        assert len(content) > 50, f"{name}.ts is too short ({len(content)} chars)"
        assert content.count("export default") == 1, f"{name}.ts must have exactly one export default"
        assert content.count("async execute") == 1, f"{name}.ts must have exactly one async execute"


def test_unexpected_tool_files():
    """Warn if there are tool files not in the expected list."""
    for f in sorted(TOOLS_DIR.glob("dh_*.ts")):
        assert f.stem in EXPECTED_TOOLS, f"Unexpected tool file: {f.name}"


# --- Agent permission tests ---


def test_data_access_agent_exists():
    path = ROOT_DIR / "agents" / "data-access.md"
    assert path.exists(), "agents/data-access.md missing"


def test_data_access_agent_mode():
    content = (ROOT_DIR / "agents" / "data-access.md").read_text()
    assert "mode: subagent" in content, "data-access must be mode: subagent"


def test_data_access_agent_permission_exists():
    content = (ROOT_DIR / "agents" / "data-access.md").read_text()
    assert "permission:" in content, "data-access must have permission section"


def test_data_access_agent_wildcard_deny():
    content = (ROOT_DIR / "agents" / "data-access.md").read_text()
    assert '"*": deny' in content, "data-access must have wildcard deny"

ALLOWED_TOOLS_IN_AGENT = ["dh_mysql_query", "dh_mongodb_query", "dh_dynamodb_read", "dh_dynamodb_write", "dh_object_storage_read"]

def test_data_access_agent_allowed_tools():
    content = (ROOT_DIR / "agents" / "data-access.md").read_text()
    for tool in ALLOWED_TOOLS_IN_AGENT:
        assert f"{tool}: allow" in content, f"data-access missing allow for {tool}"


def test_data_access_agent_no_extra_allowed_tools():
    content = (ROOT_DIR / "agents" / "data-access.md").read_text()
    import re
    allowed = re.findall(r'(\w+): allow', content)
    tool_allows = [t for t in allowed if t.startswith("dh_")]
    assert len(tool_allows) == 5, f"data-access should allow exactly 5 tools, got {len(tool_allows)}: {tool_allows}"


if __name__ == "__main__":
    test_all_tool_files_exist()
    print("[ok] all tool files exist")
    test_tool_name_from_filename()
    print("[ok] tool names match filenames")
    test_no_forbidden_patterns()
    print("[ok] no forbidden patterns (input/output/name)")
    test_required_patterns()
    print("[ok] required patterns present")
    test_unexpected_tool_files()
    print("[ok] no unexpected tool files")
    test_ts_syntax()
    print("[ok] TypeScript syntax check")
    test_data_access_agent_exists()
    print("[ok] data-access agent exists")
    test_data_access_agent_mode()
    print("[ok] data-access mode: subagent")
    test_data_access_agent_permission_exists()
    print("[ok] data-access permission section")
    test_data_access_agent_wildcard_deny()
    print("[ok] data-access wildcard deny")
    test_data_access_agent_allowed_tools()
    print("[ok] data-access 5 tools allow")
    test_data_access_agent_no_extra_allowed_tools()
    print("[ok] data-access no extra tools")
    print("\n=== Todos los tests pasaron ===")
