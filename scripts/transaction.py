#!/usr/bin/env python3
"""Coordinador transaccional tipado para recursos persistidos."""

from __future__ import annotations

import argparse
import ctypes
import errno
import hashlib
import json
import os
import re
import signal
import stat
import sys
import tempfile
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Any, NoReturn, Sequence


EXIT_TECHNICAL = 1
EXIT_CONFLICT = 3
EXIT_INCOMPLETE_RECOVERY = 4
AT_FDCWD = -100
RENAME_NOREPLACE = 1
RENAME_EXCHANGE = 2
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
MODE_RE = re.compile(r"^(?:0)?[0-7]{3}$")
ROOT_KEYS = ("opencodeDir", "stateDir", "secretsDir", "agentsDir", "backupsDir")
SAFE_BACKUP_RE = r"[A-Za-z0-9][A-Za-z0-9_-]*"


class Phase(str, Enum):
    PREPARING = "preparing"
    CANDIDATES_READY = "candidates-ready"
    APPLYING = "applying"
    COMMITTED = "committed"
    ROLLING_BACK = "rolling-back"
    ROLLED_BACK = "rolled-back"


class ResourceStatus(str, Enum):
    PREPARED = "prepared"
    APPLYING = "applying"
    APPLIED = "applied"
    ROLLING_BACK = "rolling-back"
    ROLLED_BACK = "rolled-back"


class TransactionError(Exception):
    """Base para errores controlados del coordinador."""


class InvalidTransaction(TransactionError):
    pass


class ManagedConflict(TransactionError):
    pass


class TechnicalFailure(TransactionError):
    pass


class IncompleteRecovery(TransactionError):
    pass


_TRIGGERED_FAILPOINTS: set[str] = set()


def _test_hook(name: str, *, hard_crash: bool = False) -> None:
    if os.environ.get("DH_TEST_MODE") != "1":
        return
    if hard_crash and os.environ.get("DH_HARD_CRASH_AT") == name:
        os.kill(os.getpid(), signal.SIGKILL)
    if os.environ.get("DH_FAIL_AT") == name and name not in _TRIGGERED_FAILPOINTS:
        _TRIGGERED_FAILPOINTS.add(name)
        raise TechnicalFailure(f"controlled failpoint: {name}")


KNOWN_AGENTS = frozenset(
    {
        "alegra-code-reviewer",
        "alegra-microservice-engineer",
        "alegra-microservice-test-engineer",
        "migration-parity-reviewer",
        "php-engineer",
    }
)
RESOURCE_PATHS = {
    "opencodeConfig": ("opencodeDir", Path("opencode.json")),
    "mcpState": ("stateDir", Path("opencode-managed.json")),
    "managedFilesState": ("stateDir", Path("opencode-managed.state")),
    "githubAuthorization": ("secretsDir", Path("github/authorization")),
    "naviUrl": ("secretsDir", Path("navi/url")),
    "naviClientId": ("secretsDir", Path("navi/client-id")),
    **{agent: ("agentsDir", Path(f"{agent}.md")) for agent in KNOWN_AGENTS},
}
BACKUP_PREFIXES = {
    "opencodeConfig": "opencode-config",
    "mcpState": "opencode-mcpstate",
    "managedFilesState": "opencode-managed-state",
    "githubAuthorization": "github-authorization",
    "naviUrl": "navi-url",
    "naviClientId": "navi-client-id",
    **{agent: f"agent-{agent}" for agent in KNOWN_AGENTS},
}


@dataclass(frozen=True)
class AllowedRoots:
    opencode_dir: Path
    state_dir: Path
    secrets_dir: Path
    agents_dir: Path
    backups_dir: Path

    def by_key(self, key: str) -> Path:
        return {
            "opencodeDir": self.opencode_dir,
            "stateDir": self.state_dir,
            "secretsDir": self.secrets_dir,
            "agentsDir": self.agents_dir,
            "backupsDir": self.backups_dir,
        }[key]

    def as_json(self) -> dict[str, str]:
        return {key: str(self.by_key(key)) for key in ROOT_KEYS}


@dataclass(frozen=True)
class Resource:
    id: str
    apply_order: int
    resource_type: str
    final_path: Path
    temp_path: Path
    backup_path: Path | None
    existed_before: bool
    candidate_sha256: str
    original_sha256: str | None
    expected_mode: str
    link_target: str | None
    status: ResourceStatus = ResourceStatus.PREPARED


