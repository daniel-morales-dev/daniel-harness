# ADR 0004: Frontera de secretos para modelos restricted

## Estado

Aceptado

## Decisión

Los modelos restricted no reciben secretos ni shell arbitrario. Acceden a sistemas protegidos mediante tools cerradas con validación y sanitización.

## Consecuencias

- `read: deny` con Bash amplio no cuenta como aislamiento.
- Los data adapters productivos deben ser operaciones estrechas.
- La fase actual documenta y diagnostica; no reescribe OpenCode automáticamente.
