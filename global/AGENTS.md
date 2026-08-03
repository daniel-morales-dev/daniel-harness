# Regla global — Daniel Harness

Aplica a TODAS las sesiones de OpenCode, independientemente del proyecto activo.

## Inicio

1. Ejecuta `dh context` para detectar el contexto del proyecto activo.
2. Ejecuta `dh preflight` para obtener contexto completo del proyecto (JSON).
3. Las políticas del contexto activo están en `~/.config/daniel-harness/policies/`.
4. Usa CodeGraph antes de exploración amplia.

## Precedencia

1. Instrucción explícita del usuario.
2. `AGENTS.md` del proyecto activo.
3. Política del contexto.
4. Política global.
5. Default conservador.

## Autoridad

- Gentle AI decide routing directo/delegado/SDD y administra RDD.
- Daniel Harness decide contexto, repositorios, políticas, MCPs, Linear y seguridad.
- No reconstruyas receipts ni lifecycle de Gentle AI desde narración.
- No edites prompts, agentes o configuración generada por Gentle AI.

## Límites

- Nunca leas, imprimas, copies o versiones secretos reales.
- No trates un repositorio privado como secret storage.
- No modifiques assets migrados de Fase 1 salvo tarea explícita.
- No crees ramas sin preguntar.
- No edites automáticamente configuración OpenCode productiva.

## Recursos

- `bin/dh`: CLI unificada. Ver `dh help` para comandos.
- Las políticas de proyecto activo están en `~/.config/daniel-harness/policies/`.
- Si hay tarea Linear, ejecuta `dh session read <issue>` para crear una plantilla de brief.
  El agente debe usar `linear_get_issue` (Linear MCP) para poblarla con título,
  descripción, estado, asignado, subtareas y comentarios.
- `dh preflight` es la fuente única de contexto del proyecto.