@dataclass(frozen=True)
class Plan:
    transaction_id: str
    allowed_roots: AllowedRoots
    resources: tuple[Resource, ...]


@dataclass(frozen=True)
class Journal:
    transaction_id: str
    phase: Phase
    allowed_roots: AllowedRoots
    resources: tuple[Resource, ...]


@dataclass(frozen=True)
class FileState:
    kind: str
    sha256: str
    mode: str
    uid: int
    link_target: str | None = None


def _fail(message: str) -> NoReturn:
    raise InvalidTransaction(message)


def _strict_keys(value: dict[str, Any], expected: set[str], context: str) -> None:
    actual = set(value)
    if actual != expected:
        missing = sorted(expected - actual)
        extra = sorted(actual - expected)
        _fail(f"{context}: invalid fields (missing={missing}, extra={extra})")


def _json_no_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            _fail(f"duplicate JSON field: {key}")
        result[key] = value
    return result


def _is_under_tmp(path: Path) -> bool:
    return path == Path("/tmp") or Path("/tmp") in path.parents


def _test_allows_tmp() -> bool:
    return os.environ.get("DH_TEST_MODE") == "1" or os.environ.get("DH_TRANSACTION_ALLOW_TMP") == "1"


def _validate_absolute_path(raw: Any, context: str, *, allow_empty: bool = False) -> Path | None:
    if allow_empty and raw == "":
        return None
    if not isinstance(raw, str) or not raw or "\x00" in raw:
        _fail(f"{context}: path must be a non-empty string")
    path = Path(raw)
    if not path.is_absolute() or ".." in path.parts:
        _fail(f"{context}: path must be absolute without traversal")
    if _is_under_tmp(path) and not _test_allows_tmp():
        _fail(f"{context}: persisted resources under /tmp are forbidden")
    return path


def _validate_canonical_directory(path: Path, context: str) -> None:
    try:
        resolved = path.resolve(strict=True)
        metadata = path.lstat()
    except OSError as exc:
        _fail(f"{context}: directory is not accessible: {exc.strerror}")
    if resolved != path or not stat.S_ISDIR(metadata.st_mode):
        _fail(f"{context}: directory must be canonical and contain no symlink")
    if metadata.st_uid != os.getuid():
        _fail(f"{context}: directory owner must be the current uid")


def _validate_parent(path: Path, context: str) -> None:
    _validate_canonical_directory(path.parent, f"{context} parent")


def _validate_persisted_file(path: Path, context: str) -> None:
    if not path.is_absolute() or ".." in path.parts or (_is_under_tmp(path) and not _test_allows_tmp()):
        _fail(f"{context}: persisted file must be absolute, traversal-free and outside /tmp")
    _validate_parent(path, context)
    try:
        metadata = path.lstat()
    except OSError as exc:
        _fail(f"{context}: cannot stat file: {exc.strerror}")
    if not stat.S_ISREG(metadata.st_mode):
        _fail(f"{context}: must be a regular non-symlink file")
    if metadata.st_uid != os.getuid():
        _fail(f"{context}: owner must be the current uid")
    if stat.S_IMODE(metadata.st_mode) != 0o600:
        _fail(f"{context}: mode must be 600")


def _load_json(path: Path, context: str) -> Any:
    _validate_persisted_file(path, context)
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(path, flags)
        with os.fdopen(descriptor, "r", encoding="utf-8") as stream:
            return json.load(stream, object_pairs_hook=_json_no_duplicates)
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        _fail(f"{context}: invalid JSON: {exc}")


def _parse_roots(raw: Any) -> AllowedRoots:
    if not isinstance(raw, dict):
        _fail("allowedRoots must be an object")
    _strict_keys(raw, set(ROOT_KEYS), "allowedRoots")
    roots: dict[str, Path] = {}
    for key in ROOT_KEYS:
        root = _validate_absolute_path(raw[key], f"allowedRoots.{key}")
        assert root is not None
        _validate_canonical_directory(root, f"allowedRoots.{key}")
        roots[key] = root
    if len(set(roots.values())) != len(roots):
        _fail("allowedRoots must be unique")
    return AllowedRoots(
        opencode_dir=roots["opencodeDir"],
        state_dir=roots["stateDir"],
        secrets_dir=roots["secretsDir"],
        agents_dir=roots["agentsDir"],
        backups_dir=roots["backupsDir"],
    )


