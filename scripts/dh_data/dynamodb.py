# scripts/dh_data/dynamodb.py — DynamoDB read/write backend
import json, hashlib, time, random

READ_OPS = ('GetItem', 'Query', 'Scan')
WRITE_OPS = ('PutItem', 'UpdateItem')
TOKEN_STORE = {}  # nonce -> {"payload": dict, "expires": float}

def validate_read_operation(operation):
    if operation not in READ_OPS:
        raise ValueError(f"Operación de solo lectura no permitida: {operation}")

def handle_read(profile, credentials, operation, params):
    try:
        validate_read_operation(operation)
    except ValueError as e:
        return {"error": str(e)}, 2

    table_name = params.get("tableName", "")
    if not table_name:
        return {"error": "tableName requerido"}, 2

    import boto3

    profile_name = credentials.strip()
    region = profile.get('region', 'us-east-1')

    try:
        session = boto3.Session(profile_name=profile_name, region_name=region)
        client = session.client('dynamodb')

        kwargs = {'TableName': table_name}
        key = params.get('key') or params.get('keys') or {}

        if operation == 'GetItem':
            kwargs['Key'] = key
            resp = client.get_item(**kwargs)
            items = [resp.get('Item', {})]
        elif operation == 'Query':
            kwargs.update(params)
            kwargs.pop('tableName', None)
            kwargs.pop('operation', None)
            resp = client.query(**kwargs)
            items = resp.get('Items', [])
        elif operation == 'Scan':
            kwargs.update({k: v for k, v in params.items() if k != 'tableName'})
            kwargs.setdefault('Limit', 100)
            resp = client.scan(**kwargs)
            items = resp.get('Items', [])

        return {"items": items, "count": len(items)}, 0

    except Exception as e:
        return {"error": str(e)}, 1


def _build_payload(params):
    return {k: v for k, v in params.items() if k in ('tableName', 'keys', 'fields', 'condition')}

def handle_write(profile, credentials, operation, params):
    if operation == "prepare":
        return _handle_write_prepare(profile, credentials, params)
    elif operation == "confirm":
        return _handle_write_confirm(profile, credentials, params)
    return {"error": f"Operación no soportada: {operation}"}, 2

def _handle_write_prepare(profile, credentials, params):
    write_op = params.get("operation", "")
    if write_op not in WRITE_OPS:
        return {"error": f"Operación de escritura no permitida: {write_op}"}, 2

    payload = _build_payload(params)
    if not payload.get("tableName"):
        return {"error": "tableName requerido"}, 2

    import boto3
    # Ejecutar dry-run preview via GetItem
    profile_name = credentials.strip()
    region = profile.get('region', 'us-east-1')

    try:
        session = boto3.Session(profile_name=profile_name, region_name=region)
        client = session.client('dynamodb')

        preview = {"operation": write_op, **payload}
        if write_op in ('PutItem', 'UpdateItem') and payload.get('keys'):
            try:
                item = client.get_item(TableName=payload['tableName'], Key=payload['keys'])
                preview['currentItem'] = item.get('Item', {})
            except Exception:
                preview['currentItem'] = None

        raw = json.dumps(payload, sort_keys=True)
        token = hashlib.sha256(f"{raw}{time.time()}{random.random()}".encode()).hexdigest()
        TOKEN_STORE[token] = {"payload": payload, "expires": time.time() + 60, "operation": write_op}

        return {"confirmationRequired": True, "preview": preview, "token": token}, 3

    except Exception as e:
        return {"error": str(e)}, 1

def _handle_write_confirm(profile, credentials, params):
    token = params.get("token", "")
    if not token or token not in TOKEN_STORE:
        return {"error": "Token inválido o expirado"}, 4

    entry = TOKEN_STORE.pop(token)
    if time.time() > entry["expires"]:
        return {"error": "Token expirado"}, 4

    payload = _build_payload(params)
    stored = entry["payload"]
    if payload != stored:
        return {"error": "Payload no coincide con el preview"}, 4

    try:
        import boto3
        profile_name = credentials.strip()
        region = profile.get('region', 'us-east-1')
        session = boto3.Session(profile_name=profile_name, region_name=region)
        client = session.client('dynamodb')

        write_op = entry["operation"]
        kwargs = {'TableName': payload['tableName']}
        if payload.get('keys'):
            kwargs['Key'] = payload['keys']
        if payload.get('fields'):
            if write_op == 'PutItem':
                kwargs['Item'] = payload['fields']
            else:
                kwargs['ExpressionAttributeValues'] = {f":v{k}": v for k, v in payload['fields'].items()}
                kwargs['UpdateExpression'] = "SET " + ", ".join(f"#{k} = :v{k}" for k in payload['fields'])
                kwargs['ExpressionAttributeNames'] = {f"#{k}": k for k in payload['fields']}
        if payload.get('condition'):
            kwargs['ConditionExpression'] = payload['condition']

        if write_op == 'PutItem':
            client.put_item(**kwargs)
        else:
            client.update_item(**kwargs)

        return {"attributes": {}}, 0

    except Exception as e:
        return {"error": str(e)}, 1
