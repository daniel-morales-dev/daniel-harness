# Workflow freelance

## Preparación

1. Resuelve el proyecto en `project-registry.yaml`.
2. Lee sus reglas locales antes de aplicar defaults globales.
3. Aplica `task-lifecycle` si el trabajo tiene issue.
4. Ejecuta doctor y confirma los túneles requeridos.

## Trabajo

- Usa el stack y convenciones reales del proyecto; no importes reglas de Alegra automáticamente.
- Mantén scope `single-repo` salvo relación explícita.
- Usa datos read-only por default.
- MongoDB writes requieren confirmación mientras la política siga abierta.
- Garage y bases se acceden solo mediante endpoints locales configurados.

## Entrega

Ejecuta checks del proyecto, resume riesgos y sigue su política Git/deploy. Los comandos de túnel permanecen locales y manuales.
