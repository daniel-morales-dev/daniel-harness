#!/usr/bin/env python3
"""Pruebas directas del coordinador transaccional tipado."""

from __future__ import annotations

import copy
import hashlib
import json
import os
import signal
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "transaction.py"
sys.path.insert(0, str(SCRIPT.parent))

import transaction


@pytest.fixture
def workspace():
    with tempfile.TemporaryDirectory(prefix=".transaction-test-", dir=Path.home()) as name:
        base = Path(name)
        roots = {
            "opencodeDir": base / "opencode",
            "stateDir": base / "state",
            "secretsDir": base / "secrets",
            "agentsDir": base / "agents",
            "backupsDir": base / "backups",
        }
        for path in roots.values():
            path.mkdir(mode=0o700)
        yield base, roots


def sha_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def write_file(path: Path, value: bytes, mode: int = 0o600) -> None:
    path.write_bytes(value)
    path.chmod(mode)


def make_resource(
    roots: dict[str, Path],
    resource_id: str = "opencodeConfig",
    order: int = 10,
    *,
    original: bytes | None = None,
    candidate: bytes = b"candidate",
    resource_type: str = "file",
    original_target: str = "",
    candidate_target: str = "",
) -> dict:
    root_key, suffix = transaction.RESOURCE_PATHS[resource_id]
    final = roots[root_key] / suffix
    final.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    temp = final.parent / f".{final.name}.tmp.test-{order}"
    prefix = transaction.BACKUP_PREFIXES[resource_id]
    backup = roots["backupsDir"] / f"{prefix}-pre-test-{order}.bak"

    if resource_type == "symlink":
        if original is not None:
            final.symlink_to(original_target)
        temp.symlink_to(candidate_target)
        original_hash = sha_bytes(os.fsencode(original_target)) if original is not None else ""
        candidate_hash = sha_bytes(os.fsencode(candidate_target))
        expected_mode = "777"
    else:
        if original is not None:
            write_file(final, original)
        write_file(temp, candidate)
        original_hash = sha_bytes(original) if original is not None else ""
        candidate_hash = sha_bytes(candidate)
        expected_mode = "600"

    return {
        "id": resource_id,
        "applyOrder": order,
        "resourceType": resource_type,
        "finalPath": str(final),
        "tempPath": str(temp),
        "backupPath": str(backup) if original is not None else "",
        "existedBefore": original is not None,
        "candidateSha256": candidate_hash,
        "originalSha256": original_hash,
        "expectedMode": expected_mode,
        "linkTarget": original_target if original is not None and resource_type == "symlink" else "",
    }


def roots_json(roots: dict[str, Path]) -> dict[str, str]:
    return {key: str(value) for key, value in roots.items()}


def write_plan(
    base: Path,
    roots: dict[str, Path],
    resources: list[dict],
    name: str = "plan.json",
    transaction_id: str = "tx-test",
) -> tuple[Path, dict]:
    raw = {
        "planVersion": 1,
        "transactionId": transaction_id,
        "allowedRoots": roots_json(roots),
        "resources": resources,
    }
    path = base / name
    path.write_text(json.dumps(raw), encoding="utf-8")
    path.chmod(0o600)
    return path, raw


def journal_path(base: Path) -> Path:
    return base / "journal.json"


def rewrite_json(path: Path, transform) -> dict:
    raw = json.loads(path.read_text(encoding="utf-8"))
    transform(raw)
    path.write_text(json.dumps(raw), encoding="utf-8")
    path.chmod(0o600)
    return raw


def test_validation_accepts_strict_plan_and_correct_managed_state_path(workspace):
    base, roots = workspace
    resource = make_resource(roots, "managedFilesState")
    plan, _ = write_plan(base, roots, [resource], transaction_id="tx-managed-state")

    assert resource["finalPath"] == str(roots["stateDir"] / "opencode-managed.state")
    assert transaction.main(["validate-plan", "--plan", str(plan)]) == 0


