# ADR-0007: Comandos finales del harness — preflight, session, verify

**Fecha:** 2026-08-03

**Contexto:** Completar los tres items de baja prioridad del plan de corrección:
preflight (fuente única de contexto), session (lectura real de Linear), verify
(validación por contexto de proyecto).

**Decisión:**

1. **`dh preflight`**: Salida JSON con proyecto, contexto, familia, scope, policies,
   harnessRoot e issue. Consumible por `global/AGENTS.md` como contexto único.
   Implementado como función bash que combina `detect_context()` con lectura del
   `project-registry.yaml` y `$HARNESS_DIR/policies/`.

2. **`dh session`**: Dos subcomandos:
   - `scaffold <issue>`: plantilla sin API (fallback por defecto sin token)
   - `read <issue>`: consulta Linear GraphQL API vía `curl`. Token desde
     `LINEAR_API_KEY` o `~/.config/daniel-harness/secrets/tokens/linear.token`.
     Sin token → fallback automático a scaffold.

3. **`dh verify`**: Según contexto detectado ejecuta:
   - `generic-php`: `php -l` en archivos modificados
   - `alegra-microservice`/`generic-typescript`: `tsc --noEmit` + `npm test`
   - `generic-node`: `npm test`
   - `generic-go`: `go vet ./...`
   - `freelance`: mensaje informativo
   - `generic` (harness): ShellCheck + `bash -n` + tests

4. **Documentación**: `docs/dh-cli.md` actualizado con los tres comandos.
   `global/AGENTS.md` actualizado para referenciar `dh preflight` como disponible.

**Consecuencias:** Los 13 items del plan de corrección están completos.
El harness ahora tiene preflight (contexto JSON), session (Linear API opcional),
y verify (validación por contexto).
