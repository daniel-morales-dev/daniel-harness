# Instrucciones para agentes

Este repositorio define la base estable de Daniel Harness.

## Inicio

1. Lee `docs/project-memory.md`.
2. Lee los ADR relevantes en `docs/adr/`.
3. Lee la política y el workflow del contexto activo.
4. Usa CodeGraph antes de exploración amplia.
5. Si hay una tarea Linear, carga `skills/task-lifecycle/SKILL.md`.

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
- Los comentarios técnicos no obvios van en español.

## Cambios

- Prefiere el cambio mínimo correcto.
- Mantén un writer por superficie compartida.
- Ejecuta tests y lint enfocados.
- Usa fixtures sintéticos; nunca pruebes con configuración real.
- Conventional Commit: type inglés, descripción española, máximo 120 caracteres.
- Commit, push y deploy dependen de autorización del proyecto.

## Recursos propios

- `agents/php-engineer.md`: PHP 7.0.9/ZF1.
- `skills/task-lifecycle/SKILL.md`: ciclo completo de tareas Linear.
- `skills/monolith-to-micro-migration/SKILL.md`: paridad PHP → TypeScript.

Los assets migrados de Fase 1 y sus checksums están en `docs/project-memory.md`.
