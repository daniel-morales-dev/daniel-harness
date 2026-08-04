---
description: Lee un objeto de object storage (S3-compatible) via custom tool dh_object_storage_read.
  La validacion y enforcement ocurren en el backend Python, no en el prompt.
mode: read
agent: data-access
subtask: true
argument-hint: "<profile> <bucket> <key>"
---

# Object Storage Read

Lee un objeto de object storage para el perfil: $ARGUMENTS

## Proceso

1. Lee `~/.config/daniel-harness/connections.yaml`, busca profile cuyo `id` coincida.
2. Valida: `type` debe ser `object-storage`, `readOnly` debe ser `true`.
3. Construye JSON con `profile`, `bucket`, `key`.
4. Invoca `dh_object_storage_read` con el JSON.
5. Devuelve el resultado JSON (contenido o metadata).

## Restricciones

- READ ONLY. La validacion se aplica en el backend (`validate_key` en `scripts/dh_data/object_storage.py`).
- Path traversal en key es bloqueado.
- Archivos >10MB: solo metadata, no contenido.
- Archivos temporales se limpian automaticamente.
- No exponer credenciales.