def _parse_hash(raw: Any, context: str, *, allow_empty: bool = False) -> str | None:
    if allow_empty and raw == "":
        return None
    if not isinstance(raw, str) or not SHA256_RE.fullmatch(raw):
        _fail(f"{context}: expected lowercase SHA256")
    return raw


def _parse_mode(raw: Any, context: str) -> str:
    if not isinstance(raw, str) or not MODE_RE.fullmatch(raw):
        _fail(f"{context}: invalid octal mode")
    return raw[-3:]


def _authorized_final(resource_id: str, final_path: Path, roots: AllowedRoots) -> bool:
    mapping = RESOURCE_PATHS.get(resource_id)
    if mapping is None:
        return False
    root_key, suffix = mapping
    return final_path == roots.by_key(root_key) / suffix


def _recognized_backup(resource_id: str, backup_path: Path, roots: AllowedRoots) -> bool:
    if backup_path.parent != roots.backups_dir:
        return False
    prefix = re.escape(BACKUP_PREFIXES[resource_id])
    pattern = rf"^{prefix}-pre-{SAFE_BACKUP_RE}\.bak$"
    return re.fullmatch(pattern, backup_path.name) is not None


def _parse_resource(raw: Any, roots: AllowedRoots, context: str, *, journal: bool) -> Resource:
    if not isinstance(raw, dict):
        _fail(f"{context}: resource must be an object")
    fields = {
        "id",
        "applyOrder",
        "resourceType",
        "finalPath",
        "tempPath",
        "backupPath",
        "existedBefore",
        "candidateSha256",
        "originalSha256",
        "expectedMode",
        "linkTarget",
    }
    if journal:
        fields.add("status")
    _strict_keys(raw, fields, context)

    resource_id = raw["id"]
    if not isinstance(resource_id, str) or resource_id not in RESOURCE_PATHS:
        _fail(f"{context}.id: unrecognized managed resource")
    apply_order = raw["applyOrder"]
    if isinstance(apply_order, bool) or not isinstance(apply_order, int) or apply_order <= 0:
        _fail(f"{context}.applyOrder: expected a positive integer")
    resource_type = raw["resourceType"]
    if resource_type not in ("file", "symlink", "symlink-to-file"):
        _fail(f"{context}.resourceType: expected file, symlink or symlink-to-file")
    final_path = _validate_absolute_path(raw["finalPath"], f"{context}.finalPath")
    temp_path = _validate_absolute_path(raw["tempPath"], f"{context}.tempPath")
    backup_path = _validate_absolute_path(raw["backupPath"], f"{context}.backupPath", allow_empty=True)
    assert final_path is not None and temp_path is not None
    if not _authorized_final(resource_id, final_path, roots):
        _fail(f"{context}: id/finalPath is outside the structural allowlist")
    if temp_path.parent != final_path.parent or temp_path == final_path:
        _fail(f"{context}.tempPath: candidate must be a sibling of finalPath")
    _validate_parent(final_path, f"{context}.finalPath")
    _validate_parent(temp_path, f"{context}.tempPath")

    existed_before = raw["existedBefore"]
    if not isinstance(existed_before, bool):
        _fail(f"{context}.existedBefore: expected boolean")
    candidate_hash = _parse_hash(raw["candidateSha256"], f"{context}.candidateSha256")
    original_hash = _parse_hash(raw["originalSha256"], f"{context}.originalSha256", allow_empty=True)
    mode = _parse_mode(raw["expectedMode"], f"{context}.expectedMode")
    link_target = raw["linkTarget"]
    if not isinstance(link_target, str):
        _fail(f"{context}.linkTarget: expected string")

    if existed_before:
        if original_hash is None or backup_path is None:
            _fail(f"{context}: existing resource requires originalSha256 and backupPath")
        if not _recognized_backup(resource_id, backup_path, roots):
            _fail(f"{context}.backupPath: unrecognized direct-child backup name")
        _validate_parent(backup_path, f"{context}.backupPath")
        if resource_type in ("symlink", "symlink-to-file") and not link_target:
            _fail(f"{context}.linkTarget: existing symlink requires its exact target")
    elif original_hash is not None or backup_path is not None or link_target:
        _fail(f"{context}: absent resource must have empty original, backup and link target")
    if resource_type == "file" and link_target:
        _fail(f"{context}.linkTarget: files must use an empty link target")
    if resource_type == "symlink-to-file" and resource_id not in KNOWN_AGENTS:
        _fail(f"{context}.resourceType: symlink-to-file is limited to managed agents")

    try:
        status = ResourceStatus(raw["status"]) if journal else ResourceStatus.PREPARED
    except (ValueError, TypeError):
        _fail(f"{context}.status: unrecognized status")
    assert candidate_hash is not None
    return Resource(
        id=resource_id,
        apply_order=apply_order,
        resource_type=resource_type,
        final_path=final_path,
        temp_path=temp_path,
        backup_path=backup_path,
        existed_before=existed_before,
        candidate_sha256=candidate_hash,
        original_sha256=original_hash,
        expected_mode=mode,
        link_target=link_target or None,
        status=status,
    )


