#!/usr/bin/env python3
"""Validate harness scripts and structure — bootstrap, registry, install, MCP, global rules."""

import json
import subprocess
import tempfile
from pathlib import Path

import jsonschema
import yaml


ROOT_DIR = Path(__file__).resolve().parent.parent


def test_global_agents_md_exists():
    path = ROOT_DIR / "global" / "AGENTS.md"
    assert path.exists(), "global/AGENTS.md must exist"
    content = path.read_text()
    assert "dh context" in content, "global AGENTS.md must reference dh context"
    assert "dh preflight" in content, "global AGENTS.md must reference dh preflight"
    assert "fuente única" in content, "preflight debe describirse como fuente única"


def test_install_and_uninstall_consistent():
    install = (ROOT_DIR / "scripts" / "install.sh").read_text()
    uninstall = (ROOT_DIR / "scripts" / "uninstall.sh").read_text()
    managed_links_in_install = {
        line.split()[-1]
        for line in install.splitlines()
        if "link_if_missing" in line and "AGENTS.md" in line
    }
    managed_links_in_uninstall = {
        line.split()[-1]
        for line in uninstall.splitlines()
        if "remove_managed_link" in line and "AGENTS.md" in line
    }
    assert managed_links_in_install == managed_links_in_uninstall, (
        f"install links {managed_links_in_install} != uninstall links {managed_links_in_uninstall}"
    )


def test_context_heuristic_never_alegra():
    """Verify heuristics never assign alegra-* context by language."""
    detect = (ROOT_DIR / "scripts" / "detect-context.sh").read_text()
    heuristic_section = detect.split("# 2. Heurística")[1] if "# 2. Heurística" in detect else detect
    assert "alegra-monolith" not in heuristic_section
    assert "alegra-microservice" not in heuristic_section
    assert "contexto=generic-php" in detect
    assert "contexto=generic-typescript" in detect
    assert "contexto=generic-go" in detect
    detect_bin = (ROOT_DIR / "bin" / "dh").read_text()
    assert "contexto=generic-php" in detect_bin
    assert "contexto=generic-typescript" in detect_bin
    assert "contexto=generic-go" in detect_bin


def test_manifest_mcp_local_has_type():
    manifest = yaml.safe_load((ROOT_DIR / "bootstrap" / "manifest.yaml").read_text())
    mcps = manifest.get("mcp_servers", {})
    for name, cfg in mcps.items():
        t = cfg.get("type", "")
        if "command" in cfg:
            assert t == "local", f"MCP {name}: local servers must have type: local"
        elif t == "remote":
            assert t == "remote", f"MCP {name}: remote servers must have type: remote"
        else:
            if t == "remote":
                continue  # remote without command is fine for manifest (bootstrap skips it)
            assert False, f"MCP {name}: unrecognized type '{t}'"


def test_bootstrap_generates_local_mcp_with_type():
    """Verify bootstrap.sh jq line for local MCPs includes type: local."""
    bootstrap = (ROOT_DIR / "scripts" / "bootstrap.sh").read_text()
    assert 'type: "local"' in bootstrap or 'type: \\"local\\"' in bootstrap or 'type: local' in bootstrap


def test_bootstrap_skips_remote_mcp():
    """Verify bootstrap.sh skips remote MCPs without url and configures those with url."""
    bootstrap = (ROOT_DIR / "scripts" / "bootstrap.sh").read_text()
    assert "remotos sin url" in bootstrap
    assert 'type: "remote"' in bootstrap or 'type: remote' in bootstrap


def test_bootstrap_nvm_uses_direct_curl():
    """Verify NVM install uses direct curl, not broken parse_value pipe."""
    bootstrap = (ROOT_DIR / "scripts" / "bootstrap.sh").read_text()
    assert "user_tools" not in bootstrap.split("Instalando NVM")[1].split("\n")[0]


def test_bootstrap_plugin_uses_singular():
    """Verify bootstrap.sh uses .plugin (singular), not .plugins."""
    bootstrap = (ROOT_DIR / "scripts" / "bootstrap.sh").read_text()
    assert '(.plugin // [])' in bootstrap
    assert '(.plugins // [])' not in bootstrap


