# Security Model

## Assets

- Versioned policy and code.
- Local non-secret configuration.
- Secret material.
- Proprietary source and internal documentation.
- Production and testing data.

These are separate trust classes. A private repository protects visibility but is not an approved credential store.

## Trust Boundary

Trusted executors may access approved host tools. Restricted models receive no arbitrary shell or direct secret reads. Closed tools cross the boundary by enforcing a narrow operation and returning sanitized output.

## Known Limitation

OpenCode `read: deny` does not create isolation if Bash can call `cat`, an interpreter, a database client, or another reader. RTK reduces output volume but does not enforce permissions.

## Phase 1 Guarantee

This phase provides documentation, schemas, examples, redaction, and diagnostics. It does not claim that current production OpenCode configuration is isolated, and it does not alter that configuration.

## Proprietary Code

The exact policy for sending proprietary code to free/restricted models remains open. Until decided, use the conservative default: do not send proprietary source outside approved trusted models and tools.
