# Seguimiento de tareas

## Linear obligatorio para Alegra

Antes de implementar cualquier cambio en un contexto Alegra (monolito, microservicio o integración), debe existir una tarea Linear vinculada. Si no la hay, créala con título, contexto y criterios de aceptación mínimos antes de empezar.

`task-lifecycle` es obligatoria siempre que haya una tarea vinculada.

- Lee descripción, comentarios, adjuntos, padre, subtareas, blockers, blocked-by y relaciones directas.
- Lee la descripción y comentarios de cada relación que cambie scope, dependencia o aceptación.
- Publica avances en español al iniciar, cambiar de fase, encontrar un bloqueo o completar verificación.
- Evita comentarios por cada comando o archivo.
- No crees subtareas duplicadas.
- No cierres hasta verificar criterios de aceptación y checks aplicables.
- Respeta una instrucción explícita de no actualizar Linear.

## Registro de decisiones

Toda decisión de arquitectura o diseño (por qué se descartó una alternativa, qué tradeoff se aceptó) se registra como ADR en `docs/adr/` del proyecto activo. Usa la numeración correlativa existente. No se documentan decisiones triviales de implementación ni cambios sin alternativa considerada.
