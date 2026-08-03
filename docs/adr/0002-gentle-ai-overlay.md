# ADR 0002: Overlay sobre Gentle AI

## Estado

Aceptado

## Decisión

Gentle AI permanece externo y actualizable. Daniel Harness no lo forkea ni modifica generated assets; lo integra mediante comandos y contratos públicos.

## Consecuencias

- `gentle-ai upgrade/sync` conserva ownership de sus superficies.
- El harness puede evolucionar políticas propias sin copiar internals.
- Cambios del contrato público requieren revalidar el adapter.
