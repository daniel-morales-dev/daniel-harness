# Security Policy

## Report an Exposure

Stop the current operation and report the affected credential class and location without quoting its value. Do not copy the secret into an issue, chat, commit, log, or screenshot.

## Response

1. Treat a hardcoded or shared secret as compromised.
2. Revoke or rotate it in the owning system.
3. Remove it from active configuration and use an external secret reference.
4. Inspect Git history and logs for propagation.
5. Apply the minimum required privilege to the replacement credential.

History rewriting is a separate, explicitly authorized operation. Rotation comes first because deleting text does not invalidate a credential.

## Storage Boundary

Versioned code belongs in this repository. Local config belongs in `~/.config/daniel-harness/`; secret files belong under `~/.config/daniel-harness/secrets/` with directories mode `700` and files mode `600`.

Never commit:

- tokens, passwords, API keys, private keys, or credential-bearing URLs;
- raw `opencode.json` files containing headers or environment values;
- MySQL option files, SSH material, database dumps, query results, or production logs;
- remote SSH hosts or real tunnel commands.

## Model Boundary

A `read: deny` rule does not isolate secrets while arbitrary Bash or another interpreter remains available. Restricted models must use closed tools that accept non-secret parameters, read credentials internally, enforce policy, and return sanitized results.

## Minimum Privilege

- MySQL/MariaDB is always read-only.
- DynamoDB writes require exact confirmation of operation, profile, region, table, keys, fields, and condition.
- Grants are proposed for review but never executed by the harness.
- Production mutation requires explicit confirmation even for trusted models.
