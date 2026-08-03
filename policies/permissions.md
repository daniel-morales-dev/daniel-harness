# Tool Permissions

Permissions combine task scope, project rules, model trust, environment, and tool capability.

## Defaults

- Read repository documentation before implementation.
- Use CodeGraph for architecture, call flow, references, dependencies, and impact.
- Ask before production mutation, dependency installation, deploy, or a new branch.
- Deny direct access to secret paths.
- Deny arbitrary host shell to restricted models.

## Closed Tools

A closed tool owns credential access and policy enforcement. It accepts only non-secret parameters, validates the requested operation, uses credentials internally, and returns sanitized output.

Shell wrappers do not become safe merely because their output is compressed by RTK.