def test_registry_default_includes_relationships():
    """Verify registry default creation includes relationships field."""
    with tempfile.NamedTemporaryFile(mode="w", suffix=".yaml", delete=False) as f:
        f.write('version: "1"\nfamilies: []\nrelationships: []\n')
        tmp = f.name

    schema = json.loads((ROOT_DIR / "schemas" / "project-registry.schema.json").read_text())
    data = yaml.safe_load(Path(tmp).read_text())
    jsonschema.validate(data, schema)
    Path(tmp).unlink()


def test_registry_rejects_missing_relationships():
    """Verify registry without relationships fails schema validation."""
    schema = json.loads((ROOT_DIR / "schemas" / "project-registry.schema.json").read_text())
    invalid = {"version": "1", "families": []}
    try:
        jsonschema.validate(invalid, schema)
        assert False, "registry without relationships should fail validation"
    except jsonschema.ValidationError:
        pass


def test_registry_rejects_repository_property():
    """Verify project entries with 'repository' fail schema validation."""
    schema = json.loads((ROOT_DIR / "schemas" / "project-registry.schema.json").read_text())
    invalid = {
        "version": "1",
        "families": [
            {
                "id": "test",
                "contexts": ["freelance"],
                "projects": [
                    {
                        "id": "test-project",
                        "path": "/tmp/test",
                        "context": "freelance",
                        "rules": [],
                        "git": {
                            "askBeforeBranch": True,
                            "commit": "ask",
                            "push": "ask",
                            "deploy": "ask",
                        },
                        "repository": "https://github.com/user/repo.git",
                    }
                ],
            }
        ],
        "relationships": [],
    }
    try:
        jsonschema.validate(invalid, schema)
        assert False, "project entry with 'repository' should fail validation"
    except jsonschema.ValidationError:
        pass


def test_agents_no_write_permission():
    """Verify no agent uses undocumented 'write' permission."""
    for agent_md in (ROOT_DIR / "agents").glob("*.md"):
        content = agent_md.read_text()
        assert "write: allow" not in content, f"{agent_md.name} still has write: allow"


def test_code_reviewer_readonly():
    """Verify code-reviewer has restricted permissions with wildcard deny."""
    content = (ROOT_DIR / "agents" / "code-reviewer.md").read_text()
    assert "edit: deny" in content
    assert '"*": deny' in content
    assert "git diff" in content
    assert "git status" in content

def test_writers_bash_is_ask():
    """Verify alegra-microservice-engineer and alegra-microservice-test-engineer use bash: ask, not allow."""
    senior = (ROOT_DIR / "agents" / "alegra-microservice-engineer.md").read_text()
    test = (ROOT_DIR / "agents" / "alegra-microservice-test-engineer.md").read_text()
    assert "bash: ask" in senior
    assert "bash: ask" in test
    assert "bash: allow" not in senior
    assert "bash: allow" not in test

def test_agents_specialized():
    """Verify agents are specialized (alegra-microservice-* names, reduced size)."""
    senior = (ROOT_DIR / "agents" / "alegra-microservice-engineer.md").read_text()
    test = (ROOT_DIR / "agents" / "alegra-microservice-test-engineer.md").read_text()
    assert "alegra-microservice-engineer" in senior
    assert "alegra-microservice-test-engineer" in test
    assert "preflight" in senior.lower()
    assert len(senior) < 5000
    assert len(test) < 5000


def test_dh_cli_contexts_use_alegra_prefix():
    """Verify dh-cli.md uses alegra-monolith/alegra-microservice context names."""
    doc = (ROOT_DIR / "docs" / "dh-cli.md").read_text()
    assert "alegra-monolith" in doc
    assert "alegra-microservice" in doc
    assert "generic-php" in doc
    assert "generic-typescript" in doc


def test_mcp_status_uninitialized():
    """Verify mcp_status in bin/dh handles missing MCP section."""
    content = (ROOT_DIR / "bin" / "dh").read_text()
    assert "mcp_root=\"\"" in content or "local mcp_root=\"\"" in content or '[[ -z "$mcp_root" ]]' in content


def test_uninstall_removes_global_link():
    """Verify uninstall.sh removes the global AGENTS.md link."""
    content = (ROOT_DIR / "scripts" / "uninstall.sh").read_text()
    assert "global/AGENTS.md" in content


