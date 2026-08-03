# Ciclo de una tarea Linear

## Antes de planear

1. Lee la tarea principal, descripción, comentarios, adjuntos y estado.
2. Lee el padre si existe.
3. Lista subtareas y lee descripción/comentarios de cada una.
4. Lee blockers, blocked-by y relaciones directas relevantes.
5. Identifica criterios de aceptación, decisiones previas, duplicados y trabajo ya cubierto.

No recorras el grafo indefinidamente. Amplía una relación indirecta solo cuando cambie scope o dependencia.

## Comentarios de avance

Publica comentarios breves en español:

| Momento | Contenido |
|---|---|
| Inicio | Scope entendido, repositorios y siguiente paso. |
| Plan/SDD aprobado | Enfoque y principales riesgos. |
| Implementación significativa | Qué quedó listo y qué falta. |
| Bloqueo/cambio de scope | Causa, impacto y decisión necesaria. |
| Verificación | Tests/checks y gaps conocidos. |
| Cierre | Resultado, archivos principales y trade-offs. |

No publiques un comentario por comando. No pegues el chat completo.

## Cierre

Relee criterios de aceptación, confirma checks y relaciones pendientes, publica el resumen y mueve a Done. Si el usuario prohíbe actualizaciones o falta verificación, no cierres.
