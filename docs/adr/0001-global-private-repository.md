# ADR 0001: Repositorio global privado

## Estado

Aceptado

## Decisión

Mantener Daniel Harness en `daniel-morales-dev/daniel-harness`, instalarlo globalmente y guardar config/secrets en `~/.config/daniel-harness/`.

## Consecuencias

- Una sola fuente versionada para políticas compartidas.
- Los proyectos conservan sus reglas específicas.
- Privado no significa secret storage.
- Los adapters no pueden volver OpenCode-only al core.
