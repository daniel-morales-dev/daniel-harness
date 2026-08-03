# Workflow del monolito Alegra

## Preparación

1. Si no hay tarea Linear vinculada, créala con título, contexto y criterios de aceptación mínimos. Luego aplica `task-lifecycle`.
2. Lee `AGENTS.md`, `CLAUDE.md` y docs relacionadas.
3. Activa `php-engineer`.
4. Usa CodeGraph para encontrar entry point, callers, side effects y blast radius.
5. Reporta repositorios en lectura/escritura.

## Feature o fix

1. Define comportamiento observable, permisos, país, toggle y rollback.
2. Lee método completo, helpers, controller/model/service y contratos downstream.
3. Conserva ZF1 y PHP 7.0.9; no modernices superficies no relacionadas.
4. Implementa el cambio mínimo siguiendo el estilo vecino.
5. Diferencia fallback deliberado de error transitorio.
6. Mantén company scope, transacciones, idempotencia y side effects.

## Verificación

```bash
docker exec alegra-app-php-1 php -l <file>
```

Ejecuta checks existentes y escenarios manuales del flujo. Para migraciones usa Phinx y `testing_docker`. No inventes un framework de unit tests.

Actualiza Linear en transiciones significativas y cierra solo con criterios verificados.
