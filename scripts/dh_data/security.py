"""Credential resolution for dh_data tools.

resolve_credentials(ref, harness_dir) returns a string credential value.
Supports:
  - secrets/<type>/<file>    file-based, read from harness_dir, perms enforced
  - aws-profile://<name>     unsupported (returns error)
  - env://<VAR>              environment variable
  - keychain://<name>        unsupported (returns error)
"""
import os
import stat
from pathlib import Path


class CredentialError(PermissionError):
    """Credential resolution failed. Message never includes paths or secret values."""


def _resolve_file(ref, harness_dir):
    """Read a credential file under harness_dir with security checks."""
    parts = Path(ref).parts
    if any(p == ".." for p in parts):
        raise CredentialError("path traversal rejected")

    path = (harness_dir / ref).resolve()
    harness = harness_dir.resolve()

    try:
        path.relative_to(harness)
    except ValueError:
        raise CredentialError("reference resolves outside harness directory")

    if path.is_symlink():
        raise CredentialError("symlinks not allowed")

    if not path.is_file():
        raise CredentialError("not a regular file")

    mode = os.stat(path).st_mode
    if mode & (stat.S_IRWXG | stat.S_IRWXO):
        raise CredentialError("file permissions too permissive")

    return path.read_text()


def _resolve_env(ref):
    """Read a credential from an environment variable."""
    var = ref.removeprefix("env://").strip()
    if not var:
        raise CredentialError("empty environment variable name")
    value = os.environ.get(var)
    if value is None:
        raise CredentialError("environment variable not set")
    return value


def resolve_credentials(ref, harness_dir):
    """Resolve a credentialsRef to a credential string.

    Args:
        ref: credentialsRef string (e.g. "secrets/mysql/prod.cnf", "env://DB_PASS", "aws-profile://prod")
        harness_dir: Path to harness config directory

    Returns:
        str: credential content (file content, env var value, etc.)

    Raises:
        CredentialError: if ref is invalid, unsupported, or fails security checks
    """
    if not isinstance(ref, str) or not ref.strip():
        raise CredentialError("credentialsRef must be a non-empty string")

    if ref.startswith("secrets/"):
        return _resolve_file(ref, harness_dir)
    elif ref.startswith("env://"):
        return _resolve_env(ref)
    elif ref.startswith("aws-profile://"):
        raise CredentialError("aws-profile:// not yet implemented")
    elif ref.startswith("keychain://"):
        raise CredentialError("keychain:// not yet implemented")
    else:
        raise CredentialError("unsupported credentialsRef scheme")
