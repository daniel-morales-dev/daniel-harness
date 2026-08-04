---
name: data-access
description: Acceso cerrado a datos. Solo ejecuta las custom tools dh_* via OpenCode;
  no tiene acceso a bash ni edicion.
mode: subagent
permission:
  "*": deny
  dh_mysql_query: allow
  dh_mongodb_query: allow
  dh_dynamodb_read: allow
  dh_dynamodb_write: allow
  dh_object_storage_read: allow
---
