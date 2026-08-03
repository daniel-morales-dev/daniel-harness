# Workflow de paridad monolito y micro

Paridad significa conservar comportamiento observable, no copiar arquitectura o estilo línea por línea.

## Monolito → micro

1. Lee tarea, subtareas, comentarios y relaciones.
2. Delimita el fragmento PHP y lee método completo/callers.
3. Extrae reglas, orden, errores, amounts, flags, países y side effects.
4. Mapea cada regla a domain, application, adapter o gap del micro.
5. No copies N+1, globals, fat models o acoplamiento de transporte.
6. No inventes defaults ausentes en PHP.
7. Deja TODO con issue cuando el micro no tenga datos o ownership.
8. Prueba escenarios de paridad y documenta diferencias intencionales.

## Micro → monolito

Usa esta dirección cuando el micro contiene el contrato vigente que debe llevarse al monolito.

1. Confirma que el micro es source of truth para esa regla; no asumas que lo más nuevo es canónico.
2. Extrae entradas, outputs, errores, ordering, idempotencia y side effects.
3. Traduce el contrato a PHP 7.0.9/ZF1 sin copiar patrones TypeScript incompatibles.
4. Reutiliza helpers, gateways, services, toggles y excepciones existentes en el monolito.
5. Mantén compatibilidad pública y comportamiento legacy fuera del scope.
6. Verifica sintaxis y escenarios equivalentes en ambos lados.

## Matriz obligatoria

| Regla | Fuente | Destino | Estado | Evidencia |
|---|---|---|---|---|
| Validación/branch | archivo:método | archivo:método | Cubierto/Parcial/Gap | Test o escenario |

Registra gaps en Linear, evita subtareas duplicadas y no cierres hasta resolver o aceptar diferencias.
