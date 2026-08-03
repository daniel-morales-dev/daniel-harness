---
name: task-lifecycle
description: "Trigger: Linear issue, tarea, subtarea, ticket. Lee la jerarquía completa y publica avances y cierre verificado en español."
license: Proprietary
metadata:
  author: "daniel-morales-dev"
  version: "1.0"
---

# Task Lifecycle

## Activation Contract

Activa esta skill cuando la solicitud incluya una tarea Linear, un identificador de issue o trabajo vinculado a subtareas.

## Hard Rules

- Lee la tarea, descripción, comentarios, adjuntos, padre, subtareas y relaciones directas antes de planear.
- Lee descripción y comentarios de cada tarea relacionada que afecte alcance, dependencias o aceptación.
- No recorras relaciones sin límite: detente en relaciones directas y amplía solo si una dependencia lo exige.
- No dupliques subtareas existentes.
- Publica comentarios en español solo en avances significativos; no copies el chat.
- No marques Done hasta verificar criterios y checks aplicables.
- Respeta una instrucción explícita de no actualizar Linear.

## Decision Gates

| Estado | Acción |
|---|---|
| Contexto incompleto | Investiga relaciones; pregunta solo si sigue bloqueado. |
| Trabajo iniciado | Publica alcance y siguiente verificación. |
| Cambio de alcance o bloqueo | Publica causa, impacto y decisión requerida. |
| Implementación lista | Publica checks en curso o resultado parcial útil. |
| Verificación completa | Publica resumen, riesgos/gaps y mueve a Done. |

## Execution Steps

1. Construye un mapa de tarea principal, padre, hijos, blockers, blocked-by y related.
2. Resume criterios de aceptación, decisiones previas, gaps y archivos/repositorios afectados.
3. Ejecuta el workflow del contexto sin perder ese mapa.
4. Comenta únicamente al cambiar de fase o descubrir un bloqueo material.
5. Relee los criterios antes del cierre y registra evidencia de verificación.

## Output Contract

Entrega mapa de tareas consultadas, avances publicados, estado final, verificación y gaps pendientes.

## References

- `../../docs/workflows/task-lifecycle.md`
