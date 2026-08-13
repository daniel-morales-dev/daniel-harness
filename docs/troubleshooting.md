# Troubleshooting

## Bootstrap falla con "crítico" en doctor

El doctor puede reportar críticos por varias razones:

**Falta de herramientas**: Ejecuta el bootstrap de nuevo, o instala manualmente:

```bash
sudo apt-get install jq gh
```

## Gentle AI no reporta `healthy`

La instalación falla cerrada si `gentle-ai skill-registry refresh --force`,
`gentle-ai sync` o `gentle-ai doctor` no completan saludables. `gentle-ai doctor`
puede devolver cero aun con `Status:  degraded`; corregí primero los warnings que
enumera y repetí la instalación.

## Conflicto o recovery incompleto

`./install` devuelve `3` para un recurso administrado modificado y `4` cuando el
rollback/recovery no terminó. No borres journal ni sobrescribas el recurso: ejecutá
de nuevo el bootstrap para recuperación y conservá el archivo modificado para revisión.

**Permisos incorrectos**: Verifica que `~/.config/daniel-harness/` sea `700` y los archivos `600`:

```bash
chmod 700 ~/.config/daniel-harness
chmod 600 ~/.config/daniel-harness/config.yaml
chmod 600 ~/.config/daniel-harness/connections.yaml
```

**MCP requiere autenticación**:

```bash
opencode mcp auth <nombre-del-mcp>
```

**Falta NAVI_MCP_URL o NAVI_OAUTH_CLIENT_ID**:

```bash
export NAVI_MCP_URL="https://tu-servidor-navi/mcp"
export NAVI_OAUTH_CLIENT_ID="tu-client-id"
```

## Bootstrap se queda en "Otro bootstrap en ejecución"

Una ejecución anterior no terminó correctamente. Elimina el lock manualmente:

```bash
rm -f ~/.config/daniel-harness/state/.bootstrap.lock
```

## Transacción incompleta

Si el bootstrap se interrumpió (crash, cierre de terminal), el bootstrap siguiente
detecta el journal y recupera automáticamente.

Para recuperación manual:

```bash
# Verificar si hay journal
ls ~/.config/daniel-harness/state/.bootstrap-journal.json

# Ejecutar bootstrap de nuevo (recupera y continúa)
./scripts/bootstrap.sh --profile core
```

## "No se pudo crear lock (estado no escribible)"

El directorio de estado no es accesible. Verifica permisos:

```bash
ls -la ~/.config/daniel-harness/state/
```

## Doctor reporta secretos hardcodeados

El doctor detecta literales con nombres de token/secret/password en `opencode.json`.
Usa referencias `{env:VARIABLE}` o `{file:ruta}` en lugar de valores literales.

## Data tools no disponibles

Los closed data tools están deshabilitados por defecto en v0.1.0.
Actívalos con:

```bash
./scripts/install.sh --experimental-data-tools
./scripts/bootstrap.sh --profile alegra --experimental-data-tools
```

## Error de schema en opencode.json

Valida el archivo contra el schema oficial:

```bash
python3 scripts/validate-opencode-config.py \
  --config ~/.config/opencode/opencode.json \
  --schema tests/fixtures/opencode-config.schema.json
```

## Reportar errores

Abre un issue en: https://github.com/daniel-morales-dev/daniel-harness/issues

Incluye:
- Salida de `dh doctor`
- Versión del harness (`dh version` o `cat VERSION`)
- Perfil usado
- Pasos para reproducir