def _validate_resource_uniqueness(resources: tuple[Resource, ...]) -> None:
    for label, values in (
        ("id", [resource.id for resource in resources]),
        ("applyOrder", [resource.apply_order for resource in resources]),
        ("finalPath", [resource.final_path for resource in resources]),
        ("tempPath", [resource.temp_path for resource in resources]),
    ):
        if len(values) != len(set(values)):
            _fail(f"resources: duplicate {label}")
    all_paths = [resource.final_path for resource in resources] + [resource.temp_path for resource in resources]
    all_paths += [resource.backup_path for resource in resources if resource.backup_path]
    if len(all_paths) != len(set(all_paths)):
        _fail("resources: final, temp and backup paths must be globally unique")


def _parse_transaction_id(raw: Any, context: str) -> str:
    if not isinstance(raw, str) or not raw.strip():
        _fail(f"{context}: transactionId must be a non-empty string")
    return raw


def load_plan(path: Path) -> Plan:
    raw = _load_json(path, "plan")
    if not isinstance(raw, dict):
        _fail("plan: expected object")
    _strict_keys(raw, {"planVersion", "transactionId", "allowedRoots", "resources"}, "plan")
    if raw["planVersion"] != 1 or isinstance(raw["planVersion"], bool):
        _fail("planVersion must be integer 1")
    transaction_id = _parse_transaction_id(raw["transactionId"], "plan")
    roots = _parse_roots(raw["allowedRoots"])
    if not isinstance(raw["resources"], list) or not raw["resources"]:
        _fail("resources must be a non-empty array")
    resources = tuple(
        _parse_resource(item, roots, f"resources[{index}]", journal=False)
        for index, item in enumerate(raw["resources"])
    )
    _validate_resource_uniqueness(resources)
    return Plan(transaction_id, roots, resources)


def load_journal(path: Path) -> Journal:
    raw = _load_json(path, "journal")
    if not isinstance(raw, dict):
        _fail("journal: expected object")
    _strict_keys(raw, {"journalVersion", "transactionId", "phase", "allowedRoots", "resources"}, "journal")
    if raw["journalVersion"] != 1 or isinstance(raw["journalVersion"], bool):
        _fail("journalVersion must be integer 1")
    transaction_id = _parse_transaction_id(raw["transactionId"], "journal")
    try:
        phase = Phase(raw["phase"])
    except (ValueError, TypeError):
        _fail("journal phase is unrecognized")
    roots = _parse_roots(raw["allowedRoots"])
    if not isinstance(raw["resources"], list) or not raw["resources"]:
        _fail("journal resources must be a non-empty array")
    resources = tuple(
        _parse_resource(item, roots, f"resources[{index}]", journal=True)
        for index, item in enumerate(raw["resources"])
    )
    _validate_resource_uniqueness(resources)
    return Journal(transaction_id, phase, roots, resources)