def test_shellcheck():
    """Run ShellCheck on all shell scripts if available."""
    import shutil

    if not shutil.which("shellcheck"):
        print("  [-] ShellCheck no instalado, saltando")
        return

    scripts = [
        ROOT_DIR / "bin" / "dh",
        ROOT_DIR / "scripts" / "bootstrap.sh",
        ROOT_DIR / "scripts" / "install.sh",
        ROOT_DIR / "scripts" / "uninstall.sh",
        ROOT_DIR / "scripts" / "doctor.sh",
        ROOT_DIR / "scripts" / "detect-context.sh",
    ]
    for script in scripts:
        if not script.exists():
            print(f"  [-] {script.name} no existe, saltando")
            continue
        result = subprocess.run(
            ["shellcheck", "-e", "SC1091,SC2154,SC2317", str(script)],
            capture_output=True, text=True
        )
        assert result.returncode == 0, (
            f"ShellCheck falló en {script.name}:\n{result.stdout}\n{result.stderr}"
        )
        print(f"  [ok] ShellCheck: {script.name}")


if __name__ == "__main__":
    test_global_agents_md_exists()
    print("[ok] global/AGENTS.md existe y tiene contenido")

    test_install_and_uninstall_consistent()
    print("[ok] install/uninstall consistentes")

    test_bootstrap_plugin_uses_singular()
    print("[ok] bootstrap usa .plugin singular")

    test_context_heuristic_never_alegra()
    print("[ok] heurística nunca asigna alegra-* por lenguaje")

    test_manifest_mcp_local_has_type()
    print("[ok] manifest MCPs locales tienen type")

    test_bootstrap_generates_local_mcp_with_type()
    print("[ok] bootstrap genera MCP locales con type")

    test_bootstrap_skips_remote_mcp()
    print("[ok] bootstrap salta MCPs remotos")

    test_bootstrap_nvm_uses_direct_curl()
    print("[ok] bootstrap NVM usa curl directo")

    test_registry_default_includes_relationships()
    print("[ok] registry default incluye relationships")

    test_registry_rejects_missing_relationships()
    print("[ok] registry sin relationships es rechazado")

    test_registry_rejects_repository_property()
    print("[ok] registry con repository es rechazado")

    # Verify migration-parity-reviewer exists and is read-only
    parity = (ROOT_DIR / "agents" / "migration-parity-reviewer.md").read_text()
    assert "edit: deny" in parity
    assert '"*": deny' in parity

    # Verify migration-gap command uses agent frontmatter, not allowed-tools
    cmd = (ROOT_DIR / "commands" / "migration-gap-analysis.md").read_text()
    assert "agent: migration-parity-reviewer" in cmd
    assert "allowed-tools" not in cmd
    assert "--apply" not in cmd
    assert "mutation" not in cmd.lower() or "no muta" in cmd.lower()

    test_agents_no_write_permission()
    print("[ok] agents sin write permission")

    test_code_reviewer_readonly()
    print("[ok] code-reviewer readonly con wildcard deny")

    test_writers_bash_is_ask()
    print("[ok] alegra-microservice-engineer y alegra-microservice-test-engineer con bash: ask")

    test_dh_cli_contexts_use_alegra_prefix()
    print("[ok] dh-cli.md contextos actualizados")

    test_mcp_status_uninitialized()
    print("[ok] mcp_status maneja sección MCP faltante")

    def test_preflight_output():
        result = subprocess.run(
            ["bash", "bin/dh", "preflight"],
            capture_output=True, text=True, timeout=5
        )
        parsed = json.loads(result.stdout)
        assert "context" in parsed
        assert "harnessRoot" in parsed
        assert "policies" in parsed
        assert "scope" in parsed
        assert "relationships" in parsed
        assert isinstance(parsed.get("project"), (str, type(None)))
        assert isinstance(parsed.get("family"), (str, type(None)))
        assert isinstance(parsed.get("path"), (str, type(None)))
        assert result.returncode == 0

    test_preflight_output()
    print("[ok] dh preflight produce JSON válido")

    test_uninstall_removes_global_link()
    print("[ok] uninstall.sh elimina enlace global")

    test_shellcheck()
    print("[ok] ShellCheck")

    print("\n=== Todos los tests pasaron ===")
