# Output redaction for dh_data tools
import re


SENSITIVE_PATTERNS = [
    re.compile(r'(password|passwd|pwd)\s*[:=]\s*["\']?[^"\';\s]+["\']?', re.IGNORECASE),
    re.compile(r'(secret|token|api_key|apikey)\s*[:=]\s*["\']?[^"\';\s]+["\']?', re.IGNORECASE),
    re.compile(r'(aws_secret_access_key|aws_access_key_id)\s*[:=]\s*["\']?[^"\';\s]+["\']?', re.IGNORECASE),
]


def redact(text):
    """Replace sensitive patterns with REDACTED."""
    result = text
    for pattern in SENSITIVE_PATTERNS:
        result = pattern.sub(r'\1=REDACTED', result)
    return result


def truncate(data, max_bytes=10 * 1024 * 1024, max_records=1000):
    """Truncate data to limits."""
    if isinstance(data, list) and len(data) > max_records:
        return data[:max_records], True
    if isinstance(data, str) and len(data.encode()) > max_bytes:
        return data[:max_bytes], True
    return data, False
