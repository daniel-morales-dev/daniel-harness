"""Persistent token store for 2-step confirmation (DynamoDB writes).

Tokens stored as files under:
  <state_dir>/data-confirmations/<token>.json

Security: mode 700 dir, 600 files, tokens with secrets module, TTL 60s, single-use.
"""
import json
import os
import stat
import secrets
import time
from pathlib import Path


class TokenError(Exception):
    """Token operation failed."""


class TokenStore:
    """Disk-backed, single-use token store with TTL."""

    def __init__(self, state_dir: Path):
        self._dir = state_dir / "data-confirmations"
        self._dir.mkdir(parents=True, exist_ok=True)
        os.chmod(str(self._dir), stat.S_IRWXU)

    def _path(self, token: str) -> Path:
        return self._dir / f"{token}.json"

    def _gc(self):
        """Remove expired tokens."""
        now = time.time()
        for f in self._dir.iterdir():
            if f.suffix != ".json":
                continue
            try:
                data = json.loads(f.read_text())
                if data.get("expires_at", 0) < now:
                    f.unlink(missing_ok=True)
            except (json.JSONDecodeError, OSError):
                f.unlink(missing_ok=True)

    def create(self, payload: dict) -> str:
        """Create a token bound to the canonical payload. Returns token string."""
        token = secrets.token_hex(32)
        entry = {
            "payload": payload,
            "expires_at": time.time() + 60,
        }
        path = self._path(token)
        path.write_text(json.dumps(entry, sort_keys=True))
        os.chmod(str(path), stat.S_IRUSR | stat.S_IWUSR)
        return token

    def consume(self, token: str, expected_payload: dict):
        """Atomically consume a token if payload matches and not expired.

        Raises TokenError on any mismatch or expiry.
        Returns None on success.
        """
        path = self._path(token)
        if not path.exists():
            raise TokenError("token not found or already consumed")

        try:
            data = json.loads(path.read_text())
        except (json.JSONDecodeError, OSError) as e:
            path.unlink(missing_ok=True)
            raise TokenError("invalid token data") from e

        if data.get("expires_at", 0) < time.time():
            path.unlink(missing_ok=True)
            raise TokenError("token expired")

        if data.get("payload") != expected_payload:
            path.unlink(missing_ok=True)
            raise TokenError("payload mismatch")

        path.unlink()
