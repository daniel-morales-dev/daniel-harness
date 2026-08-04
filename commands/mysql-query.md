---
description: Ejecuta una consulta SELECT read-only sobre MySQL/MariaDB via custom tool
  dh_mysql_query. La validacion y enforcement ocurren en el backend Python, no en el prompt.
mode: read
agent: data-access
subtask: true
argument-hint: "<profile> <sql>"
---

# MySQL Query

Ejecuta SELECT para el perfil: $ARGUMENTS

## Proceso

1. Lee `~/.config/daniel-harness/connections.yaml`, busca profile cuyo `id` coincida con el primer argumento.
2. Valida: `type` debe ser `mysql` o `mariadb`, `readOnly` debe ser `true`.
3. Construye JSON con `profile` y `sql`.
4. Invoca `dh_mysql_query` con el JSON.
5. Devuelve el resultado JSON.

## Restricciones

- READ ONLY. La validacion se aplica en el backend (`validate_sql` en `scripts/dh_data/mysql.py`).
- Un solo statement por llamada.
- Maximo 1000 filas devueltas.
- No exponer credenciales.
