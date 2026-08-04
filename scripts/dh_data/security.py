"""Credential resolution for dh_data tools.

resolve_credentials(ref, harness_dir) returns a typed credential dict.
Supports:
  - secrets/<type>/<file>    file-based, read from harness_dir, perms enforced
  - env://<VAR>              environment variable
  - aws-profile://<name>     AWS profile (boto3 Session)
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

    raw = (harness_dir / ref)
    harness = harness_dir.resolve()

    # Inspect symlink BEFORE resolve
    try:
        lst = os.lstat(raw)
    except OSError:
        raise CredentialError("credential file not accessible")

    if stat.S_ISLNK(lst.st_mode):
        raise CredentialError("symlinks not allowed")

    path = raw.resolve()
    try:
        path.relative_to(harness)
    except ValueError:
        raise CredentialError("reference resolves outside harness directory")

    if not stat.S_ISREG(lst.st_mode):
        raise CredentialError("not a regular file")

    if lst.st_mode & (stat.S_IRWXG | stat.S_IRWXO):
        raise CredentialError("file permissions too permissive")

    return {"kind": "file", "value": path.read_text()}


def _resolve_env(ref):
    """Read a credential from an environment variable."""
    var = ref.removeprefix("env://").strip()
    if not var:
        raise CredentialError("empty environment variable name")
    value = os.environ.get(var)
    if value is None:
        raise CredentialError("environment variable not set")
    return {"kind": "env", "value": value}


def _resolve_aws_profile(ref):
    """Read credentials from an AWS profile via boto3 Session."""
    profile = ref.removeprefix("aws-profile://").strip()
    if not profile:
        raise CredentialError("empty AWS profile name")
    return {"kind": "aws-profile", "profile": profile}


def resolve_credentials(ref, harness_dir):
    """Resolve a credentialsRef to a credential dict.

    Args:
        ref: credentialsRef string
        harness_dir: Path to harness config directory

    Returns:
        dict with at least {"kind": str, ...}
        - kind "file": {"kind": "file", "value": str}
        - kind "env": {"kind": "env", "value": str}
        - kind "aws-profile": {"kind": "aws-profile", "profile": str}

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
        return _resolve_aws_profile(ref)
    elif ref.startswith("keychain://"):
        raise CredentialError("keychain:// not yet implemented")
    else:
        raise CredentialError("unsupported credentialsRef scheme")
