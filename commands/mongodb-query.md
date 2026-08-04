---
description: Ejecuta una consulta read-only sobre MongoDB (find o aggregate) via custom tool
  dh_mongodb_query. La validacion y enforcement ocurren en el backend Python, no en el prompt.
mode: read
agent: data-access
subtask: true
argument-hint: "<profile> <collection> <filter-json> [projection-json]"
---

# MongoDB Query

Ejecuta find/aggregate para el perfil: $ARGUMENTS

## Proceso

1. Lee `~/.config/daniel-harness/connections.yaml`, busca profile cuyo `id` coincida.
2. Valida: `type` debe ser `mongodb`, `readOnly` debe ser `true`.
3. Construye JSON con `profile`, `collection`, `filter`, `projection` (find) o `pipeline` (aggregate).
4. Invoca `dh_mongodb_query` con el JSON.
5. Devuelve el resultado JSON.

## Restricciones

- READ ONLY. La validacion se aplica en el backend (`validate_pipeline` en `scripts/dh_data/mongodb.py`).
- Pipeline con `$out`, `$merge`, `$where`, `$function`, `mapReduce` son bloqueados.
- Maximo 1000 documentos.
- No exponer credenciales.
