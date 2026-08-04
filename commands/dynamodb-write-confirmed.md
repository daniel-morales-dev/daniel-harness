---
description: Escribe un item en DynamoDB (PutItem o UpdateItem). Requiere confirmacion
  exacta del usuario antes de ejecutar. Lee el perfil de conexion desde connections.yaml,
  usa AWS CLI y respeta la politica writeConfirmation del perfil.
mode: write
agent: alegra-microservice-engineer
subtask: true
argument-hint: "<profile> <PutItem|UpdateItem> <params-json>"
---

# DynamoDB Write Confirmed

Ejecuta escritura en DynamoDB para el perfil: $ARGUMENTS

## Proceso

1. Lee `~/.config/daniel-harness/connections.yaml`, busca profile cuyo `id` coincida.
2. Valida: `type` debe ser `dynamodb`, `writeConfirmation.mode` debe ser `exact-operation`.
3. Lee `region`, `resource` (table name), `credentialsRef`.
4. Configura: `AWS_PROFILE=<profile> AWS_REGION=<region>`.
5. Antes de ejecutar, MUESTRA al usuario los campos requeridos por `writeConfirmation.requiredFields`:
   - `operation`: PutItem o UpdateItem
   - `profile`: nombre del perfil
   - `region`: region AWS
   - `resource`: nombre de la tabla
   - `keys`: clave primaria del item
   - `fields`: campos a escribir
   - `condition`: expresion condicional (si aplica)
6. ESPERA confirmacion explicita del usuario ("si", "confirmo", "adelante").

## Restricciones

- REQUIERE confirmacion explicita del usuario. Sin confirmacion, no ejecutar.
- Solo PutItem y UpdateItem. Rechazar DeleteItem, BatchWriteItem, TransactWriteItems.
- No exponer credenciales AWS en la respuesta.
- Incluir en la respuesta el resultado de la operacion (atributos devueltos).
