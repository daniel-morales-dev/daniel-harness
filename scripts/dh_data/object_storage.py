# scripts/dh_data/object_storage.py — Read-only S3-compatible object storage backend
import os, tempfile
from dh_data.redaction import redact

MAX_BYTES = 10 * 1024 * 1024

def validate_key(key):
    if not key or not isinstance(key, str):
        raise ValueError("key requerido")
    if key.startswith('/'):
        raise ValueError("key no debe comenzar con /")
    if '..' in key.split('/'):
        raise ValueError("path traversal detectado en key")
    if os.path.isabs(key):
        raise ValueError("key absoluto no permitido")

def handle(profile, credentials, operation, params):
    if operation != "get-object":
        return {"error": f"Operación no soportada: {operation}"}, 2

    bucket = params.get("bucket", "")
    key = params.get("key", "")

    if not bucket:
        return {"error": "bucket requerido"}, 2
    try:
        validate_key(key)
    except ValueError as e:
        return {"error": str(e)}, 2

    import boto3

    endpoint = profile.get('endpoint')
    region = profile.get('region', 'us-east-1')

    try:
        client_kwargs = {'region_name': region}
        if endpoint:
            client_kwargs['endpoint_url'] = endpoint

        # Parse credentials: can be AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY pair
        lines = credentials.strip().split('\n')
        aws_access_key = None
        aws_secret_key = None
        for line in lines:
            if line.startswith('AWS_ACCESS_KEY_ID='):
                aws_access_key = line.split('=', 1)[1].strip()
            elif line.startswith('AWS_SECRET_ACCESS_KEY='):
                aws_secret_key = line.split('=', 1)[1].strip()

        if aws_access_key and aws_secret_key:
            client_kwargs['aws_access_key_id'] = aws_access_key
            client_kwargs['aws_secret_access_key'] = aws_secret_key

        client = boto3.client('s3', **client_kwargs)

        head = client.head_object(Bucket=bucket, Key=key)
        content_length = head.get('ContentLength', 0)
        content_type = head.get('ContentType', 'application/octet-stream')
        etag = head.get('ETag', '')

        if content_length > MAX_BYTES:
            return {
                "metadata": {
                    "size": content_length,
                    "contentType": redact(content_type),
                    "etag": redact(etag),
                },
                "binary": True,
            }, 0

        tmp = None
        try:
            with tempfile.NamedTemporaryFile(suffix='.dh-object', delete=False) as f:
                tmp = f.name
                client.download_fileobj(bucket, key, f)

            with open(tmp, 'r', errors='replace') as f:
                content = f.read(MAX_BYTES)

            truncated = content_length > MAX_BYTES
            content = redact(content)

            return {"content": content, "truncated": truncated}, 0
        finally:
            if tmp and os.path.exists(tmp):
                os.unlink(tmp)

    except Exception as e:
        return {"error": str(e)}, 1