def test_validation_schema_matrix(workspace):
    base, roots = workspace
    resource = make_resource(roots)
    plan, valid = write_plan(base, roots, [resource])
    cases = {
        "version": lambda value: value.update(planVersion="1"),
        "empty transaction": lambda value: value.update(transactionId=""),
        "whitespace transaction": lambda value: value.update(transactionId="  "),
        "extra field": lambda value: value.update(command="rm -rf /"),
        "roots list": lambda value: value.update(allowedRoots=list(value["allowedRoots"].values())),
        "roots missing": lambda value: value["allowedRoots"].pop("backupsDir"),
        "roots extra": lambda value: value["allowedRoots"].update(extraDir=str(base)),
        "unknown id": lambda value: value["resources"][0].update(id="externalAgent"),
        "non-positive order": lambda value: value["resources"][0].update(applyOrder=0),
        "boolean order": lambda value: value["resources"][0].update(applyOrder=True),
        "resource type": lambda value: value["resources"][0].update(resourceType="directory"),
        "boolean": lambda value: value["resources"][0].update(existedBefore=1),
        "sha256": lambda value: value["resources"][0].update(candidateSha256="ABC"),
        "mode": lambda value: value["resources"][0].update(expectedMode="68"),
        "relative path": lambda value: value["resources"][0].update(finalPath="opencode/opencode.json"),
        "traversal": lambda value: value["resources"][0].update(
            finalPath=f"{roots['opencodeDir']}/../opencode/opencode.json"
        ),
        "temporary resource": lambda value: value["resources"][0].update(finalPath="/tmp/opencode.json"),
        "wrong structural path": lambda value: value["resources"][0].update(
            finalPath=str(roots["opencodeDir"] / "other.json")
        ),
        "matching wrong root": lambda value: value["resources"][0].update(
            finalPath=str(roots["stateDir"] / "opencode.json"),
            tempPath=str(roots["stateDir"] / ".opencode.json.tmp.test"),
        ),
        "temp in another parent": lambda value: value["resources"][0].update(tempPath=str(base / "candidate")),
    }

    for label, mutate in cases.items():
        raw = copy.deepcopy(valid)
        mutate(raw)
        plan.write_text(json.dumps(raw), encoding="utf-8")
        plan.chmod(0o600)
        assert transaction.main(["validate-plan", "--plan", str(plan)]) == 1, label


@pytest.mark.parametrize(
    ("resource_id", "prefix"),
    [
        ("opencodeConfig", "opencode-config"),
        ("mcpState", "opencode-mcpstate"),
        ("managedFilesState", "opencode-managed-state"),
        ("githubAuthorization", "github-authorization"),
        ("naviUrl", "navi-url"),
        ("naviClientId", "navi-client-id"),
        ("php-engineer", "agent-php-engineer"),
    ],
)
def test_backup_allowlist_accepts_exact_resource_prefix(workspace, resource_id, prefix):
    base, roots = workspace
    resource = make_resource(roots, resource_id, original=b"old")
    plan, _ = write_plan(base, roots, [resource])

    assert Path(resource["backupPath"]).parent == roots["backupsDir"]
    assert Path(resource["backupPath"]).name.startswith(f"{prefix}-pre-")
    assert transaction.main(["validate-plan", "--plan", str(plan)]) == 0


@pytest.mark.parametrize(
    "backup",
    ["opencode-config-test.bak", "wrong-pre-safe.bak", "opencode-config-pre-safe.backup"],
)
def test_backup_allowlist_rejects_wrong_names(workspace, backup):
    base, roots = workspace
    resource = make_resource(roots, original=b"old")
    resource["backupPath"] = str(roots["backupsDir"] / backup)
    plan, _ = write_plan(base, roots, [resource])
    assert transaction.main(["validate-plan", "--plan", str(plan)]) == 1


def test_backup_allowlist_rejects_valid_name_outside_backups_root(workspace):
    base, roots = workspace
    resource = make_resource(roots, original=b"old")
    resource["backupPath"] = str(roots["opencodeDir"] / "opencode-config-pre-safe.bak")
    plan, _ = write_plan(base, roots, [resource])
    assert transaction.main(["validate-plan", "--plan", str(plan)]) == 1


def test_validation_uniqueness_matrix(workspace):
    base, roots = workspace
    first = make_resource(roots, "opencodeConfig", 10)
    second = make_resource(roots, "mcpState", 20)
    plan, valid = write_plan(base, roots, [first, second])

    for field in ("id", "applyOrder", "finalPath", "tempPath"):
        raw = copy.deepcopy(valid)
        raw["resources"][1][field] = raw["resources"][0][field]
        plan.write_text(json.dumps(raw), encoding="utf-8")
        plan.chmod(0o600)
        assert transaction.main(["validate-plan", "--plan", str(plan)]) == 1, field


def test_validation_rejects_duplicate_json_keys(workspace):
    base, roots = workspace
    resource = make_resource(roots)
    plan = base / "plan.json"
    plan.write_text(
        '{"planVersion":1,"planVersion":1,"transactionId":"tx","allowedRoots":'
        + json.dumps(roots_json(roots))
        + ',"resources":['
        + json.dumps(resource)
        + "]}",
        encoding="utf-8",
    )
    plan.chmod(0o600)
    assert transaction.main(["validate-plan", "--plan", str(plan)]) == 1


