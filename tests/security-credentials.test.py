#!/usr/bin/env python3
"""Tests for dh_data/security.py — credential resolution."""
import os
import stat
import tempfile
from pathlib import Path

from dh_data.security import resolve_credentials, CredentialError

ROOT = Path(__file__).resolve().parent.parent

def setup_module():
    global _tmpdir, _harness
    _tmpdir = Path(tempfile.mkdtemp())
    _harness = _tmpdir / "harness"
    (_harness / "secrets" / "mysql").mkdir(parents=True, mode=0o700)
    (_harness / "secrets" / "mongodb").mkdir(parents=True, mode=0o700)


def teardown_module():
    import shutil
    shutil.rmtree(str(_tmpdir), ignore_errors=True)


def create_cred(path, content="password=test", mode=0o600):
    full = _harness / path
    full.parent.mkdir(parents=True, exist_ok=True)
    full.write_text(content)
    os.chmod(str(full), mode)
    return full


def test_valid_file():
    create_cred("secrets/mysql/prod.cnf")
    val = resolve_credentials("secrets/mysql/prod.cnf", _harness)
    assert val == "password=test"


def test_env_var():
    os.environ["_DH_TEST_VAR"] = "secret-value"
    val = resolve_credentials("env://_DH_TEST_VAR", _harness)
    assert val == "secret-value"


def test_env_var_empty_name():
    try:
        resolve_credentials("env://", _harness)
        assert False, "should raise"
    except CredentialError:
        pass


def test_env_var_not_set():
    try:
        resolve_credentials("env://_DH_NONEXISTENT", _harness)
        assert False, "should raise"
    except CredentialError:
        pass


def test_traversal_rejected():
    try:
        resolve_credentials("secrets/../opencode.json", _harness)
        assert False, "should raise"
    except CredentialError:
        pass


def test_symlink_to_outside_rejected():
    outside = _tmpdir / "outside.txt"
    outside.write_text("leak")
    link = _harness / "secrets" / "mysql" / "outside.cnf"
    link.parent.mkdir(parents=True, exist_ok=True)
    link.symlink_to(outside)
    os.chmod(str(link), 0o600)
    try:
        resolve_credentials("secrets/mysql/outside.cnf", _harness)
        assert False, "should raise"
    except CredentialError:
        pass


def test_symlink_rejected():
    target = _tmpdir / "real.txt"
    target.write_text("real-content")
    link = _harness / "secrets" / "mysql" / "link.cnf"
    link.symlink_to(target)
    try:
        resolve_credentials("secrets/mysql/link.cnf", _harness)
        assert False, "should raise"
    except CredentialError:
        pass


def test_world_readable_rejected():
    create_cred("secrets/mysql/world.cnf", mode=0o644)
    try:
        resolve_credentials("secrets/mysql/world.cnf", _harness)
        assert False, "should raise"
    except CredentialError:
        pass


def test_group_readable_rejected():
    create_cred("secrets/mysql/group.cnf", mode=0o640)
    try:
        resolve_credentials("secrets/mysql/group.cnf", _harness)
        assert False, "should raise"
    except CredentialError:
        pass


def test_aws_profile_unsupported():
    try:
        resolve_credentials("aws-profile://prod", _harness)
        assert False, "should raise"
    except CredentialError as e:
        assert "not yet implemented" in str(e)


def test_keychain_unsupported():
    try:
        resolve_credentials("keychain://mykey", _harness)
        assert False, "should raise"
    except CredentialError as e:
        assert "not yet implemented" in str(e)


def test_empty_ref():
    try:
        resolve_credentials("", _harness)
        assert False, "should raise"
    except CredentialError:
        pass


def test_error_does_not_leak_path():
    create_cred("secrets/mysql/hidden.cnf", mode=0o644)
    try:
        resolve_credentials("secrets/mysql/hidden.cnf", _harness)
        assert False, "should raise"
    except CredentialError as e:
        msg = str(e)
        assert "hidden" not in msg
        assert "/tmp/" not in msg


def test_mongodb_cred():
    create_cred("secrets/mongodb/uri.txt", content="MONGODB_URI=mongodb://localhost:27017")
    val = resolve_credentials("secrets/mongodb/uri.txt", _harness)
    assert "MONGODB_URI" in val


if __name__ == "__main__":
    setup_module()
    test_valid_file()
    print("[ok] valid file credential")
    test_env_var()
    print("[ok] env var credential")
    test_env_var_empty_name()
    print("[ok] env var empty name")
    test_env_var_not_set()
    print("[ok] env var not set")
    test_traversal_rejected()
    print("[ok] traversal rejected")
    test_symlink_to_outside_rejected()
    print("[ok] symlink to outside rejected")
    test_symlink_rejected()
    print("[ok] symlink rejected")
    test_world_readable_rejected()
    print("[ok] world readable rejected")
    test_group_readable_rejected()
    print("[ok] group readable rejected")
    test_aws_profile_unsupported()
    print("[ok] aws-profile unsupported")
    test_keychain_unsupported()
    print("[ok] keychain unsupported")
    test_empty_ref()
    print("[ok] empty ref")
    test_error_does_not_leak_path()
    print("[ok] error does not leak path")
    test_mongodb_cred()
    print("[ok] mongodb cred")
    teardown_module()
    print("\n=== Todos los tests pasaron ===")
