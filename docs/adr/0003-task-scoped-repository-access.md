# ADR 0003: Acceso a repositorios por tarea

## Estado

Aceptado

## Decisión

El scope surge de la tarea, no del cwd. Se soportan `single-repo`, `related-repos` y `multi-project`. Antes de editar se informa acceso read/write; repos relacionados no requieren prompt adicional.

## Consecuencias

- Una migración puede leer monolito y escribir micro.
- La sesión mantiene un mapa explícito de acceso.
- No se agregan repositorios especulativamente.
