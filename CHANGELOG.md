# Changelog

## 0.1.0 (2026-08-04)

### Added

- Release estable del harness base v0.1.0
- Perfiles: core, alegra, migration, full con herencia `extends`
- Instalación: `install.sh`, `bootstrap.sh`, `dh install`
- Diagnóstico: `doctor.sh` con `--strict`, detección de MCPs, túneles, secretos
- Preflight: `dh preflight` con detección de contexto
- Verify: `dh verify` con validación según contexto
- Update: `dh update` para actualizar desde Git
- OpenCode: configuración completa con plugins, MCPs y reconciliación
- Gentle AI: integración completa, skill-registry, agentes
- Agentes: 5 agentes administrados (alegra-microservice-engineer, code-reviewer,
  alegra-microservice-test-engineer, php-engineer, migration-parity-reviewer)
- Skills: task-lifecycle, monolith-to-micro-migration
- MCPs: codegraph, engram, linear, context7, wiki-alegra, github,
  sentry, navi con OAuth completo
- Reconciliación: detección de drift, protección de configuraciones personalizadas
- Transacción crash-consistente: journal, backups, rollback, failpoints
- Lock de concurrencia: protege state contra ejecución simultánea
- Dry-run: `--dry-run` no destructivo
- Runtime Python: venv administrado con `requirements-runtime.txt`
- NVM + Node.js 24 administrado
- Doctor: validación de permisos 600/700, secretos, túneles, MCPs vivos
- Redact: `redact-opencode-config.sh` para exportar config sin secretos
- Smoke test de release: `tests/release-smoke.test.sh`

### Security

- Lock temprano protege state contra escritura
- Backups obligatorios antes de modificar config o state
- Journal de transacción permite rollback exacto
- Failpoints para probar recuperación en cada fase
- Doctor detecta secretos hardcodeados, URLs con credenciales
- Rechazo de ambient credentials en data tools
- Navi externalizado: no expone ARN, client ID ni headers

### Experimental

- Closed Data Tools (MySQL, MongoDB, DynamoDB, Object Storage)
  - Activación: `--experimental-data-tools`
  - Estado: beta, no estables en v0.1.0
  - Requiere Python runtime venv y dependencias adicionales

### Known Limitations

- Closed data tools en beta, deshabilitadas por defecto
- OAuth de MCPs requiere autenticación manual con `opencode mcp auth`
- Ubuntu 24.04 es la plataforma soportada y verificada
- Túneles locales son manuales (SSH)
- El repositorio es privado; no se concede licencia pública
- Las políticas de data tools (policy gate común, fail-closed) se
  completarán en v0.2.0
