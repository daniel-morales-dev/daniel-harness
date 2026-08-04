---
description: Ejecuta una consulta SELECT read-only sobre MySQL/MariaDB via tunel local.
  Lee el perfil de conexion desde connections.yaml y usa el CLI mysql con las credenciales
  referenciadas. Rechaza mutaciones. Devuelve filas como array JSON.
mode: read
agent: alegra-microservice-engineer
subtask: true
argument-hint: "<profile> <sql>"
---

# MySQL Query

Ejecuta SELECT para el perfil: $ARGUMENTS

## Proceso

1. Lee `~/.config/daniel-harness/connections.yaml`, busca profile cuyo `id` coincida con el primer argumento.
2. Valida: `type` debe ser `mysql` o `mariadb`, `readOnly` debe ser `true`.
3. Verifica que el tunel este activo: `host` debe ser `127.0.0.1`, el puerto debe responder.
4. Lee credenciales del archivo indicado en `credentialsRef` (formato: `[client]\nuser=...\npassword=...`).
5. Ejecuta: `mysql --defaults-extra-file=<credentials> -h 127.0.0.1 -P <port> --batch --raw -e "<sql>"`.
6. Convierte la salida tabular a array de objetos JSON.
7. Limita a 1000 filas.

## Restricciones

- READ ONLY. Rechazar INSERT, UPDATE, DELETE, DROP, ALTER, CREATE, TRUNCATE, CALL, SET, LOAD.
- Un solo statement por llamada. Rechazar multi-statement.
- Maximo 1000 filas devueltas. Si hay mas, incluir `"truncated": true`.
- No exponer credenciales ni valores literales sensibles en la respuesta.
- Verificar que la consulta comience con SELECT, SHOW, DESCRIBE, DESC o EXPLAIN.
