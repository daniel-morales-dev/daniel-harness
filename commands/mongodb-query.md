---
description: Ejecuta una consulta read-only sobre MongoDB (find o aggregate) via tunel
  local. Lee el perfil de conexion desde connections.yaml y usa mongosh. Rechaza mutaciones.
  Devuelve documentos como array JSON.
mode: read
agent: alegra-microservice-engineer
subtask: true
argument-hint: "<profile> <collection> <filter-json> [projection-json]"
---

# MongoDB Query

Ejecuta find/aggregate para el perfil: $ARGUMENTS

## Proceso

1. Lee `~/.config/daniel-harness/connections.yaml`, busca profile cuyo `id` coincida.
2. Valida: `type` debe ser `mongodb`, `readOnly` debe ser `true`.
3. Lee credenciales del archivo en `credentialsRef` (formato: `MONGODB_URI=mongodb://...`).
4. Conecta via: `mongosh "<uri>" --eval 'db.getSiblingDB("<db>").getCollection("<collection>").find(<filter>).limit(1000).toArray()' --quiet`.
5. Para `aggregate`: usa `db.getCollection("<collection>").aggregate(<pipeline>).toArray()`.
6. Devuelve documentos como array JSON. Si se excede el tamano, incluir `"truncated": true`.

## Restricciones

- READ ONLY. Rechazar insert, update, delete, drop, createIndex, mapReduce, bulkWrite.
- Un solo comando por llamada.
- Maximo 1000 documentos.
- No exponer credenciales en la respuesta.
- Preferir `find()` con filtro sobre `aggregate()` sin `$match`.
