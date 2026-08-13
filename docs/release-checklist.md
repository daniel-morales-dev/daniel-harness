# Release Checklist

## v0.1.1

### Readiness

- [ ] CI verde en el SHA final: gitleaks, validate y e2e
- [ ] OpenCode `1.18.18` y capabilities verificadas
- [ ] `{file:...}` runtime: Authorization, URL y oauth.clientId
- [ ] Smoke A limpio sobre el SHA final
- [ ] Smoke B de migración sobre el mismo SHA final
- [ ] Secret leak scan sin coincidencias fuera de archivos intencionales
- [ ] Documentación y CHANGELOG `0.1.1 (Unreleased)` actualizados
- [ ] Worktree limpio y body de PR con evidencia real
- [ ] `transaction.py` coordinó config, secretos, cinco agentes y managed state
- [ ] GitHub/Navi `{file:...}` inválidos fallan cerrado; Navi parcial devuelve `2`
- [ ] Managed-modified y symlink de terceros devuelven `3` sin sobrescritura
- [ ] Hard crash/recovery y CAS concurrente verificados

### Release

- [ ] Merge
- [ ] Tag
- [ ] GitHub release

## v0.1.0

### Pre-release

- [ ] CI verde: validate, e2e y gitleaks pasan en main
- [ ] `bash -n` pasa en todos los scripts
- [ ] ShellCheck pasa
- [ ] `python3 -m pytest -q` pasa (número positivo de tests)
- [ ] `bun install --frozen-lockfile` pasa
- [ ] `bun run typecheck` pasa
- [ ] `bun run test:tools` pasa
- [ ] `--dry-run` no modifica el filesystem
- [ ] `--help` no modifica el filesystem
- [ ] Todos los failpoints preservan hashes exactos (transaction-failures)
- [ ] Lock no escribible falla cerrado
- [ ] Segunda instalación es idempotente
- [ ] Los cuatro perfiles generan opencode.json válido
- [ ] Data tools no se instalan por defecto
- [ ] Data tools experimentales siguen teniendo sus tests actuales verdes
- [ ] No hay secretos literales en el código
- [ ] No hay archivos pyc, caches o artefactos generados
- [ ] Git working tree queda limpio

### Smoke test

- [ ] Instalación real limpia en Ubuntu 24.04
- [ ] `bash tests/release-smoke.test.sh` pasa sin --stubs
- [ ] Segunda instalación idempotente
- [ ] `core → alegra → migration → full` funciona
- [ ] Doctor estricto pasa

### Release

- [ ] Número de versión en VERSION
- [ ] CHANGELOG.md actualizado
- [ ] Tag firmado o protegido
- [ ] Release notes publicadas
- [ ] Branch protection activada en main
- [ ] Checks requeridos configurados
- [ ] Rollback documentado
- [ ] Matriz de soporte: Ubuntu 24.04
- [ ] Decisión explícita sobre visibilidad pública

### Post-release

- [ ] Mover issues de data tools a milestone v0.2.0
- [ ] Comunicar release al equipo
