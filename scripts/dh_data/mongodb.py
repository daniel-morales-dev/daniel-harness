# scripts/dh_data/mongodb.py — Read-only MongoDB query backend
from dh_data.redaction import redact, truncate

BLOCKED_STAGES = {'$out', '$merge', '$where', '$function', 'mapReduce'}

def validate_pipeline(pipeline):
    if not isinstance(pipeline, list):
        return
    for stage in pipeline:
        if not isinstance(stage, dict):
            continue
        for key in stage:
            if key in BLOCKED_STAGES:
                raise ValueError(f"Pipeline stage bloqueada: {key}")

def handle(profile, credentials, operation, params):
    collection_name = params.get("collection", "")
    if not collection_name:
        return {"error": "collection requerido"}, 2
    if operation not in ("find", "aggregate"):
        return {"error": f"Operación no soportada: {operation}"}, 2

    from pymongo import MongoClient

    uri = credentials.strip()
    db_name = profile.get('database', '')
    client = None

    try:
        client = MongoClient(uri, serverSelectionTimeoutMS=30000)
        db = client.get_database(db_name) if db_name else client.get_default_database()
        collection = db[collection_name]

        if operation == "aggregate":
            pipeline = params.get("pipeline", [])
            validate_pipeline(pipeline)
            docs = list(collection.aggregate(pipeline))
        elif operation == "find":
            filt = params.get("filter", {})
            projection = params.get("projection")
            cursor = collection.find(filt, projection).limit(1000)
            docs = list(cursor)
        else:
            return {"error": f"Operación no soportada: {operation}"}, 2

        docs, truncated = truncate(docs, max_records=1000)
        return {"documents": docs, "truncated": truncated}, 0

    except ValueError:
        raise
    except Exception as e:
        return {"error": str(e)}, 1
    finally:
        if client:
            client.close()
