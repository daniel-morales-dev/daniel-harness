# Release smoke test

Procedimiento canónico para ejecutar `tests/release-smoke.test.sh`
sobre un SHA exacto en un entorno Ubuntu 24.04 limpio.

## v0.1.1 gates

Antes de declarar release readiness, ejecutar dos smokes sobre el mismo SHA final:

- Smoke A: instalación limpia, segundo run, doctor, agentes, MCPs, permisos y
  `bash tests/opencode-file-refs-runtime.test.sh` con OpenCode real.
- Smoke B: fixture de migración; preservar configuración no administrada,
  conflictos managed, symlinks de terceros, recovery, CAS e idempotencia.

Los logs sanitizados se guardan fuera del repositorio como `smoke-a-<sha>.log` y
`smoke-b-<sha>.log`. Nunca registrar valores de secretos; solo estados PASS/FAIL.

## Entorno

- Ubuntu 24.04 LTS limpio (contenedor o VM)
- Sin bind mount del repositorio
- Usuario no-root con sudo sin contraseña
- Docker (opcional, para contenedor)

## Procedimiento

```bash
EXPECTED_SHA='<commit-sha>'

# Crear contenedor (o arrancar VM)
docker run --name daniel-harness-smoke \
  ubuntu:24.04 bash -s <<'OUTER'
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  sudo git ca-certificates

useradd -m -s /bin/bash smoketest
printf '%s\n' \
  'smoketest ALL=(ALL) NOPASSWD:ALL' \
  > /etc/sudoers.d/smoketest
chmod 440 /etc/sudoers.d/smoketest

sudo -u smoketest -H bash -s <<'INNER'
set -euo pipefail

EXPECTED_SHA='<commit-sha>'

git clone \
  --single-branch \
  --branch <branch> \
  https://github.com/daniel-morales-dev/daniel-harness.git \
  "$HOME/harness"

cd "$HOME/harness"

actual_sha=$(git rev-parse HEAD)
if [[ "$actual_sha" != "$EXPECTED_SHA" ]]; then
  printf 'HEAD inesperado: %s; esperado: %s\n' \
    "$actual_sha" "$EXPECTED_SHA" >&2
  exit 1
fi

test "$(stat -c '%U' .)" = 'smoketest'

set +e
bash tests/release-smoke.test.sh 2>&1 |
  tee "$HOME/release-smoke-${EXPECTED_SHA:0:7}.log"
smoke_rc=${PIPESTATUS[0]}
set -e

{
  printf 'SMOKE_SHA=%s\n' "$actual_sha"
  printf 'SMOKE_EXIT=%s\n' "$smoke_rc"
} | tee -a "$HOME/release-smoke-${EXPECTED_SHA:0:7}.log"
exit "$smoke_rc"
INNER
OUTER
```

## Notas

### `set -e` y el log

`set -euo pipefail` en el script externo puede interrumpir la
ejecución antes de mostrar el `tail` del log si un paso interno falla.
Para evitar esto, capturar `PIPESTATUS` como en el ejemplo y salir con
ese código. El log completo queda escrito por `tee` y puede extraerse
después con `docker cp`.

### Sin bind mount

El repositorio debe clonarse dentro del contenedor como usuario no-root
(`smoketest`). El bind mount desde el host produce archivos con UID del
host, lo que activa la protección `safe.directory` de Git en Ubuntu
24.04. Aunque se puede configurar `safe.directory` globalmente, el
procedimiento canónico clona dentro del contenedor para evitar esta
complejidad.

### Extraer y verificar

```bash
# Recuperar log desde el contenedor
docker cp \
  daniel-harness-smoke:/home/smoketest/release-smoke-<sha>.log \
  ./release-smoke-<sha>.log

# Verificar resultado
grep 'SMOKE_EXIT=' release-smoke-<sha>.log

# Limpiar contenedor
docker rm daniel-harness-smoke
```

## Alternativa con rtk

`rtk docker` puede reemplazar a `docker` si `rtk` está disponible:

```bash
rtk docker run --name daniel-harness-smoke ...
rtk docker cp ...
rtk docker rm ...
```

El procedimiento con `docker` estándar es el principal; `rtk` es una
alternativa opcional.

## Historial de ejecuciones

| SHA | Perfil | Resultado | Entorno |
|-----|--------|-----------|---------|
| `70f7cb2` | todos | 37/37 exit 0 | Ubuntu 24.04 VM |
| `61e2686` | core | OK | Ubuntu 24.04 contenedor |
| `61e2686` | todos | inconcluso | contenedor local (entorno) |
