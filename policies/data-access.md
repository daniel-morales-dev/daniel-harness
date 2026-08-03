# Data Access

## MySQL and MariaDB

Always read-only. Allowed statement families are `SELECT`, `SHOW`, `DESCRIBE`/`DESC`, `EXPLAIN`, and a CTE ending in `SELECT`. Multiple statements and all mutation, DDL, grant, procedure, and bulk-load operations are blocked.

On a permission error, identify the operation and object, obtain `USER()` and `CURRENT_USER()` when possible, inspect current grants when allowed, and propose the minimum `GRANT` for Daniel to send to a leader. Never execute it.

## DynamoDB

Resolve profile, region, table, and environment explicitly. Prefer describe, get, and query; limit scans.

Any write requires confirmation showing the exact operation, profile, region, table, keys, changed fields, and condition expression.

## MongoDB and Object Storage

Default to read-only diagnostics. MongoDB mutation policy for K Agencia remains open; require explicit confirmation until resolved.

## Tunnels

Tunnels are manual. The harness may test known local ports and report status but never opens or repairs SSH tunnels.