def test_validation_persisted_file_metadata(workspace, monkeypatch):
    base, roots = workspace
    resource = make_resource(roots)
    plan, _ = write_plan(base, roots, [resource])
    plan.chmod(0o644)
    assert transaction.main(["validate-plan", "--plan", str(plan)]) == 1
    plan.chmod(0o600)
    real_uid = os.getuid()
    monkeypatch.setattr(transaction.os, "getuid", lambda: real_uid + 1)
    assert transaction.main(["validate-plan", "--plan", str(plan)]) == 1


def test_validation_rejects_symlink_root(workspace):
    base, roots = workspace
    resource = make_resource(roots)
    plan, raw = write_plan(base, roots, [resource])
    real = base / "real-opencode"
    roots["opencodeDir"].rename(real)
    roots["opencodeDir"].symlink_to(real, target_is_directory=True)
    raw["allowedRoots"]["opencodeDir"] = str(roots["opencodeDir"])
    raw["resources"][0]["finalPath"] = str(roots["opencodeDir"] / "opencode.json")
    raw["resources"][0]["tempPath"] = str(roots["opencodeDir"] / ".opencode.json.tmp.test")
    plan.write_text(json.dumps(raw), encoding="utf-8")
    plan.chmod(0o600)
    assert transaction.main(["validate-plan", "--plan", str(plan)]) == 1


def test_apply_preserves_transaction_id_through_all_journal_writes(workspace):
    base, roots = workspace
    resource = make_resource(roots, candidate=b"new")
    plan, _ = write_plan(base, roots, [resource], transaction_id="tx-preserved")
    journal = journal_path(base)

    assert transaction.main(["apply", "--plan", str(plan), "--journal", str(journal)]) == 0
    raw = json.loads(journal.read_text())
    assert raw["transactionId"] == "tx-preserved"
    assert raw["journalVersion"] == 1
    assert raw["allowedRoots"] == roots_json(roots)
    assert raw["phase"] == "committed"
    assert stat.S_IMODE(journal.stat().st_mode) == 0o600
    assert transaction.main(["verify", "--journal", str(journal), "--mode", "committed"]) == 0
    assert not journal.exists()


def test_journal_validation_rejects_empty_transaction_id(workspace):
    base, roots = workspace
    resource = make_resource(roots)
    plan, _ = write_plan(base, roots, [resource])
    journal = journal_path(base)
    transaction.apply_plan(plan, journal)
    rewrite_json(journal, lambda raw: raw.update(transactionId=""))
    assert transaction.main(["recover", "--journal", str(journal)]) == 1


def test_apply_existing_and_verify_cleans_backup(workspace):
    base, roots = workspace
    resource = make_resource(roots, original=b"old", candidate=b"new")
    plan, _ = write_plan(base, roots, [resource])
    journal = journal_path(base)

    assert transaction.main(["apply", "--plan", str(plan), "--journal", str(journal)]) == 0
    assert Path(resource["finalPath"]).read_bytes() == b"new"
    assert Path(resource["backupPath"]).read_bytes() == b"old"
    assert transaction.main(["verify", "--journal", str(journal), "--mode", "committed"]) == 0
    assert not Path(resource["backupPath"]).exists()


def test_apply_conflict_preserves_changed_original(workspace):
    base, roots = workspace
    resource = make_resource(roots, original=b"old", candidate=b"new")
    plan, _ = write_plan(base, roots, [resource])
    write_file(Path(resource["finalPath"]), b"external")
    journal = journal_path(base)
    assert transaction.main(["apply", "--plan", str(plan), "--journal", str(journal)]) == 3
    assert Path(resource["finalPath"]).read_bytes() == b"external"
    assert not journal.exists()


def test_cas_verification_failure_reverses_exchange(workspace, monkeypatch):
    _base, roots = workspace
    raw = make_resource(roots, original=b"old", candidate=b"new")
    typed_roots = transaction._parse_roots(roots_json(roots))
    resource = transaction._parse_resource(raw, typed_roots, "resource", journal=False)
    real_rename = transaction._renameat2
    calls = []
    checks = 0

    def record_rename(source, destination, flags):
        calls.append(flags)
        real_rename(source, destination, flags)

    def candidate_check(state):
        nonlocal checks
        checks += 1
        return checks > 1 and transaction._matches_candidate(resource, state)

    monkeypatch.setattr(transaction, "_renameat2", record_rename)
    with pytest.raises(transaction.ManagedConflict):
        transaction._exchange_checked(
            resource.temp_path,
            resource.final_path,
            candidate_check,
            lambda state: transaction._matches_original(resource, state),
        )
    assert calls == [transaction.RENAME_EXCHANGE, transaction.RENAME_EXCHANGE]
    assert Path(raw["finalPath"]).read_bytes() == b"old"
    assert Path(raw["tempPath"]).read_bytes() == b"new"


