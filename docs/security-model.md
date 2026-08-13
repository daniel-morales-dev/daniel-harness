# Modelo de seguridad

## Principios

1. **Un repositorio privado no es un almacén de secretos.**
   Los secretos nunca deben estar en el código versionado del harness.

2. **Los secretos viven fuera de opencode.json.**
   GitHub tokens, Navi URL/client-id, y cualquier credencial se almacenan
   en `~/.config/daniel-harness/secrets/` con permisos restrictivos.

3. **Los secretos nunca se imprimen.**
   Los comandos de diagnóstico (`dh opencode diff`, `dh opencode backups`)
   muestran estructura pero nunca valores.

## Almacenamiento de secretos

### GitHub

- Archivo: `~/.config/daniel-harness/secrets/github/authorization`
- Formato: `Bearer <token>`
- Permisos: `600`
- Directorio: `700`
- Referencia en opencode.json: `{file:~/.config/daniel-harness/secrets/github/authorization}`

### Navi

- URL: `~/.config/daniel-harness/secrets/navi/url` (600)
- Client ID: `~/.config/daniel-harness/secrets/navi/client-id` (600)
- Directorio: `700`
- Referencias en opencode.json: `{file:...}`

### Migración automática

Durante `--connect`, el instalador detecta:
- Tokens literales en opencode.json → migra a archivo
- Variables de entorno (`{env:GITHUB_PERSONAL_ACCESS_TOKEN}`) → migra a archivo
- Referencias a archivo existentes → valida permisos y reutiliza

La referencia efectiva de OpenCode debe apuntar al archivo administrado exacto.
No se consideran saludables symlinks, archivos vacíos, permisos distintos de `600`,
padres inseguros ni formatos que no comiencen con `Bearer `.

## Backups

Los backups de opencode.json se crean automáticamente antes de cada
modificación. Se almacenan en `~/.config/daniel-harness/backups/` (700).
Cada backup tiene modo `600`.

`dh opencode diff` solo muestra diferencias estructurales, nunca valores.

## Permisos del sistema

| Recurso | Permiso | Propósito |
|---|---|---|
| `~/.config/daniel-harness/` | 700 | Solo el usuario |
| `~/.config/daniel-harness/secrets/` | 700 | Solo el usuario |
| `~/.config/daniel-harness/secrets/**/*` | 600 | Solo lectura propietario |
| `~/.config/daniel-harness/state/` | 700 | Estado administrado |
| `~/.config/daniel-harness/backups/` | 700 | Backups de configuración |
| `~/.config/daniel-harness/backups/*` | 600 | Backups individuales |

## Modelos restricted

Cuando `config.yaml` define modelos con trust `restricted`:
- No se concede shell arbitrario (`permission.bash` debe ser `deny`).
- Los agentes no tienen acceso directo a secretos.
- OpenCode no debe tener valores sensibles hardcodeados.

## Túneles

Los comandos de túnel viven en `~/.config/daniel-harness/secrets/tunnels/`:
- Permisos: `600`.
- Contienen comandos SSH reales, con credenciales.
- Nunca se versionan.
- Se ejecutan manualmente; el harness verifica conectividad pero no los almacena.

## OpenCode

- La configuración de OpenCode está en `~/.config/opencode/opencode.json`.
- El harness solo modifica propiedades declaradas en su allowlist:
  - `plugin[]` (solo entrada Ponytail)
  - `mcp.codegraph.*`
  - `mcp.engram.*`
  - `mcp.context7.*`
  - `mcp.github.*`
  - `mcp.linear.*`
  - `mcp.wiki-alegra.*`
  - `mcp.navi.*`
  - `mcp.sentry.*`
- Todo lo demás (agentes, permisos, providers, perfiles, etc.) es propiedad
  del usuario o de Gentle AI.
- El candidato siempre se construye desde una copia exacta de la
  configuración activa.

## Agentes administrados

Los 5 agentes del harness se instalan como copias regulares (no symlinks):
- Si un agente fue modificado localmente, no se sobrescribe (conflicto).
- Si es un symlink propiedad del harness, se migra a copia.
- El estado administrado registra hashes para detectar modificaciones.

## Commit de secretos

Ningún fixture, test, log, diff, backup, estado, PR body o GitHub Action
debe contener secretos reales.

El gate manual `bash tests/opencode-file-refs-runtime.test.sh` usa valores dummy y
un HOME aislado para comprobar `{file:...}` en Authorization, URL y oauth.clientId.
