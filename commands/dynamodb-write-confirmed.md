---
description: Escribe un item en DynamoDB (PutItem o UpdateItem) via custom tool dh_dynamodb_write.
  Requiere confirmacion exacta en dos pasos (prepare + confirm). La validacion y enforcement
  ocurren en el backend Python, no en el prompt.
mode: write
agent: data-access
subtask: true
argument-hint: "<profile> <PutItem|UpdateItem> <params-json>"
---

# DynamoDB Write Confirmed

Ejecuta escritura en DynamoDB para el perfil: $ARGUMENTS

## Proceso (2 pasos)

### Paso 1: Prepare
1. Lee `~/.config/daniel-harness/connections.yaml`, busca profile cuyo `id` coincida.
2. Valida: `type` debe ser `dynamodb`, `writeConfirmation.mode` debe ser `exact-operation`.
3. Construye JSON con `profile`, `operation`, `tableName`, `keys`, `fields`, `condition`.
4. Invoca `dh_dynamodb_write` (modo prepare).
5. Muestra al usuario el `preview` devuelto y el `token`.

### Paso 2: Confirm
6. Una vez el usuario confirma, invoca `dh_dynamodb_write` con el mismo payload más el `token`.
7. Devuelve el resultado JSON.

## Restricciones

- REQUIERE confirmacion exacta (prepare + confirm con token).
- El backend verifica que el payload coincida exactamente con el preview.
- Token de un solo uso con expiracion de 60s.
- Solo PutItem y UpdateItem.
- No exponer credenciales.
