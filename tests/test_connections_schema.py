#!/usr/bin/env python3
import json
from pathlib import Path

import jsonschema


ROOT_DIR = Path(__file__).resolve().parent.parent
SCHEMA = json.loads((ROOT_DIR / "schemas/connections.schema.json").read_text())
VALID_FIELDS = [
    "operation",
    "profile",
    "region",
    "resource",
    "keys",
    "fields",
    "condition",
]


def configuration(required_fields: list[str], mode: str = "exact-operation") -> dict:
    return {
        "version": "1",
        "profiles": [
            {
                "id": "synthetic-dynamodb",
                "context": "alegra-microservice",
                "type": "dynamodb",
                "environment": "testing",
                "region": "us-east-1",
                "readOnly": False,
                "credentialsRef": "aws-profile://SYNTHETIC",
                "writeConfirmation": {
                    "mode": mode,
                    "requiredFields": required_fields,
                },
            }
        ],
    }


jsonschema.validate(configuration(VALID_FIELDS), SCHEMA)

tunnel_configuration = {
    "version": "1",
    "profiles": [
        {
            "id": "synthetic-mysql",
            "context": "freelance",
            "type": "mysql",
            "environment": "testing",
            "host": "127.0.0.1",
            "port": 3306,
            "readOnly": True,
            "credentialsRef": "secrets/mysql/synthetic.cnf",
            "tunnel": {
                "required": True,
                "commandRef": "secrets/tunnels/synthetic.command",
            },
            "writeConfirmation": {"mode": "deny"},
        }
    ],
}
jsonschema.validate(tunnel_configuration, SCHEMA)

missing_required_fields = configuration(VALID_FIELDS)
del missing_required_fields["profiles"][0]["writeConfirmation"]["requiredFields"]

invalid_configurations = [
    missing_required_fields,
    configuration(VALID_FIELDS[:-1]),
    configuration(VALID_FIELDS, mode="deny"),
    configuration(VALID_FIELDS + ["operation"]),
]

invalid_tunnel = tunnel_configuration.copy()
invalid_tunnel["profiles"] = [tunnel_configuration["profiles"][0].copy()]
invalid_tunnel["profiles"][0]["tunnel"] = {
    "required": True,
    "commandRef": "../../unsafe.command",
}
invalid_configurations.append(invalid_tunnel)

for invalid_configuration in invalid_configurations:
    try:
        jsonschema.validate(invalid_configuration, SCHEMA)
    except jsonschema.ValidationError:
        continue
    raise AssertionError("Expected invalid DynamoDB confirmation policy to fail")

print("connections schema tests passed")