def test_apply_and_rollback_orders(workspace, monkeypatch):
    base, roots = workspace
    later = make_resource(roots, "mcpState", 20, original=b"old-2", candidate=b"new-2")
    earlier = make_resource(roots, "opencodeConfig", 10, original=b"old-1", candidate=b"new-1")
    plan, _ = write_plan(base, roots, [later, earlier])
    journal = journal_path(base)
    applied = []
    real_apply = transaction._apply_resource

    def record_apply(resource):
        applied.append(resource.apply_order)
        real_apply(resource)

    monkeypatch.setattr(transaction, "_apply_resource", record_apply)
    transaction.apply_plan(plan, journal)
    assert applied == [10, 20]
    rewrite_json(journal, lambda raw: raw.update(phase="applying"))
    rolled_back = []
    real_rollback = transaction._rollback_resource

    def record_rollback(resource):
        rolled_back.append(resource.apply_order)
        real_rollback(resource)

    monkeypatch.setattr(transaction, "_rollback_resource", record_rollback)
    transaction.recover(journal)
    assert rolled_back == [20, 10]
    assert Path(earlier["finalPath"]).read_bytes() == b"old-1"
    assert Path(later["finalPath"]).read_bytes() == b"old-2"


def test_recovery_committed_verifies_candidate_then_clears(workspace):
    base, roots = workspace
    resource = make_resource(roots, original=b"old", candidate=b"new")
    plan, _ = write_plan(base, roots, [resource])
    journal = journal_path(base)
    transaction.apply_plan(plan, journal)
    assert transaction.main(["recover", "--journal", str(journal)]) == 0
    assert Path(resource["finalPath"]).read_bytes() == b"new"
    assert not Path(resource["backupPath"]).exists()
    assert not journal.exists()


@pytest.mark.parametrize("phase", ["applying", "committed"])
def test_recovery_preserves_unknown_external_changes(workspace, phase):
    base, roots = workspace
    resource = make_resource(roots, candidate=b"new")
    plan, _ = write_plan(base, roots, [resource])
    journal = journal_path(base)
    transaction.apply_plan(plan, journal)
    rewrite_json(journal, lambda raw: raw.update(phase=phase))
    write_file(Path(resource["finalPath"]), b"external")
    assert transaction.main(["recover", "--journal", str(journal)]) == 4
    assert Path(resource["finalPath"]).read_bytes() == b"external"
    assert journal.exists()


def test_symlink_recovery_restores_exact_target_without_following(workspace):
    base, roots = workspace
    resource = make_resource(
        roots,
        "php-engineer",
        original=b"present",
        resource_type="symlink",
        original_target="../../original-target",
        candidate_target="../../candidate-target",
    )
    plan, _ = write_plan(base, roots, [resource])
    journal = journal_path(base)
    transaction.apply_plan(plan, journal)
    assert os.readlink(resource["finalPath"]) == "../../candidate-target"
    rewrite_json(journal, lambda raw: raw.update(phase="applying"))
    assert transaction.main(["recover", "--journal", str(journal)]) == 0
    assert os.readlink(resource["finalPath"]) == "../../original-target"


def test_agent_symlink_to_file_recovery_restores_exact_target(workspace):
    base, roots = workspace
    resource = make_resource(
        roots,
        "php-engineer",
        original=b"present",
        candidate=b"managed agent",
    )
    final = Path(resource["finalPath"])
    final.unlink()
    final.symlink_to("../../legacy-agent")
    resource["resourceType"] = "symlink-to-file"
    resource["originalSha256"] = sha_bytes(b"../../legacy-agent")
    resource["linkTarget"] = "../../legacy-agent"
    candidate = Path(resource["tempPath"])
    plan, _ = write_plan(base, roots, [resource])
    journal = journal_path(base)

    transaction.apply_plan(plan, journal)
    assert Path(resource["finalPath"]).read_bytes() == b"managed agent"
    rewrite_json(journal, lambda raw: raw.update(phase="applying"))
    assert transaction.main(["recover", "--journal", str(journal)]) == 0
    assert os.readlink(resource["finalPath"]) == "../../legacy-agent"


