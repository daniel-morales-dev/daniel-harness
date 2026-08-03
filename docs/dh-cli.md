# dh CLI

`dh` es el entry point unificado de Daniel Harness. Se instala como symlink en `~/.local/bin/dh` mediante `install.sh` o `bootstrap.sh`.

## Subcomandos

### dh doctor

Ejecuta el diagnóstico completo del harness: herramientas, configuración, MCPs, túneles y repositorio.

```bash
dh doctor
```

### dh install

Crea o actualiza la configuración local y los symlinks de agentes, skills y comandos en OpenCode.

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

Salida: lista de servidores con estado (connected, failed, disabled), tipo (local/remote) y autenticación OAuth (authenticated, expired, not authenticated), más un resumen numérico.

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

### dh update

Actualiza el harness desde Git. Hace `git pull --ff-only` y avisa si cambiaron el manifest, `install.sh` o `bootstrap.sh` para sugerir re-ejecutarlos.

```bash
dh update
```

### dh project init

Asistente interactivo para registrar un nuevo proyecto en `project-registry.yaml`. Pide nombre, ruta absoluta, contexto y repositorio opcional. Valida que la ruta exista y que el contexto sea válido.

```bash
dh project init
```

### dh session \<issue\>

Crea un brief de sesión a partir de un ID de tarea Linear. Genera un archivo markdown en `~/.config/daniel-harness/sessions/<issue>.md` con la tarea, el contexto detectado, objetivos, criterios de aceptación y archivos afectados como plantilla.

```bash
dh session ENG-123
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
