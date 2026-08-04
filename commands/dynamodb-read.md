---
description: Ejecuta operaciones read-only sobre DynamoDB (GetItem, Query, Scan
  limitado). Lee el perfil de conexion desde connections.yaml y usa AWS CLI.
  Rechaza mutaciones. Devuelve items como JSON.
mode: read
agent: alegra-microservice-engineer
subtask: true
argument-hint: "<profile> <GetItem|Query> <params-json>"
---

# DynamoDB Read

Ejecuta operacion de lectura para el perfil: $ARGUMENTS

## Proceso

1. Lee `~/.config/daniel-harness/connections.yaml`, busca profile cuyo `id` coincida.
2. Valida: `type` debe ser `dynamodb`.
3. Lee `region` y `credentialsRef` (formato: `aws-profile://<profile>`).
4. Configura: `AWS_PROFILE=<profile> AWS_REGION=<region>`.
5. Ejecuta segun la operacion:
   - `GetItem`: `aws dynamodb get-item --table-name <resource> --key '<keys>'`
   - `Query`: `aws dynamodb query --table-name <resource> --key-condition-expression '<condition>' [--filter-expression]`
   - `Scan`: solo si no existe `GetItem` ni `Query`, con `--max-items 100`
6. Devuelve `Item` o `Items` como JSON.

## Restricciones

- READ ONLY. Rechazar PutItem, UpdateItem, DeleteItem, BatchWriteItem, TransactWriteItems.
- Preferir GetItem > Query > Scan (Scan solo como ultimo recurso).
- Limitar Scan a 100 items maximo.
- No exponer credenciales AWS en la respuesta.
