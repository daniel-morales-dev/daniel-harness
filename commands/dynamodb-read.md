---
description: Ejecuta operaciones read-only sobre DynamoDB (GetItem, Query, Scan) via custom tool
  dh_dynamodb_read. La validacion y enforcement ocurren en el backend Python, no en el prompt.
mode: read
agent: data-access
subtask: true
argument-hint: "<profile> <operation> <params-json>"
---

# DynamoDB Read

Ejecuta operacion de lectura para el perfil: $ARGUMENTS

## Proceso

1. Lee `~/.config/daniel-harness/connections.yaml`, busca profile cuyo `id` coincida.
2. Valida: `type` debe ser `dynamodb`.
3. Construye JSON con `profile`, `operation` (GetItem|Query|Scan), `tableName`, `params`.
4. Invoca `dh_dynamodb_read` con el JSON.
5. Devuelve el resultado JSON.

## Restricciones

- READ ONLY. La validacion se aplica en el backend (`handle_read` en `scripts/dh_data/dynamodb.py`).
- Solo GetItem, Query, Scan. PutItem, UpdateItem, DeleteItem, BatchWriteItem son bloqueados.
- Scan limitado a 100 items.
- No exponer credenciales.
