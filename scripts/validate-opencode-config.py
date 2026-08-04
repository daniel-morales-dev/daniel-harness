#!/usr/bin/env python3
"""Shared OpenCode config validator — bootstrap, doctor y CI usan el mismo código.

Uso:
  validate-opencode-config.py --config <opencode.json> --schema <schema.json>

Exit 0 si es válido, 1 si no, con mensaje de error en stderr.
"""
import json
import sys
import argparse

try:
    import jsonschema
except ImportError:
    print("error: jsonschema no instalado (pip install jsonschema)", file=sys.stderr)
    sys.exit(2)


def main():
    parser = argparse.ArgumentParser(description="Valida opencode.json contra schema versionado")
    parser.add_argument("--config", required=True, help="Ruta a opencode.json")
    parser.add_argument("--schema", required=True, help="Ruta al schema JSON")
    args = parser.parse_args()

    try:
        with open(args.config) as f:
            config = json.load(f)
    except json.JSONDecodeError as e:
        print(f"error: config no es JSON válido — {e}", file=sys.stderr)
        sys.exit(1)
    except FileNotFoundError:
        print(f"error: config no encontrado — {args.config}", file=sys.stderr)
        sys.exit(1)

    try:
        with open(args.schema) as f:
            schema = json.load(f)
    except FileNotFoundError:
        print(f"error: schema no encontrado — {args.schema}", file=sys.stderr)
        sys.exit(2)

    try:
        jsonschema.validate(config, schema)
        print(f"[ok] Schema válido: {args.config}")
        sys.exit(0)
    except jsonschema.ValidationError as e:
        path = " → ".join(str(p) for p in e.absolute_path) if e.absolute_path else "root"
        print(f"error: schema inválido en {path}: {e.message}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
