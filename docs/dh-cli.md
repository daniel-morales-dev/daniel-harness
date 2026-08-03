# dh CLI

`dh` es el entry point unificado de Daniel Harness. Se instala como symlink en `~/.local/bin/dh` mediante `install.sh` o `bootstrap.sh`.

## Subcomandos

### dh doctor

Ejecuta el diagnóstico completo del harness: herramientas, configuración, MCPs, túneles, agentes y repositorio.
Detecta agentes con `bash: allow` bajo modelos `restricted`.

```bash
dh doctor
```

### dh root

Imprime la ruta absoluta del directorio del harness.

```bash
dh root
# /home/user/.config/daniel-harness
```

### dh preflight

Devuelve contexto completo del proyecto como JSON: proyecto, contexto, familia, scope, policies,
harnessRoot y estado de issue.

```bash
dh preflight
```

Salida (ejemplo):
```json
{
  "project": "api-alegra-bills-backend",
  "context": "alegra-microservice",
  "family": "alegra-bills",
  "scope": "single-repo",
  "policies": ["data-access.md", "git.md", "work-tracking.md"],
  "issue": null
}
```

Es la fuente única de contexto para `global/AGENTS.md`.

### dh install

Crea o actualiza la configuración local y los symlinks de agentes, skills, comandos y policies en OpenCode.

```bash
dh install
```

### dh bootstrap

Instalación completa desde cero: dependencias del sistema, Node.js, OpenCode, Gentle AI, Engram, CodeGraph, RTK, GitHub CLI, AWS CLI, Docker (opcional), plugins y MCPs.

```bash
dh bootstrap                # instalación completa
dh bootstrap --dry-run      # previsualizar sin cambios
dh bootstrap --skip-docker  # omitir Docker
```

### dh mcp-status

Muestra el estado de conexión y autenticación OAuth de todos los servidores MCP configurados en OpenCode.

```bash
dh mcp-status
```

Salida: lista de servidores con tipo (local/remote), habilitado y estado (disponible, no-probado, comando-no-encontrado).

### dh tunnel list

Lista los túneles configurados en `connections.yaml` con su endpoint local, si son requeridos y la referencia al comando.

```bash
dh tunnel list
```

### dh context [dir]

Detecta el contexto del proyecto activo. Busca primero en `project-registry.yaml` y si no encuentra coincidencia, usa heurística por lenguaje.

```bash
dh context                          # directorio actual
dh context /ruta/al/proyecto        # directorio específico
```

Salida: pares `clave=valor` con `proyecto`, `contexto`, `path` y `detectado_por`.

Contextos detectables (por heurística de lenguaje):
- `generic-php`: `composer.json` presente
- `generic-typescript`: `package.json` con TypeScript en devDependencies
- `generic-node`: `package.json` sin TypeScript
- `generic-go`: `go.mod` presente
- `generic`: ningún marcador conocido

Los contextos `alegra-monolith` y `alegra-microservice` solo se asignan desde
`project-registry.yaml`. La heurística NUNCA asigna Alegra por lenguaje.

### dh verify

Valida el proyecto actual según su contexto:

| Contexto | Verificación |
|---|---|
| `generic-php` | `php -l` en archivos modificados |
| `alegra-microservice` / `generic-typescript` | `tsc --noEmit` + `npm test` |
| `generic-node` | `npm test` |
| `generic-go` | `go vet ./...` |
| `freelance` | Remite a README del proyecto |
| `generic` | ShellCheck + `bash -n` + tests del harness |

```bash
dh verify
```

### dh update

Actualiza el harness desde Git. Hace `git pull --ff-only` y avisa si cambiaron el manifest, `install.sh` o `bootstrap.sh` para sugerir re-ejecutarlos.

```bash
dh update
```

### dh project init

Asistente interactivo para registrar un nuevo proyecto en `project-registry.yaml`.
Pide nombre, ruta absoluta, contexto y familia. Valida contra el schema.
El campo `repository` no está incluido (no declarado en schema).

```bash
dh project init
```

### dh session scaffold \<issue\>

Crea una plantilla de brief de sesión. No requiere API. Genera un archivo markdown
en `~/.config/daniel-harness/sessions/<issue>.md` con la tarea, contexto, objetivos
y criterios de aceptación.

```bash
dh session scaffold ENG-123
```

### dh session read \<issue\>

Crea una plantilla de brief e instruye al agente a poblar los datos del issue
usando Linear MCP (`linear_get_issue`). No requiere token local.

```bash
dh session read ENG-123
```

### dh engram-service

Gestiona Engram como servicio systemd user para que esté disponible en segundo plano sin necesidad de arrancarlo manualmente.

```bash
dh engram-service install    # crear el archivo de servicio
dh engram-service enable     # activar e iniciar el servicio
dh engram-service disable    # detener y desactivar
dh engram-service status     # ver estado del servicio
```

Después de `install`, ejecuta:

```bash
systemctl --user enable --now engram
systemctl --user status engram
```