@pytest.mark.parametrize(
    "point",
    [
        "backup-opencodeConfig",
        "journal-write",
        "before-apply-opencodeConfig",
        "after-exchange-opencodeConfig",
        "after-apply-opencodeConfig",
    ],
)
def test_controlled_failpoints_raise_technical_and_rollback(workspace, monkeypatch, point):
    base, roots = workspace
    resource = make_resource(roots, original=b"old", candidate=b"new")
    plan, _ = write_plan(base, roots, [resource], transaction_id=f"tx-{point}")
    journal = journal_path(base)
    monkeypatch.setenv("DH_TEST_MODE", "1")
    monkeypatch.setenv("DH_FAIL_AT", point)

    assert transaction.main(["apply", "--plan", str(plan), "--journal", str(journal)]) == 1
    assert Path(resource["finalPath"]).read_bytes() == b"old"
    assert not Path(resource["tempPath"]).exists()
    assert not Path(resource["backupPath"]).exists()
    raw = json.loads(journal.read_text())
    assert raw["phase"] == "rolled-back"
    assert raw["transactionId"] == f"tx-{point}"


def test_failpoints_are_ignored_outside_test_mode(workspace, monkeypatch):
    base, roots = workspace
    resource = make_resource(roots, original=b"old", candidate=b"new")
    plan, _ = write_plan(base, roots, [resource])
    journal = journal_path(base)
    monkeypatch.setenv("DH_TEST_MODE", "0")
    monkeypatch.setenv("DH_FAIL_AT", "after-exchange-opencodeConfig")
    monkeypatch.setenv("DH_HARD_CRASH_AT", "after-exchange-opencodeConfig")
    assert transaction.main(["apply", "--plan", str(plan), "--journal", str(journal)]) == 0


def test_hard_crash_after_exchange_is_recovered_by_next_process(workspace):
    base, roots = workspace
    resource = make_resource(roots, original=b"old", candidate=b"new")
    plan, _ = write_plan(base, roots, [resource], transaction_id="tx-hard-crash")
    journal = journal_path(base)
    environment = os.environ.copy()
    environment.update(
        DH_TEST_MODE="1",
        DH_HARD_CRASH_AT="after-exchange-opencodeConfig",
    )

    crashed = subprocess.run(
        [sys.executable, str(SCRIPT), "apply", "--plan", str(plan), "--journal", str(journal)],
        env=environment,
        capture_output=True,
        text=True,
    )
    assert crashed.returncode == -signal.SIGKILL
    assert Path(resource["finalPath"]).read_bytes() == b"new"
    raw = json.loads(journal.read_text())
    assert raw["phase"] == "applying"
    assert raw["resources"][0]["status"] == "applying"
    assert raw["transactionId"] == "tx-hard-crash"

    clean_environment = os.environ.copy()
    clean_environment.pop("DH_TEST_MODE", None)
    clean_environment.pop("DH_HARD_CRASH_AT", None)
    recovered = subprocess.run(
        [sys.executable, str(SCRIPT), "recover", "--journal", str(journal)],
        env=clean_environment,
        capture_output=True,
        text=True,
    )
    assert recovered.returncode == 0, recovered.stderr
    assert Path(resource["finalPath"]).read_bytes() == b"old"
    assert not Path(resource["tempPath"]).exists()
    assert not Path(resource["backupPath"]).exists()
    assert not journal.exists()


def test_apply_does_not_fallback_when_renameat2_is_unavailable(workspace, monkeypatch):
    base, roots = workspace
    resource = make_resource(roots, candidate=b"new")
    plan, _ = write_plan(base, roots, [resource])
    journal = journal_path(base)

    def unavailable(*_args):
        raise transaction.TechnicalFailure("libc renameat2 is unavailable")

    monkeypatch.setattr(transaction, "_renameat2", unavailable)
    assert transaction.main(["apply", "--plan", str(plan), "--journal", str(journal)]) == 1
    assert not Path(resource["finalPath"]).exists()
    assert json.loads(journal.read_text())["phase"] == "rolled-back"


def test_recovery_is_incomplete_without_renameat2_exchange(workspace, monkeypatch):
    base, roots = workspace
    resource = make_resource(roots, original=b"old", candidate=b"new")
    plan, _ = write_plan(base, roots, [resource])
    journal = journal_path(base)
    transaction.apply_plan(plan, journal)
    rewrite_json(journal, lambda raw: raw.update(phase="applying"))

    def unavailable(*_args):
        raise transaction.TechnicalFailure("libc renameat2 is unavailable")

    monkeypatch.setattr(transaction, "_renameat2", unavailable)
    assert transaction.main(["recover", "--journal", str(journal)]) == 4
    assert Path(resource["finalPath"]).read_bytes() == b"new"
    assert journal.exists()
