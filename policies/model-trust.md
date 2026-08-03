# Model Trust

## Trusted

Trusted models may use tools approved by the active project policy. Trust does not bypass production confirmations, data-write rules, or repository scope.

## Restricted

Restricted models, including free models by default:

- cannot read secret files or raw credential configuration;
- cannot use arbitrary Bash, interpreters, or equivalent escape hatches;
- access protected systems only through closed, policy-enforcing tools;
- receive sanitized, minimum-necessary results.

The initial phase documents and audits this boundary. It does not rewrite production OpenCode permissions automatically.