def _hash_file(path: Path) -> str:
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(path, flags)
    digest = hashlib.sha256()
    with os.fdopen(descriptor, "rb") as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def _state(path: Path) -> FileState | None:
    try:
        metadata = path.lstat()
    except FileNotFoundError:
        return None
    except OSError as exc:
        raise TechnicalFailure(f"cannot inspect managed resource: {exc.strerror}") from exc
    mode = f"{stat.S_IMODE(metadata.st_mode):03o}"
    if stat.S_ISLNK(metadata.st_mode):
        target = os.readlink(path)
        digest = hashlib.sha256(os.fsencode(target)).hexdigest()
        return FileState("symlink", digest, mode, metadata.st_uid, target)
    if stat.S_ISREG(metadata.st_mode):
        try:
            digest = _hash_file(path)
        except OSError as exc:
            raise TechnicalFailure(f"cannot hash managed resource: {exc.strerror}") from exc
        return FileState("file", digest, mode, metadata.st_uid)
    raise TechnicalFailure("managed resource is neither a regular file nor a symlink")


def _matches_candidate(resource: Resource, state: FileState | None) -> bool:
    expected_kind = "file" if resource.resource_type == "symlink-to-file" else resource.resource_type
    return bool(
        state
        and state.kind == expected_kind
        and state.sha256 == resource.candidate_sha256
        and state.uid == os.getuid()
        and (state.kind == "symlink" or state.mode == resource.expected_mode)
    )


def _matches_original(resource: Resource, state: FileState | None) -> bool:
    if not resource.existed_before:
        return state is None
    return bool(
        state
        and state.kind == ("symlink" if resource.resource_type == "symlink-to-file" else resource.resource_type)
        and state.sha256 == resource.original_sha256
        and state.uid == os.getuid()
        and (state.kind != "symlink" or state.link_target == resource.link_target)
    )


def validate_plan_state(plan: Plan) -> None:
    for resource in plan.resources:
        candidate = _state(resource.temp_path)
        if not _matches_candidate(resource, candidate):
            raise ManagedConflict(f"candidate state mismatch for {resource.id}")
        current = _state(resource.final_path)
        if not _matches_original(resource, current):
            raise ManagedConflict(f"original state mismatch for {resource.id}")
        if resource.backup_path and _state(resource.backup_path) is not None:
            raise ManagedConflict(f"backup already exists for {resource.id}")


def _renameat2(source: Path, destination: Path, flags: int) -> None:
    """Usa el símbolo libc; los números de syscall cambian entre arquitecturas."""
    try:
        function = ctypes.CDLL(None, use_errno=True).renameat2
    except (AttributeError, OSError) as exc:
        raise TechnicalFailure("libc renameat2 is unavailable") from exc
    function.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
    function.restype = ctypes.c_int
    result = function(AT_FDCWD, os.fsencode(source), AT_FDCWD, os.fsencode(destination), flags)
    if result != 0:
        number = ctypes.get_errno()
        if number == errno.EEXIST:
            raise ManagedConflict("CAS destination already exists")
        raise TechnicalFailure(f"renameat2 failed: {os.strerror(number)}")


def _fsync_directory(path: Path) -> None:
    try:
        descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
        try:
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
    except OSError as exc:
        raise TechnicalFailure(f"directory fsync failed: {exc.strerror}") from exc


def _fsync_regular(path: Path) -> None:
    state = _state(path)
    if state is None or state.kind == "symlink":
        return
    try:
        descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
        try:
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
    except OSError as exc:
        raise TechnicalFailure(f"file fsync failed: {exc.strerror}") from exc


def _atomic_write_json(path: Path, value: dict[str, Any]) -> None:
    _validate_parent(path, "journal")
    descriptor = -1
    temporary = ""
    try:
        descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.tmp.", dir=path.parent)
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            descriptor = -1
            json.dump(value, stream, sort_keys=True, separators=(",", ":"))
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        temporary = ""
        os.chmod(path, 0o600, follow_symlinks=False)
        _fsync_regular(path)
        _fsync_directory(path.parent)
    except OSError as exc:
        raise TechnicalFailure(f"durable journal write failed: {exc.strerror}") from exc
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        if temporary:
            try:
                os.unlink(temporary)
            except FileNotFoundError:
                pass


def _resource_dict(resource: Resource) -> dict[str, Any]:
    return {
        "id": resource.id,
        "applyOrder": resource.apply_order,
        "resourceType": resource.resource_type,
        "finalPath": str(resource.final_path),
        "tempPath": str(resource.temp_path),
        "backupPath": str(resource.backup_path) if resource.backup_path else "",
        "existedBefore": resource.existed_before,
        "candidateSha256": resource.candidate_sha256,
        "originalSha256": resource.original_sha256 or "",
        "expectedMode": resource.expected_mode,
        "linkTarget": resource.link_target or "",
        "status": resource.status.value,
    }


