# Security validation for credential access
import os, stat
from pathlib import Path


ALLOWED_SECRET_PREFIXES = (
    "secrets/mysql/",
    "secrets/mongodb/",
    "secrets/tunnels/",
    "secrets/tokens/",
)


def validate_credential_ref(ref, harness_dir):
    """Validate credentialsRef is within allowed paths. Reject traversal, symlinks, open perms."""
    if not isinstance(ref, str) or not ref:
        raise PermissionError("credentialsRef must be a non-empty string")

    allowed = False
    for prefix in ALLOWED_SECRET_PREFIXES:
        if ref.startswith(prefix):
            allowed = True
            break
    if not allowed:
        raise PermissionError(f"credentialsRef '{ref}' outside allowed paths")

    path = (harness_dir / ref).resolve()
    harness = harness_dir.resolve()

    try:
        path.relative_to(harness)
    except ValueError:
        raise PermissionError(f"credentialsRef '{ref}' resolves outside harness dir")

    if path.is_symlink():
        link_target = path.resolve()
        try:
            link_target.relative_to(harness)
        except ValueError:
            raise PermissionError(f"Symmetric credential ref '{ref}' points outside harness")

    try:
        mode = os.stat(path).st_mode
        if mode & (stat.S_IRWXG | stat.S_IRWXO):
            raise PermissionError(f"Credentials file '{ref}' has group/other permissions")
    except FileNotFoundError:
        raise PermissionError(f"Credentials file '{ref}' not found")


def read_credentials(path):
    """Read credential file, return content as string."""
    if not path.exists():
        raise FileNotFoundError(f"Credentials file not found: {path}")
    validate_credential_ref(str(path.relative_to(path.parent.parent)), path.parent.parent)
    content = path.read_text()
    return content
