# Changelog

## 0.1.1 (2026-08-14)

### Fixed (release readiness)

- `install` preserva los códigos `0/1/2/3/4` de bootstrap y no ejecuta doctor
  después de onboarding pendiente, conflicto o recovery incompleto.
- El resumen de GitHub reconoce la autorización persistente segura sin depender
  de `GITHUB_PERSONAL_ACCESS_TOKEN`.
- OpenCode exige la versión mínima probada `1.18.18` y capabilities reales.
- Gentle AI falla cerrada ante registry no saludable y, con autenticación
  configurada, ante sync o doctor no saludables; sin `GAIA_KEY` estos dos pasos
  dependientes de cuenta se omiten y la instalación local puede continuar.
- Referencias GitHub/Navi `{file:...}` inválidas fallan cerradas sin reparar permisos,
  imprimir secretos ni publicar cambios parciales.
- Navi diferencia configuración corrupta (`1`) de onboarding legítimo (`2`).

### Added (release readiness)

- Gate runtime con OpenCode real para `{file:...}` en Authorization, URL y
  oauth.clientId; URL y Authorization verifican recarga dinámica.
- `scripts/transaction.py` es el único coordinador productivo: recovery, validación,
  apply, CAS, rollback y verificación de commit.
- Integración del coordinador para agentes, secretos y estado, con hard crash/recovery,
  conflicto managed e idempotencia de mtime.

### Added (tercera ronda)

- Journal como array ordenado con resources[], cada recurso tiene applyOrder,
  status (prepared→applying→applied), candidateSha256 y originalSha256
- `_mv_safe`: desplaza original, publica candidato, detecta modificación concurrente
- `_fsync`: helper Python con path como argv, fail-closed
- `_enforce_allowlist`: comparación canónica de .agent, .permission, .provider,
  .model, plugins externos, MCPs personalizados y claves desconocidas
- Backup con metadata JSON (.meta) usando ID único timestamp+random
- `opencode_backup_find_all`: busca backups modernos y legacy
- `alegra-code-reviewer`: nuevo nombre para evitar colisión con Gentle AI
- `_validate_secret_file` en doctor: modo 600, ownership, no symlinks, Bearer prefix
- `--connect + --non-interactive` detectado como error inmediato
- `tests/managed-state.test.sh`: 21 tests de transacción, allowlist, perfiles, secretos

### Changed (tercera ronda)

- Transacción: coordina opencode.json, state, secretos GitHub/Navi, los cinco agentes
  y managed files mediante el coordinador Python tipado.
- Secretos: temp en mismo directorio que destino, no en /tmp
- `full` perfil ahora extiende `migration`, que extiende `alegra`, que extiende `core`
- Profile selector usa `profile-resolver.sh` para mostrar valores efectivos heredados
- Gentle AI: comandos reales verificados (--version, sync, skill-registry)
- Doctor: sin debilitamiento para full sin --connect (exit 2, no saludable)

### Fixed (tercera ronda)

- SC2034: eliminada variable `all_or_nothing` no usada
- SC2168: `local` fuera de función en apply block movido a función
- Diff estructural: `.plugins` → `.plugin` (singular), añadidas más secciones
- Allowlist primer arranque: salta cuando no existe config previa
- E2E Phase 11: ahora usa perfil alegra + linear auth-required

### Added

- Selector interactivo de perfil en `./install` cuando no se pasa `--profile`
- Flag `--non-interactive`: falla si falta `--profile`, no hace prompts
- Flag `--reset-managed`: reinstala solo recursos administrados del harness
- Flag `--connect` en bootstrap: autenticación interactiva de MCPs
- GitHub secret migration: token literal/env → archivo persistente (600)
- Navi secret migration: URL/clientId literal/env → archivos persistentes (600)
- Sentry MCP siempre en perfil full, sin preguntar
- Backup/restauración de opencode.json via `dh opencode backup|backups|restore|diff`
- Agentes como copias administradas (no symlinks) con estado y detección de conflicto
- Managed state: `state/opencode-managed.state` con hashes por recurso
- Version check de OpenCode (mínimo 0.1.0)
- Gentle AI flow: inspección de versión/help, sync solo si soporta OpenCode
- Doctor `--install-check --skip-oauth`: solo validación estructural, sin probes
- `DH_MCP_PROBE_TIMEOUT_SECONDS` (default 3) para timeout de probes MCP
- Cache de probes MCP en doctor (cada MCP consultado máximo una vez)
- `list_managed_files()` en managed-links.sh para recursos como copias
- `opencode_backup_create/list/restore/diff` en `scripts/lib/opencode-backup.sh`
- Validación estructural de secretos migrados en doctor
- Secretos GitHub y Navi en `~/.config/daniel-harness/secrets/`

### Changed

- `install` ya no usa PROFILE=core como default silencioso
- Perfiles migración y full ahora extienden alegra (no core)
- Bootstrap respeta dry-run para version check de OpenCode
- Doctor reporta Navi desde archivos primero, env como fallback
- Doctor verifica agentes cargados por OpenCode (no solo existencia de archivo)
- `uninstall.sh` elimina managed files (copias) además de symlinks
- Tests actualizados para managed copies en lugar de symlinks
- Stubs de opencode en tests soportan `--version`

### Removed

- Default silencioso PROFILE=core en install

### Security

- Secretos GitHub/Navi fuera de opencode.json, en archivos modo 600
- `dh opencode diff` solo muestra estructura, nunca valores
- Directorios de secretos: modo 700
- Backup de configuración antes de cada modificación de opencode.json

### Fixed

- `local` fuera de función en bootstrap.sh (bash 5.2 no lo permite)
- Dry-run ya no invoca gentle-ai real (evita state files en HOME falso)
- Stubs de opencode en tests ahora soportan `--version`

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
- Validación temprana de credenciales en data tools
- Navi externalizado: no expone ARN, client ID ni headers

### Experimental

- Closed Data Tools (MySQL, MongoDB, DynamoDB, Object Storage)
  - Activación: `--experimental-data-tools`
  - Estado: beta, no estables en v0.1.0
  - Requiere Python runtime venv y dependencias adicionales

### Known Limitations

- Closed data tools en beta, deshabilitadas por defecto
- OAuth de MCPs requiere autenticación manual con `opencode mcp auth`
- Ubuntu 24.04 es la plataforma soportada
- Túneles locales son manuales (SSH)
- No se concede licencia pública
- Las políticas de data tools (policy gate común, fail-closed) se
  completarán en v0.2.0
