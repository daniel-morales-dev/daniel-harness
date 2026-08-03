# Arquitectura

Daniel Harness es un overlay global de contexto, políticas y seguridad. Gentle AI conserva la autoridad sobre implementación y review; el harness aporta la información necesaria para que esa autoridad opere correctamente en cada proyecto.

## Preflight

Entrada: solicitud, directorio actual, tarea relacionada, registro de proyectos, capacidades disponibles y confianza del modelo.

Salida:

- contexto y familia detectados;
- repositorios en lectura/escritura;
- reglas resueltas por precedencia;
- restricciones de modelo y datos;
- capacidades MCP disponibles;
- contexto Linear completo;
- handoff a Gentle AI para routing y RDD.

## Autoridad por capa

| Capa | Responsabilidad |
|---|---|
| Context detector | Proyecto, familia, ambiente y repos relacionados. |
| Project registry | Paths, reglas, relaciones y política Git sin secretos. |
| Policy engine | Precedencia, permisos, confianza, datos y confirmaciones. |
| Task lifecycle | Jerarquía Linear, comentarios, avances y cierre. |
| Capability router | Descubrimiento dinámico y selección por capacidad. |
| Gentle AI adapter | Capabilities, routing orgánico, SDD opcional, RDD y receipts. |
| Data adapters | Operaciones cerradas, confirmaciones y sanitización. |
| Install/doctor | Instalación segura y diagnóstico read-only. |

## Routing

Daniel Harness no usa una tabla propia `pequeño/mediano/grande → SDD`. Entrega contexto y restricciones a Gentle AI, que selecciona una sola ruta según su contrato público:

| Ruta | Uso actual |
|---|---|
| Direct inline | Acción acotada ya entendida. |
| Delegated direct | Exploración amplia o writer con contexto fresco. |
| Optional SDD | Solicitud explícita o propuesta aceptada cuando artefactos durables reducen ambigüedad. |

Todas las rutas convergen en RDD cuando está activo. El harness no reconstruye receipts, hashes, budgets o recovery desde narración.

## Portabilidad

Las políticas y schemas son neutrales al runtime. Los adapters de OpenCode, Codex, Claude Code o Cursor traducen el mismo contrato sin modificar el núcleo.
