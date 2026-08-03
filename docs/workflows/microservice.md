# Workflow de microservicio Alegra

## Preparación

1. Aplica `task-lifecycle` si existe issue.
2. Lee `AGENTS.md`, docs index, arquitectura, testing y contratos.
3. Usa CodeGraph para flujo e impacto.
4. Consulta Context7 para librerías públicas y Raia para common/shared cuando corresponda.
5. Reporta repositorios en lectura/escritura.

## Feature o fix

1. Mantén handlers delgados.
2. Conserva dominio síncrono y puro.
3. Coloca I/O en adapters e infraestructura mediante ports.
4. Evita N+1, awaits secuenciales independientes y scans no acotados.
5. Implementa tests por comportamiento, incluido regression test para bugs.
6. Usa Ponytail después de comprender el flujo; no agregues abstracciones especulativas.

## Verificación

- Tests file-scoped durante iteración.
- Consumers directos cuando cambie un contrato compartido.
- Lint y type-check al cerrar.
- Cobertura >=90% line y branch para business logic modificada, con exenciones documentadas.
- RDD sobre la candidate antes de delivery cuando esté activo.

Publica avances Linear útiles y cierra solo después de verificar.
