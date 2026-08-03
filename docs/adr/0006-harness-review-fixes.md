# ADR-0006: Correcciones post-revisión del harness

**Fecha:** 2026-08-03

**Contexto:** Una revisión externa identificó 12 hallazgos en el harness, incluyendo
regresiones (plugin→plugins), MCPs inválidos, instalación de NVM rota en limpio,
registro de proyecto que genera YAML inválido, y permisos de agentes no documentados.

**Decisión:** Se aplicaron las correcciones en orden de criticidad:

1. **bootstrap.sh**: `plugins`→`plugin` (OpenCode usa key singular). MCPs locales
   generan `type: local`. MCPs remotos se saltan (no crear objetos incompletos).
2. **NVM**: Reemplazar `parse_value` roto por curl directo a versión fija.
3. **project init**: Default incluye `relationships: []`. Pregunta familia.
   Valida contra schema antes de escribir. Omite `repository` (no declarado en schema).
4. **AGENTS.md global**: Separado en `global/AGENTS.md` (regla global, usa `dh preflight`)
   vs raíz `AGENTS.md` (regla local para desarrollo del harness).
5. **uninstall.sh**: Agrega limpieza del symlink global.
6. **permisos agents**: Eliminado `write` (no documentado). code-reviewer restringido a
   read-only con excepciones para git diff/show/status.
7. **mcp_status**: Guard para sección MCP faltante.
8. **docs**: Contextos `alegra-monolith`/`alegra-microservice` actualizados.
9. **Tests**: Suite `tests/harness.test.py` cubre todos los hallazgos.
10. **CI**: Workflow con ShellCheck + validación schemas + tests + Gitleaks.

**Consecuencias:** bootstrap.sh ya no genera configuración inválida de OpenCode.
Los tests detectan regresiones en plugin key, MCPs, registry y permisos.
Queda pendiente: conectar `dh session` a Linear MCP, comando `dh preflight`.
