# Acceso de datos

## MySQL y MariaDB

Siempre read-only para operaciones del agente. Se permiten `SELECT`, `SHOW`, `DESCRIBE`/`DESC`, `EXPLAIN` y CTE que termine en `SELECT`. Se bloquean múltiples statements, mutaciones, DDL, grants, procedimientos y bulk load.

Ante un error de permisos, identifica operación/objeto, consulta `USER()` y `CURRENT_USER()` cuando sea posible, revisa grants permitidos y propone el `GRANT` mínimo. Nunca lo ejecutes.

## DynamoDB

Resuelve profile, región, tabla y ambiente. Prefiere describe, get y query; limita scans. Toda escritura requiere confirmación exacta.

## MongoDB y object storage

Default read-only. Las mutaciones MongoDB de K Agencia requieren confirmación explícita hasta definir la política final.

## Túneles

Son manuales. El harness comprueba los perfiles marcados con `tunnel.required`, informa cuál falta y muestra su `commandRef`. Nunca lee o ejecuta el comando SSH.
