"""Read-only MongoDB find/aggregate query backend."""
from dh_data.redaction import redact, truncate

BLOCKED_STAGES = {'$out', '$merge', '$where', '$function', 'mapReduce'}
BLOCKED_OPERATORS = {'$where', '$function', '$accumulator'}

def _contains_blocked(obj, depth=0):
    """Recursively check for blocked operators at any nesting depth."""
    if depth > 10:
        return False
    if isinstance(obj, dict):
        for key, val in obj.items():
            if key in BLOCKED_OPERATORS or key in BLOCKED_STAGES:
                return True
            if _contains_blocked(val, depth + 1):
                return True
    elif isinstance(obj, list):
        for item in obj:
            if _contains_blocked(item, depth + 1):
                return True
    return False


def validate_pipeline(pipeline):
    if not isinstance(pipeline, list):
        return
    if _contains_blocked(pipeline):
        raise ValueError("blocked pipeline stage or operator")
    for stage in pipeline:
        if isinstance(stage, dict):
            for key in stage:
                if key in BLOCKED_STAGES:
                    raise ValueError(f"blocked pipeline stage: {key}")


def handle(profile, credentials, operation, params):
    collection_name = params.get("collection", "")
    if not collection_name:
        return {"error": "collection required"}, 2
    if operation not in ("find", "aggregate"):
        return {"error": f"unsupported operation: {operation}"}, 2

    try:
        from pymongo import MongoClient
    except ImportError:
        return {"error": "pymongo not installed"}, 1

    uri = credentials.strip()
    db_name = profile.get('database', '')
    client = None

    try:
        client = MongoClient(uri, serverSelectionTimeoutMS=30000)

        # Validate URI: must start with mongodb:// or mongodb+srv://
        if not uri.startswith("mongodb://") and not uri.startswith("mongodb+srv://"):
            return {"error": "invalid MongoDB URI"}, 2

        db = client.get_database(db_name) if db_name else client.get_default_database()
        collection = db[collection_name]

        if operation == "aggregate":
            pipeline = params.get("pipeline", [])
            validate_pipeline(pipeline)
            limit = min(params.get("limit", 1000), 1000)
            docs = list(collection.aggregate(pipeline, maxTimeMS=30000))
            docs = docs[:limit]
        elif operation == "find":
            filt = params.get("filter", {})
            projection = params.get("projection")
            limit = min(params.get("limit", 1000), 1000)
            cursor = collection.find(filt, projection, maxTimeMS=30000).limit(limit)
            docs = list(cursor)
        else:
            return {"error": f"unsupported operation: {operation}"}, 2

        docs, truncated = truncate(docs, max_records=1000)
        return {"documents": docs, "truncated": truncated}, 0

    except ValueError:
        raise
    except Exception as e:
        return {"error": str(e)}, 1
    finally:
        if client:
            client.close()