def _journal_dict(journal: Journal) -> dict[str, Any]:
    return {
        "journalVersion": 1,
        "transactionId": journal.transaction_id,
        "phase": journal.phase.value,
        "allowedRoots": journal.allowed_roots.as_json(),
        "resources": [_resource_dict(resource) for resource in journal.resources],
    }


def _write_journal(path: Path, journal: Journal, *, failpoint: bool = True) -> None:
    if failpoint:
        _test_hook("journal-write")
    _atomic_write_json(path, _journal_dict(journal))


def _replace_resource(journal: Journal, resource_id: str, status: ResourceStatus) -> Journal:
    resources = tuple(
        Resource(**{**resource.__dict__, "status": status}) if resource.id == resource_id else resource
        for resource in journal.resources
    )
    return Journal(journal.transaction_id, journal.phase, journal.allowed_roots, resources)


def _replace_phase(journal: Journal, phase: Phase) -> Journal:
    return Journal(journal.transaction_id, phase, journal.allowed_roots, journal.resources)


def _durable_unlink(path: Path) -> None:
    try:
        os.unlink(path)
        _fsync_directory(path.parent)
        try:
            path.lstat()
        except FileNotFoundError:
            return
        raise TechnicalFailure("durable unlink verification failed")
    except FileNotFoundError:
        return
    except OSError as exc:
        raise TechnicalFailure(f"durable unlink failed: {exc.strerror}") from exc


def clear_journal(path: Path) -> None:
    _validate_persisted_file(path, "journal")
    _durable_unlink(path)


