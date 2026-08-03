# Configurar Daniel Harness

La configuración versionada contiene schemas y placeholders. Los valores reales viven en `~/.config/daniel-harness/`.

## Ruta rápida

```bash
./scripts/install.sh
./scripts/doctor.sh
```

## Archivos

| Archivo local | Contenido |
|---|---|
| `config.yaml` | Gentle AI, tooling, modelos, Linear y MCP routing. |
| `connections.yaml` | Perfiles locales, puertos, datos y referencias de túneles. |
| `project-registry.yaml` | Familias, proyectos, relaciones, reglas y Git. |
| `secrets/tunnels/*.command` | Comandos SSH reales. |
| `secrets/mysql/`, `mongodb/`, `tokens/` | Credenciales locales referenciadas. |

## Túneles

El harness no abre túneles. Cada perfil usa el host/puerto local y una referencia:

```yaml
- id: ejemplo-mysql
  host: 127.0.0.1
  port: 12345
  tunnel:
    required: true
    commandRef: secrets/tunnels/ejemplo-mysql.command
```

Guarda el comando real en `~/.config/daniel-harness/secrets/tunnels/ejemplo-mysql.command`, aplica `chmod 600` y ejecútalo manualmente:

```bash
bash ~/.config/daniel-harness/secrets/tunnels/ejemplo-mysql.command
```

Para agregar un túnel, añade el perfil y crea su archivo local. Para eliminarlo, borra el perfil y luego el archivo. `doctor.sh` informa el `id`, endpoint local y `commandRef` cuando está cerrado.

No guardes hosts remotos, usuarios SSH, key paths o comandos reales en el repositorio.

Perfiles locales configurados:

| Perfil | Endpoint local | Archivo del comando |
|---|---|---|
| `hopper` | `127.0.0.1:60001` | `secrets/tunnels/alegra-hopper.command` |
| `production` | `127.0.0.1:55000` | `secrets/tunnels/alegra-production.command` |
| `k-agencia-mysql` | `127.0.0.1:3306` | `secrets/tunnels/k-agencia-mysql.command` |
| `k-agencia-mongodb` | `127.0.0.1:27017` | `secrets/tunnels/k-agencia-mongodb.command` |
| `k-agencia-garage` | `127.0.0.1:3900` | `secrets/tunnels/k-agencia-garage.command` |

## MCPs

Hay dos capas:

1. Gentle AI/OpenCode administra la conexión real del MCP.
2. `config.yaml#mcpRouting` indica qué servidor satisface cada capacidad y el estado esperado.

La configuración runtime de OpenCode está en `~/.config/opencode/opencode.json`. No edites prompts/agentes generados. Para una entrada MCP user-owned, usa interpolación `{env:VAR}` o `{file:path}` en lugar de valores literales:

```json
{
  "mcp": {
    "example": {
      "type": "remote",
      "url": "{env:EXAMPLE_MCP_URL}",
      "headers": {
        "Authorization": "Bearer {env:EXAMPLE_MCP_TOKEN}"
      },
      "enabled": true
    }
  }
}
```

Agrega o elimina conexiones mediante Gentle AI o una entrada user-owned que `gentle-ai sync` preserve. Después ajusta `mcpRouting`, reinicia OpenCode, ejecuta doctor y verifica que un sync posterior no elimine la entrada. Redacta el archivo antes de compartirlo.

## Proyectos y reglas

En `project-registry.yaml`:

1. Añade el proyecto dentro de su `family`.
2. Define path absoluto, contexto y archivos de reglas.
3. Configura política Git.
4. Añade relaciones con otros repositorios cuando exista migración o dominio compartido.

Para eliminar un proyecto, elimina primero relaciones que lo referencien y luego su entrada. Los secretos y túneles no se borran automáticamente.

## Modelos y comportamiento

`config.yaml` separa trusted/restricted y declara CodeGraph, Engram, Ponytail y Caveman. No otorgues shell amplio a restricted.

## Validación

Los schemas viven en `schemas/`; los ejemplos en `examples/`. Usa fixtures sintéticos para probar cambios y nunca copies configuración productiva al repo.
