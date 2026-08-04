#!/usr/bin/env python3
import json
from pathlib import Path

import jsonschema


ROOT_DIR = Path(__file__).resolve().parent.parent
SCHEMA = json.loads((ROOT_DIR / "schemas/config.schema.json").read_text())


def configuration() -> dict:
    return {
        "version": "1",
        "defaultScope": "single-repo",
        "workflowAuthority": {
            "provider": "gentle-ai",
            "implementationRouting": "provider-policy",
            "sddActivation": "explicit-or-accepted-proposal",
            "review": "receipt-driven-development",
            "capabilityNegotiation": True,
        },
        "tooling": {
            "codeExploration": "codegraph",
            "memory": "engram",
            "codeSimplicity": "ponytail",
            "communication": "caveman",
            "communicationMode": "adaptive",
        },
        "workTracking": {
            "provider": "linear",
            "whenIssueLinked": True,
            "readHierarchy": True,
            "readRelated": True,
            "progressComments": "meaningful-transitions",
            "commentLanguage": "es",
            "closeWhenVerified": True,
        },
        "models": [
            {
                "id": "synthetic-restricted",
                "trust": "restricted",
                "allowArbitraryShell": False,
                "allowedCapabilities": ["repository-read-sanitized"],
            }
        ],
        "mcpRouting": [],
        "confirmations": {
            "branchCreation": "always",
            "productionMutation": "always",
            "dynamodbWrite": "exact-operation",
            "mongodbWrite": "always",
        },
    }


jsonschema.validate(configuration(), SCHEMA)

invalid_provider = configuration()
invalid_provider["workflowAuthority"]["provider"] = "custom-router"

invalid_sdd = configuration()
invalid_sdd["workflowAuthority"]["sddActivation"] = "size-based"

invalid_restricted_shell = configuration()
invalid_restricted_shell["models"][0]["allowArbitraryShell"] = True

for invalid_configuration in [invalid_provider, invalid_sdd, invalid_restricted_shell]:
    try:
        jsonschema.validate(invalid_configuration, SCHEMA)
    except jsonschema.ValidationError:
        continue
    raise AssertionError("Expected invalid harness authority policy to fail")

print("config schema tests passed")
