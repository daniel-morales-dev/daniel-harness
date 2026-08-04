#!/usr/bin/env python3
import json
from pathlib import Path

import jsonschema
import yaml


ROOT_DIR = Path(__file__).resolve().parent.parent
PAIRS = [
    ("schemas/config.schema.json", "examples/config.example.yaml"),
    ("schemas/connections.schema.json", "examples/connections.example.yaml"),
    ("schemas/project-registry.schema.json", "examples/project-registry.example.yaml"),
]

for schema_path, example_path in PAIRS:
    schema = json.loads((ROOT_DIR / schema_path).read_text())
    example = yaml.safe_load((ROOT_DIR / example_path).read_text())
    jsonschema.Draft202012Validator.check_schema(schema)
    jsonschema.validate(example, schema, cls=jsonschema.Draft202012Validator)

print("schema examples validated")
