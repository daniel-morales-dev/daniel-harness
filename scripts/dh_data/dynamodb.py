# scripts/dh_data/dynamodb.py — DynamoDB read/write backend
import json

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
