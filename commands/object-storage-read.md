---
description: Lee un objeto de object storage (S3-compatible) via tunel local. Lee el
  perfil de conexion desde connections.yaml, usa AWS CLI con endpoint configurable.
  Rechaza escrituras. Devuelve el contenido del objeto como texto o JSON.
mode: read
agent: alegra-microservice-engineer
subtask: true
argument-hint: "<profile> <bucket> <key>"
---

# Object Storage Read

Lee un objeto de object storage para el perfil: $ARGUMENTS

## Proceso

1. Lee `~/.config/daniel-harness/connections.yaml`, busca profile cuyo `id` coincida.
2. Valida: `type` debe ser `object-storage`, `readOnly` debe ser `true`.
3. Verifica el tunel: `host` debe ser `127.0.0.1`, el puerto debe responder.
4. Lee credenciales del archivo en `credentialsRef` (formato: `AWS_ACCESS_KEY_ID=...\nAWS_SECRET_ACCESS_KEY=...`).
5. Ejecuta: `AWS_ACCESS_KEY_ID=<key> AWS_SECRET_ACCESS_KEY=<secret> aws s3api get-object --bucket <bucket> --key <key> --endpoint-url http://127.0.0.1:<port> /tmp/dh-output && cat /tmp/dh-output`.
6. Detecta el tipo de contenido por extension o Content-Type. Para JSON, CSV y texto plano devuelve el contenido. Para binario, devuelve metadata (tamano, tipo, etag).

## Restricciones

- READ ONLY. Rechazar PutObject, DeleteObject, CopyObject.
- No listar buckets enteros ni hacer list-objects sin filtro.
- No exponer credenciales en la respuesta.
- Archivos binarios grandes (>10MB): devolver solo metadata, no el contenido.