def _copy_backup(resource: Resource) -> None:
    if not resource.backup_path:
        return
    source_state = _state(resource.final_path)
    if not _matches_original(resource, source_state):
        raise ManagedConflict(f"original changed before backup for {resource.id}")
    temporary = resource.backup_path.parent / f".{resource.backup_path.name}.tmp.{os.getpid()}.{os.urandom(6).hex()}"
    try:
        if resource.resource_type in ("symlink", "symlink-to-file"):
            os.symlink(resource.link_target or "", temporary)
        else:
            source = os.open(resource.final_path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
            target = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            try:
                while data := os.read(source, 1024 * 1024):
                    pending = memoryview(data)
                    while pending:
                        written = os.write(target, pending)
                        if written <= 0:
                            raise OSError(errno.EIO, "short backup write")
                        pending = pending[written:]
                os.fchmod(target, 0o600)
                os.fsync(target)
            finally:
                os.close(source)
                os.close(target)
        _renameat2(temporary, resource.backup_path, RENAME_NOREPLACE)
        _fsync_regular(resource.backup_path)
        _fsync_directory(resource.backup_path.parent)
        if not _matches_original(resource, _state(resource.backup_path)):
            raise TechnicalFailure(f"backup verification failed for {resource.id}")
    finally:
        if _state(temporary) is not None:
            _durable_unlink(temporary)


def _exchange_checked(
    source: Path,
    destination: Path,
    source_matches: Any,
    destination_matches: Any,
) -> None:
    _renameat2(source, destination, RENAME_EXCHANGE)
    _fsync_regular(source)
    _fsync_regular(destination)
    _fsync_directory(destination.parent)
    if source_matches(_state(destination)) and destination_matches(_state(source)):
        return
    # Revertir el intercambio es la única salida no destructiva ante una carrera.
    try:
        _renameat2(source, destination, RENAME_EXCHANGE)
        _fsync_directory(destination.parent)
    except TransactionError as exc:
        raise IncompleteRecovery("CAS verification failed and reverse exchange failed") from exc
    if not source_matches(_state(source)) or not destination_matches(_state(destination)):
        raise IncompleteRecovery("CAS reverse exchange did not restore both resources")
    raise ManagedConflict("CAS post-exchange verification failed")


def _apply_resource(resource: Resource) -> None:
    candidate = _state(resource.temp_path)
    if not _matches_candidate(resource, candidate):
        raise ManagedConflict(f"candidate changed before apply for {resource.id}")
    current = _state(resource.final_path)
    if resource.existed_before:
        if not _matches_original(resource, current):
            raise ManagedConflict(f"original changed before apply for {resource.id}")
        _exchange_checked(
            resource.temp_path,
            resource.final_path,
            lambda state: _matches_candidate(resource, state),
            lambda state: _matches_original(resource, state),
        )
        _test_hook(f"after-exchange-{resource.id}", hard_crash=True)
        _durable_unlink(resource.temp_path)
    else:
        if current is not None:
            raise ManagedConflict(f"destination appeared before apply for {resource.id}")
        _renameat2(resource.temp_path, resource.final_path, RENAME_NOREPLACE)
        _fsync_regular(resource.final_path)
        _fsync_directory(resource.final_path.parent)
        _test_hook(f"after-exchange-{resource.id}", hard_crash=True)
        if not _matches_candidate(resource, _state(resource.final_path)):
            raise IncompleteRecovery(f"candidate verification failed after apply for {resource.id}")


def _cleanup_known(path: Path, predicate: Any) -> None:
    state = _state(path)
    if state is None:
        return
    if not predicate(state):
        raise IncompleteRecovery("cleanup path contains unknown external state")
    _durable_unlink(path)


def _rollback_resource(resource: Resource) -> None:
    current = _state(resource.final_path)
    if _matches_original(resource, current):
        _cleanup_known(resource.temp_path, lambda state: _matches_candidate(resource, state))
        if resource.backup_path:
            _cleanup_known(resource.backup_path, lambda state: _matches_original(resource, state))
        return
    if not _matches_candidate(resource, current):
        raise IncompleteRecovery(f"unknown external state preserved for {resource.id}")
    if not resource.existed_before:
        _durable_unlink(resource.final_path)
        _cleanup_known(resource.temp_path, lambda state: _matches_candidate(resource, state))
        return
    assert resource.backup_path is not None
    backup = _state(resource.backup_path)
    if not _matches_original(resource, backup):
        raise IncompleteRecovery(f"verified backup unavailable for {resource.id}")
    _exchange_checked(
        resource.backup_path,
        resource.final_path,
        lambda state: _matches_original(resource, state),
        lambda state: _matches_candidate(resource, state),
    )
    _durable_unlink(resource.backup_path)
    _cleanup_known(resource.temp_path, lambda state: _matches_original(resource, state))


def _verify_state(journal: Journal, mode: str) -> None:
    if mode == "committed":
        if journal.phase is not Phase.COMMITTED:
            raise ManagedConflict("journal is not committed")
        for resource in journal.resources:
            if not _matches_candidate(resource, _state(resource.final_path)):
                raise ManagedConflict(f"committed state mismatch for {resource.id}")
    else:
        if journal.phase is not Phase.ROLLED_BACK:
            raise ManagedConflict("journal is not rolled back")
        for resource in journal.resources:
            if not _matches_original(resource, _state(resource.final_path)):
                raise ManagedConflict(f"rolled-back state mismatch for {resource.id}")
            if _state(resource.temp_path) is not None:
                raise ManagedConflict(f"rolled-back candidate residue for {resource.id}")
            if resource.backup_path and _state(resource.backup_path) is not None:
                raise ManagedConflict(f"rolled-back backup residue for {resource.id}")


def _cleanup_committed(journal: Journal) -> None:
    for resource in journal.resources:
        if resource.backup_path:
            _cleanup_known(resource.backup_path, lambda state, item=resource: _matches_original(item, state))


def rollback_journal(path: Path) -> None:
    journal = load_journal(path)
    journal = _replace_phase(journal, Phase.ROLLING_BACK)
    _write_journal(path, journal)
    failures: list[str] = []
    for resource in sorted(journal.resources, key=lambda item: item.apply_order, reverse=True):
        journal = _replace_resource(journal, resource.id, ResourceStatus.ROLLING_BACK)
        _write_journal(path, journal)
        try:
            _rollback_resource(resource)
        except TransactionError as exc:
            failures.append(str(exc))
            continue
        journal = _replace_resource(journal, resource.id, ResourceStatus.ROLLED_BACK)
        _write_journal(path, journal)
    if failures:
        raise IncompleteRecovery("; ".join(failures))
    journal = _replace_phase(journal, Phase.ROLLED_BACK)
    _write_journal(path, journal)
    _verify_state(journal, "rolled-back")


def apply_plan(plan_path: Path, journal_path: Path) -> None:
    _TRIGGERED_FAILPOINTS.clear()
    if _state(journal_path) is not None:
        raise TechnicalFailure("journal already exists; recover it before apply")
    _validate_parent(journal_path, "journal")
    plan = load_plan(plan_path)
    validate_plan_state(plan)
    journal = Journal(plan.transaction_id, Phase.PREPARING, plan.allowed_roots, plan.resources)
    _write_journal(journal_path, journal, failpoint=False)
    try:
        for resource in journal.resources:
            _test_hook(f"backup-{resource.id}")
            _copy_backup(resource)
        journal = _replace_phase(journal, Phase.CANDIDATES_READY)
        _write_journal(journal_path, journal)
        journal = _replace_phase(journal, Phase.APPLYING)
        _write_journal(journal_path, journal)
        for resource in sorted(journal.resources, key=lambda item: item.apply_order):
            journal = _replace_resource(journal, resource.id, ResourceStatus.APPLYING)
            _write_journal(journal_path, journal)
            _test_hook(f"before-apply-{resource.id}", hard_crash=True)
            _apply_resource(resource)
            _test_hook(f"after-apply-{resource.id}", hard_crash=True)
            journal = _replace_resource(journal, resource.id, ResourceStatus.APPLIED)
            _write_journal(journal_path, journal)
        journal = _replace_phase(journal, Phase.COMMITTED)
        _write_journal(journal_path, journal)
        _verify_state(journal, "committed")
    except TransactionError as original:
        try:
            rollback_journal(journal_path)
        except TransactionError as recovery_error:
            raise IncompleteRecovery(str(recovery_error)) from original
        raise


def recover(journal_path: Path) -> None:
    journal = load_journal(journal_path)
    if journal.phase is Phase.COMMITTED:
        try:
            _verify_state(journal, "committed")
        except ManagedConflict as exc:
            raise IncompleteRecovery(str(exc)) from exc
        _cleanup_committed(journal)
        clear_journal(journal_path)
        return
    if journal.phase is Phase.ROLLED_BACK:
        try:
            _verify_state(journal, "rolled-back")
        except ManagedConflict as exc:
            raise IncompleteRecovery(str(exc)) from exc
        clear_journal(journal_path)
        return
    rollback_journal(journal_path)
    clear_journal(journal_path)


def verify(journal_path: Path, mode: str) -> None:
    journal = load_journal(journal_path)
    _verify_state(journal, mode)
    if mode == "committed":
        _cleanup_committed(journal)
    clear_journal(journal_path)


class Parser(argparse.ArgumentParser):
    def error(self, message: str) -> NoReturn:
        self.print_usage(sys.stderr)
        self.exit(EXIT_TECHNICAL, f"error: {message}\n")


def _parser() -> argparse.ArgumentParser:
    parser = Parser(description="Typed durable transaction coordinator")
    commands = parser.add_subparsers(dest="command", required=True)
    validate = commands.add_parser("validate-plan")
    validate.add_argument("--plan", type=Path, required=True)
    apply = commands.add_parser("apply")
    apply.add_argument("--plan", type=Path, required=True)
    apply.add_argument("--journal", type=Path, required=True)
    recover_parser = commands.add_parser("recover")
    recover_parser.add_argument("--journal", type=Path, required=True)
    verify_parser = commands.add_parser("verify")
    verify_parser.add_argument("--journal", type=Path, required=True)
    verify_parser.add_argument("--mode", choices=("committed", "rolled-back"), required=True)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    arguments = _parser().parse_args(argv)
    try:
        if arguments.command == "validate-plan":
            validate_plan_state(load_plan(arguments.plan))
        elif arguments.command == "apply":
            apply_plan(arguments.plan, arguments.journal)
        elif arguments.command == "recover":
            recover(arguments.journal)
        else:
            verify(arguments.journal, arguments.mode)
        return 0
    except IncompleteRecovery as exc:
        print(f"error: {exc}", file=sys.stderr)
        return EXIT_INCOMPLETE_RECOVERY
    except ManagedConflict as exc:
        print(f"error: {exc}", file=sys.stderr)
        return EXIT_CONFLICT
    except (InvalidTransaction, TechnicalFailure) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return EXIT_TECHNICAL


if __name__ == "__main__":
    sys.exit(main())
