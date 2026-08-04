"""DynamoDB read/write backend with persistent 2-step confirmation."""
import json
from pathlib import Path

from dh_data.config import get_harness_dir
from dh_data.token_store import TokenStore

READ_OPS = ('GetItem', 'Query', 'Scan')
WRITE_OPS = ('PutItem', 'UpdateItem')

_store = None

def _get_store():
    global _store
    if _store is None:
        state_dir = get_harness_dir() / "state"
        _store = TokenStore(state_dir)
    return _store


def validate_read_operation(operation):
    if operation not in READ_OPS:
        raise ValueError(f"read-only operation required: {operation}")


def _build_payload(params):
    return {k: v for k, v in params.items() if k in ('tableName', 'keys', 'fields', 'condition', 'operation')}


def handle_read(profile, credentials, operation, params):
    try:
        validate_read_operation(operation)
    except ValueError as e:
        return {"error": str(e)}, 2

    table_name = params.get("tableName", "")
    if not table_name:
        return {"error": "tableName required"}, 2

    import boto3

    profile_name = credentials.strip()
    region = profile.get('region', 'us-east-1')

    try:
        session = boto3.Session(profile_name=profile_name, region_name=region)
        client = session.client('dynamodb')

        if operation == 'GetItem':
            key = params.get('key') or params.get('keys') or {}
            resp = client.get_item(TableName=table_name, Key=key)
            items = [resp.get('Item', {})]
        elif operation == 'Query':
            qparams = {k: v for k, v in params.items() if k not in ('tableName', 'operation')}
            qparams['TableName'] = table_name
            resp = client.query(**qparams)
            items = resp.get('Items', [])
        elif operation == 'Scan':
            sparams = {k: v for k, v in params.items() if k not in ('tableName', 'operation')}
            sparams.setdefault('Limit', 100)
            sparams['TableName'] = table_name
            resp = client.scan(**sparams)
            items = resp.get('Items', [])

        return {"items": items, "count": len(items)}, 0

    except Exception as e:
        return {"error": str(e)}, 1


def handle_write(profile, credentials, operation, params):
    if operation == "prepare":
        return _handle_write_prepare(profile, credentials, params)
    elif operation == "confirm":
        return _handle_write_confirm(profile, credentials, params)
    return {"error": f"unknown operation: {operation}"}, 2


def _handle_write_prepare(profile, credentials, params):
    write_op = params.get("operation", "")
    if write_op not in WRITE_OPS:
        return {"error": f"write operation not allowed: {write_op}"}, 2

    payload = _build_payload(params)
    if not payload.get("tableName"):
        return {"error": "tableName required"}, 2

    # Validate writeConfirmation.mode
    wc = profile.get("writeConfirmation", {})
    if wc.get("mode") in ("deny", None):
        return {"error": "writes not allowed for this profile"}, 2
    if wc.get("mode") not in ("exact-operation",):
        return {"error": f"unsupported writeConfirmation mode: {wc.get('mode')}"}, 2

    # Validate required fields
    required = wc.get("requiredFields", [])
    for field in required:
        if field not in params:
            return {"error": f"required field missing: {field}"}, 2

    preview = {"operation": write_op, **payload}

    try:
        import boto3
        profile_name = credentials.strip()
        region = profile.get('region', 'us-east-1')
        session = boto3.Session(profile_name=profile_name, region_name=region)
        client = session.client('dynamodb')
        if payload.get('keys'):
            try:
                item = client.get_item(TableName=payload['tableName'], Key=payload['keys'])
                preview['currentItem'] = item.get('Item', {})
            except Exception:
                preview['currentItem'] = None
    except ImportError:
        preview['currentItem'] = None
    except Exception as e:
        return {"error": str(e)}, 1

    store = _get_store()
    token = store.create(payload)

    return {"confirmationRequired": True, "preview": preview, "token": token}, 3


def _handle_write_confirm(profile, credentials, params):
    token = params.get("token", "")
    if not token:
        return {"error": "token required"}, 4

    payload = _build_payload(params)

    store = _get_store()
    try:
        store.consume(token, payload)
    except Exception as e:
        return {"error": str(e)}, 4

    write_op = params.get("operation", "")
    if write_op not in WRITE_OPS:
        return {"error": f"write operation not allowed: {write_op}"}, 2

    try:
        import boto3
        profile_name = credentials.strip()
        region = profile.get('region', 'us-east-1')
        session = boto3.Session(profile_name=profile_name, region_name=region)
        client = session.client('dynamodb')

        kwargs = {'TableName': payload['tableName']}
        if write_op == 'PutItem':
            kwargs['Item'] = payload.get('fields', {})
            if payload.get('condition'):
                kwargs['ConditionExpression'] = payload['condition']
            client.put_item(**kwargs)
        elif write_op == 'UpdateItem':
            kwargs['Key'] = payload.get('keys', {})
            fields = payload.get('fields', {})
            if fields:
                kwargs['ExpressionAttributeValues'] = {f":v{k}": v for k, v in fields.items()}
                kwargs['UpdateExpression'] = "SET " + ", ".join(f"#{k} = :v{k}" for k in fields)
                kwargs['ExpressionAttributeNames'] = {f"#{k}": k for k in fields}
            if payload.get('condition'):
                kwargs['ConditionExpression'] = payload['condition']
            client.update_item(**kwargs)

        return {"attributes": {}}, 0

    except ImportError:
        return {"error": "boto3 not installed"}, 1
    except Exception as e:
        return {"error": str(e)}, 1
