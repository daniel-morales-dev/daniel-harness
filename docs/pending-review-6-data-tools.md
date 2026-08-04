# Plan de trabajo — Punto 10: Closed Data Tools

> **⚠️ ARCHIVO DE PLANIFICACIÓN TEMPORAL**
>
> Este archivo documenta el contexto completo para implementar el punto 10
> (closed data tools) del ciclo de review 6. Una vez que todos los commits
> 10a–10e estén completados, mergeados a main y verificados, **este archivo
> debe eliminarse** (`git rm docs/pending-review-6-data-tools.md`).
>
> Su propósito es exclusivamente transferir contexto entre sesiones de
> agente. No es documentación de usuario ni arquitectura permanente.

---

## Estado actual del repositorio

- **Branch:** `main` (último commit: `f28b1da`)
- **Harness NO instalado** — `dh` no existe, `bin/dh` no está en el PATH
- **Los commits 1–9 ya están en `main`** (squashed vía PR #9 desde `hardening/review-6`)
- **Commit 10a (framework) también está en `main`**
- **CI verde** en el último build: validate ✅ e2e ✅ gitleaks ✅ GitGuardian ✅
- **Repositorio público** en GitHub — esto limita la nota de seguridad a ~9.6 máximo

---

## Lo que ya está implementado (commits 1–9 + 10a)

### Commit 1 — python3-jsonschema runtime
- `bootstrap/manifest.yaml`: `python3-jsonschema` agregado a `system_packages.required`
- `tests/clean-runtime.test.sh`: verifica manifest + bootstrap con stubs de entorno limpio
- CI: incluido en job validate

### Commit 2 — Simetría install/uninstall
- `scripts/lib/managed-links.sh`: inventario compartido con `list_managed_links()`
- `scripts/install.sh`: consume el inventario via loop
- `scripts/uninstall.sh`: consume el mismo inventario
- `tests/install-symmetry.test.sh`: 46 assertions (instalación, desinstalación, preservación de personal files)

### Commit 3 — CodeGraph pin desde manifest
- `scripts/bootstrap.sh`: `CG_INSTALL=$(parse_nested_value "user_tools" "codegraph" "install")`
- `tests/harness.test.py`: `test_codegraph_pin_from_manifest()`

### Commit 4 — AWS CLI versionada desde manifest
- `bootstrap/manifest.yaml`: `version: "2.36.15"`, `url: "...-2.36.15.zip"`, `sha256: "02a8eb2..."` para aws
- `scripts/bootstrap.sh`: lee version/url/sha256 via `parse_nested_value`, construye install command con mktemp, trap, sha256sum -c
- `tests/harness.test.py`: `test_aws_pin_from_manifest()`

### Commit 5 — ROOT_DIR en doctor
- `scripts/doctor.sh`: schema/validator resueltos contra `ROOT_DIR`, no `REPOSITORY_DIR`
- `tests/harness.test.py`: `test_doctor_uses_root_dir_for_harness_components()`

### Commit 6 — CI unificada
- `.github/workflows/ci.yml`: 3 jobs (validate, e2e, gitleaks) con permissions, concurrency, timeout-minutes
- `validate.yml` y `e2e.yml` eliminados
- `tests/harness.test.py`: `test_no_duplicate_ci_workflows()`

### Commit 7 — Compatibility real
- `.github/workflows/compatibility.yml`: PyYAML, HTTP real con timeout, GITHUB_STEP_SUMMARY, versiones exactas
- Falla en drift crítico/checksum incorrecto, warning en transitorios
- MCP reachability: DNS + HTTP, acepta 200/204/400/401/403/404/405

### Commit 8 — Drift persistence
- `scripts/bootstrap.sh`: `_reconcile_mcp` retorna códigos (0=unchanged, 1=updated, 2=drift-conflict)
- Solo `return 0`/`return 1` agregan a `MANAGED_MCPS`; `return 2` (drift) no trackea en state
- Hash canónico via `jq -S -c`
- `tests/drift-three-run.test.sh`: 13 assertions (personalización sobrevive 3 ejecuciones, state correcto)

### Commit 9 — Transacción crash-consistent
- `scripts/bootstrap.sh`: flock, journal, failpoints deterministas (DH_TEST_MODE/DH_FAIL_AT)
- Backups obligatorios sin `|| true`, mktemp en directorios destino, trap con rollback atómico
- `tests/transaction-failures.test.sh`: 33 assertions (5 failpoints × 4 checks + recovery)

### Commit 10a — Data tools framework
- `scripts/dh_data/executor.py`: entry point JSON stdin → connections.yaml → profile → backend
- `scripts/dh_data/security.py`: validate_credential_ref (anti-traversal, permisos), read_credentials
- `scripts/dh_data/config.py`: helpers YAML/profile lookup
- `scripts/dh_data/redaction.py`: redact() + truncate() para output sanitizado
- `tools/dh-mysql-query.ts`, `dh-mongodb-query.ts`, `dh-dynamodb-read.ts`, `dh-dynamodb-write.ts`, `dh-object-storage-read.ts`: custom tools OpenCode con Zod schemas, invocan executor.py
- `agents/data-access.md`: agente con `edit: deny`, `bash: "*": deny`, `allowedCapabilities: [closed-data-tools]`
- `scripts/lib/managed-links.sh`: incluye tools/ y data-access agent
- `scripts/install.sh`: crea `$OPENCODE_CONFIG_DIR/tools/`

---

## Review original que motiva este trabajo

```
# Nueva calificación

El HEAD actual es `8c38b73`, con tres commits nuevos desde la ...

## Veredicto

El harness mejoró claramente en arquitectura y pruebas, pero el HEAD
actual `8c38b73` todavía tiene **dos bloqueantes funcionales** y **un
problema de seguridad conceptual** que impiden calificarlo cerca de 10/10:

1. Una instalación Ubuntu limpia no garantiza que `jsonschema` esté
   disponible.
2. La detección de drift puede "adoptar" una personalización y
   sobrescribirla en la siguiente ejecución.
3. Los nuevos "closed data tools" son comandos-prompt que delegan Bash
   a un agente; no son herramientas cerradas con enforcement ejecutable.

El conector no mostró checks asociados al commit, por lo que la
evaluación se basa en el código de `main`.

### Calificación actual

| Área                            | Anterior |     Actual |
| ------------------------------- | -------: | ---------: |
| Arquitectura general            |      9.5 |    **9.5** |
| Subagentes                      |      9.6 |    **9.6** |
| Seguridad                       |      8.7 |    **8.4** |
| Instalación de agentes y skills |      9.7 |    **9.4** |
| Instalación desde cero          |      9.2 |    **8.1** |
| Instalación de MCPs             |      9.2 |    **8.7** |
| Rapidez del bootstrap           |      9.1 |    **9.2** |
| Experiencia inicial             |      9.1 |    **8.4** |
| CI y pruebas                    |      9.4 |    **9.2** |
| Automatización operativa        |      9.2 |    **8.8** |
| **Global**                      |  **9.3** | **8.9/10** |

La reducción no significa que los últimos cambios sean malos. El
validador compartido, la librería MCP, los Actions fijados y la
compatibilidad semanal son mejoras fuertes. La nota baja porque los
nuevos componentes revelan contratos que aún no están completamente
cerrados.

# Lo que quedó muy bien

## Validador único de OpenCode

Bootstrap y doctor ya comparten `validate-opencode-config.py`, que usa
`jsonschema` para validar el documento completo, no solo campos
seleccionados. Esta es la dirección correcta y elimina divergencias
entre CI y runtime.

## Health check MCP compartido

`classify_mcp_debug_output` salió de los tests y quedó en una librería
consumida por doctor. Ahora el test prueba la misma función productiva,
no una copia de sus regex.

## Supply chain de CI

`checkout` y `setup-python` quedaron fijados por SHA en los workflows
nuevos. Gitleaks también continúa fijado por SHA.

## Fixtures E2E

Usar la configuración real como base, en lugar de objetos vacíos que no
cumplían el schema, mejora mucho la representatividad de la suite.

## Compatibilidad semanal

El workflow programado para revisar drift del schema, DNS y packages es
útil como señal preventiva y no ralentiza cada PR.

# Bloqueantes P0

## 1. Falta `jsonschema` como dependencia runtime

El nuevo validador ejecutable importa:

```python
import jsonschema
```

y termina con código `2` si el módulo no existe.

Bootstrap lo ejecuta antes de aplicar la configuración MCP:

```bash
python3 scripts/validate-opencode-config.py ...
```

Pero los paquetes obligatorios solo incluyen:

```yaml
python3
python3-pip
python3-yaml
```

No incluyen `python3-jsonschema`, ni bootstrap instala
`requirements-dev.txt`.

CI oculta el problema porque instala explícitamente:

```bash
pip install pyyaml jsonschema
```

antes de ejecutar los tests.

En una máquina limpia, el flujo puede ser:

```text
bootstrap
→ genera candidato
→ validator falla porque falta jsonschema
→ candidato no se aplica
→ doctor falla
```

### Corrección

La alternativa simple para Ubuntu 24.04:

```yaml
system_packages:
  required:
    - python3-jsonschema
```

La alternativa más aislada:

```text
~/.local/share/daniel-harness/venv
```

creado por el instalador, con versiones fijadas y usado por todos los
scripts Python.

### Test necesario

`tests/clean-runtime.test.sh` debe ejecutarse sin el `pip install`
previo de CI y garantizar:

```text
HOME limpio
sin jsonschema preinstalado
→ bootstrap instala sus dependencias
→ validator funciona
→ perfil core termina en 0
```

## 2. El drift se preserva solo durante una ejecución

Cuando `_reconcile_mcp` detecta que el usuario modificó un MCP
administrado, lo preserva y aumenta `MCP_SKIPPED`. Sin embargo, después
el nombre igualmente termina dentro de `MANAGED_MCPS`. `_build_state`
calcula el nuevo `lastAppliedHash` usando el contenido actual de
`opencode.json`, es decir, la personalización del usuario.

La secuencia resultante puede ser:

```text
1. Harness instala GitHub y guarda hash A.
2. Usuario modifica GitHub; configuración pasa a B.
3. Bootstrap detecta B != A y conserva B.
4. State se actualiza con hash B.
5. Siguiente bootstrap ve current == lastAppliedHash B.
6. Reemplaza B por la configuración del manifest.
```

El test actual solo ejecuta la primera reconciliación después del
drift. No ejecuta una tercera vez.

### Corrección

Un MCP omitido por drift no debe actualizar su `lastAppliedHash`.

Conviene devolver un resultado explícito:

```text
unchanged
updated
created
custom-unmanaged
drift-conflict
```

Solo `created`, `updated` y `unchanged` deben actualizar el state.

### Test necesario

```text
install alegra
→ modificar manualmente github
→ bootstrap alegra
→ bootstrap alegra otra vez
→ github sigue personalizado
→ lastAppliedHash sigue representando la última versión aplicada
  por el harness
```

## 3. Los data tools todavía no son herramientas cerradas

Los cinco nuevos archivos son **custom commands de OpenCode**. La
documentación oficial define custom commands como prompts enviados al
modelo; no son executors con validaciones de seguridad embebidas. Las
opciones documentadas del frontmatter son `description`, `agent`,
`subtask` y `model`; `mode` y `argument-hint` no constituyen mecanismos
de permiso o aislamiento. ([OpenCode][1])

Por ejemplo, `mysql-query.md` solo instruye al modelo para:

* leer credenciales;
* validar SQL;
* ejecutar `mysql`;
* limitar filas;
* ocultar secretos.

No hay parser, timeout ni enforcement ejecutable.

Además, todos delegan en `alegra-microservice-engineer`, que tiene:

```yaml
edit: allow
bash: ask
```

`ask` solicita aprobación para Bash, pero no limita el proceso a
SELECT, no impide que el modelo construya otro comando y no convierte
el prompt en una sandbox. Los permisos de OpenCode se aplican por tools
y patrones de comandos; son independientes del texto de una custom
command. ([OpenCode][2])

`allowedCapabilities: [closed-data-tools]` solo aparece en el schema,
ejemplo y tests; no encontré runtime que traduzca esa capability a
permisos reales de OpenCode.

### Caso especialmente delicado: DynamoDB write

La política declara `exact-operation`, pero el command considera
suficiente responder:

```text
sí
confirmo
adelante
```

Eso no es confirmación de la operación exacta. Una confirmación exacta
debe incluir nuevamente, o referenciar mediante un nonce inmutable:

```json
{
  "operation": "UpdateItem",
  "profile": "...",
  "region": "...",
  "resource": "...",
  "keys": {},
  "fields": {},
  "condition": "..."
}
```

### Arquitectura correcta

```text
OpenCode custom tool
  ↓ input JSON validado
dh-data executor
  ↓ policy + credentials internos
driver seguro
  ↓ salida sanitizada y limitada
```

Controles necesarios:

* MySQL: credencial DB read-only, una sola sentencia, timeout, límite,
  bloqueo de `INTO OUTFILE`, `LOAD_FILE`, procedimientos y mutaciones.
* Mongo: input JSON estructurado, no `--eval` construido por
  concatenación; bloqueo de `$out`, `$merge` y JavaScript.
* DynamoDB read: IAM read-only.
* DynamoDB write: rol separado, preview canónico y confirmación exacta.
* Object storage: IAM `GetObject`, límites de tamaño, archivo temporal
  `600` y cleanup.
* Los secretos se leen dentro del executor y nunca se entregan al
  modelo.

Hasta implementar eso, los archivos deberían llamarse **guided data
commands**, no closed data tools, y no deberían habilitarse para
modelos restricted.

# Hallazgos P1

## 4. La transacción sigue siendo best-effort, no completamente atómica

La mejora es importante: ahora construye config y state antes de
aplicar, valida ambos y trata de restaurar backups.

Sin embargo:

* `TMP_CANDIDATE` y `TMP_STATE` se crean con `mktemp` general,
  normalmente en `/tmp`;
* mover desde `/tmp` a `~/.config` puede cruzar filesystems y dejar
  de ser un rename atómico;
* config y state se mueven secuencialmente;
* la creación de backups sigue usando `|| true`;
* un fallo del `chmod` final bajo `set -e` puede terminar el script
  antes de alcanzar la lógica de rollback.

El test de state failure tampoco verifica el contrato nuevo. Ejecuta
el bootstrap con `|| true`, por lo que `RC=$?` siempre queda en cero,
y solo comprueba que `opencode.json` exista. Sus comentarios todavía
dicen que el state failure es no fatal.

### Corrección

Crear temporales dentro de cada directorio destino:

```bash
mktemp "$(dirname "$OC_FILE")/.opencode.json.XXXXXX"
mktemp "$STATE_DIR/.opencode-managed.json.XXXXXX"
```

No continuar si el backup requerido no pudo crearse. También conviene
usar `trap` para rollback ante `ERR`, `INT` y `TERM`.

### Test requerido

Simular fallos separados de:

* construcción del state;
* backup;
* `mv` del config;
* `mv` del state;
* `chmod` del state.

En todos:

```text
exit != 0
hash config después == hash config antes
hash state después == hash state antes
```

## 5. CodeGraph continúa sin pin en el instalador real

El manifest fue actualizado a:

```yaml
npm install -g @codegraph/cli@1.2.0
```

pero bootstrap todavía ejecuta:

```bash
npm install -g @codegraph/cli
```

La supply chain real sigue sin fijarse. El manifest y el runtime tienen
dos fuentes diferentes de verdad.

La mejor corrección es que bootstrap lea `user_tools.codegraph.install`
del manifest. Como mínimo, agregar un test que garantice igualdad entre
ambos.

## 6. El checksum de AWS está unido a una URL móvil

Bootstrap descarga:

```text
awscli-exe-linux-x86_64.zip
```

sin versión en la URL, pero compara el archivo con un hash fijo.

Cuando AWS cambie el artefacto servido por esa URL, una instalación
nueva fallará aunque el archivo sea legítimo.

Debe fijarse una versión concreta:

```text
awscli-exe-linux-x86_64-<version>.zip
```

y su checksum correspondiente, o verificar la firma oficial del
release.

## 7. Doctor puede omitir el validator cuando cambia `DANIEL_HARNESS_REPO`

Doctor usa `REPOSITORY_DIR` para localizar:

```text
tests/fixtures/opencode-config.schema.json
scripts/validate-opencode-config.py
```

Pero `REPOSITORY_DIR` puede apuntar al proyecto que se está
diagnosticando, no al repositorio del harness. En ese caso el schema no
existe allí y el bloque simplemente se omite.

Los componentes del harness deben resolverse mediante:

```bash
ROOT_DIR
```

El proyecto inspeccionado debe continuar usando:

```bash
REPOSITORY_DIR
```

### Test necesario

```text
DANIEL_HARNESS_REPO=/tmp/proyecto-externo
opencode.json inválido por schema
→ doctor sigue encontrando el validator del harness
→ doctor termina en 1
```

## 8. Uninstall no elimina los cinco data commands

`install.sh` enlaza los cinco comandos nuevos.

`uninstall.sh` solo elimina `migration-gap-analysis.md`; no elimina los
nuevos enlaces.

La prueba existente de consistencia install/uninstall solo compara el
enlace de `AGENTS.md`, no todos los recursos administrados.

Debe extraerse un único inventario:

```bash
MANAGED_LINKS=(
  ...
)
```

consumido por install y uninstall, o construir un test que compare
todos los targets de `link_if_missing` y `remove_managed_link`.

## 9. CI ejecuta trabajo duplicado

Actualmente hay:

* `ci.yml`, con validate, E2E y Gitleaks;
* `validate.yml`;
* `e2e.yml`.

Los tres se disparan en push y pull request.

Eso ejecuta varias validaciones y el E2E más de una vez. También hay
diferencias de dependencias:

```text
ci.yml       → requirements-dev.txt
validate/e2e → pip install pyyaml jsonschema
```

Conviene conservar un solo workflow con tres jobs:

```text
validate
e2e
gitleaks
```

y un workflow separado programado para compatibilidad.

## 10. Compatibility comprueba menos de lo que anuncia

La fase "MCP endpoint DNS/HTTP reachability" solamente ejecuta
resolución DNS; no realiza ninguna petición HTTP. La disponibilidad npm
consulta la última versión de CodeGraph, no específicamente `1.2.0`.
Todos los errores se convierten en avisos sin notificación persistente.

Como workflow informativo está bien. Para acercarse a 10 debería:

* comprobar el package exacto;
* revisar la imagen/digest de Raia;
* verificar la URL/version/checksum de AWS;
* probar HTTP sin enviar credenciales;
* abrir automáticamente un issue cuando haya drift sostenido.

# Tests prioritarios restantes

## P0

1. **Clean runtime**
   * sin `jsonschema` preinstalado;
   * bootstrap debe instalarlo y terminar correctamente.

2. **Drift de tres ejecuciones**
   * una personalización debe preservarse indefinidamente, no solo una
     vez.

3. **State/config transaction failure**
   * fallos de backup, move y chmod;
   * ambos archivos deben conservar sus hashes anteriores.

4. **Data tool enforcement**
   * después de implementar executors reales;
   * probar inputs maliciosos, timeouts, límites, credenciales y
     confirmación exacta.

## P1

5. **Install/uninstall inventory symmetry**
6. **Manifest/runtime pin consistency**
7. **Doctor con `DANIEL_HARNESS_REPO` externo**
8. **OpenCode schema para `migration` y `full`**
   * actualmente el test directo de schema solo recorre `core` y
     `alegra`.
9. **Compatibility exact versions**
10. **Workflow no duplicado**

# Proyección

Después de resolver los cuatro P0:

| Área                   |  Proyección |
| ---------------------- | ----------: |
| Seguridad              |         9.3 |
| Instalación desde cero |         9.6 |
| MCPs                   |         9.5 |
| CI                     |         9.6 |
| Automatización         |         9.4 |
| Global                 | **9.5–9.6** |

Para alcanzar 9.8 o más todavía quedarían:

* data tools ejecutables y aisladas;
* supply chain completamente fijada;
* repo privado;
* releases/tags verificables;
* crash consistency real;
* comprobación de compatibilidad con endpoints auténticos.

## Conclusión

La base del harness está en un nivel alto: arquitectura compartida,
reconciliación con state, schemas, perfiles, agentes especializados,
E2E y compatibilidad programada.

La principal prioridad no es agregar más comandos ni agentes. Es:

1. hacer autocontenidas las dependencias runtime;
2. corregir la persistencia de drift;
3. convertir los data commands en herramientas cerradas reales;
4. cerrar atomicidad y simetría de instalación.

La evaluación honesta del HEAD actual es **8.9/10**. El diseño está
cerca de 9.5, pero la garantía ejecutable todavía no.

[1]: https://opencode.ai/docs/commands/ "Commands | OpenCode"
[2]: https://opencode.ai/docs/permissions/ "Permissions | OpenCode"
```

---

## Especificación completa del punto 10

### Arquitectura

```text
OpenCode custom tool (.ts con Zod)
  ↓ input JSON validado por schema
dh-data executor (scripts/dh_data/executor.py)
  ↓ policy + credenciales internos (nunca al modelo)
driver específico (mysql.py, mongodb.py, dynamodb.py, object_storage.py)
  ↓ salida sanitizada y limitada
respuesta JSON al modelo
```

### Composición final de scripts/dh_data/

| Archivo | Responsabilidad |
|---------|----------------|
| `executor.py` | Entry point: lee JSON stdin, carga connections.yaml, busca profile, delega al backend |
| `config.py` | Helpers YAML, profile lookup, harness dir |
| `security.py` | `validate_credential_ref()` (anti-traversal, permisos 600), `read_credentials()` |
| `redaction.py` | `redact()` (patrones password/secret/token/aws_), `truncate()` (límites) |
| `mysql.py` | Conexión MySQL read-only, parser sentencia única, bloqueo de peligrosas, LIMIT, timeout |
| `mongodb.py` | PyMongo estructurado, bloqueo $out/$merge/$where/$function/mapReduce, límite docs |
| `dynamodb.py` | `handle_read()` (GetItem/Query/Scan allowlisted), `handle_write()` (2-step confirmation) |
| `object_storage.py` | boto3 GetObject, ContentLength check, límite 10MB, streaming, cleanup |

### Composición final de tools/

| Archivo | Tool name | Zod inputs |
|---------|-----------|------------|
| `dh-mysql-query.ts` | `dh_mysql_query` | profile, sql, params? |
| `dh-mongodb-query.ts` | `dh_mongodb_query` | profile, collection, filter?, projection?, pipeline? |
| `dh-dynamodb-read.ts` | `dh_dynamodb_read` | profile, operation (GetItem|Query|Scan), tableName, params |
| `dh-dynamodb-write.ts` | `dh_dynamodb_write` | profile, operation (PutItem|UpdateItem), tableName, keys, fields, condition?, token? |
| `dh-object-storage-read.ts` | `dh_object_storage_read` | profile, bucket, key |

### Lo que NO necesita cambiarse

- `scripts/lib/managed-links.sh` — ya incluye tools/ y data-access agent
- `scripts/install.sh` — ya crea `$OPENCODE_CONFIG_DIR/tools/`
- `agents/data-access.md` — ya tiene `edit: deny`, `bash: "*": deny`
- `scripts/dh_data/executor.py` — ya delega con `from dh_data.mysql import handle`
- `scripts/dh_data/security.py` — ya tiene validate_credential_ref y read_credentials
- `scripts/dh_data/redaction.py` — ya tiene redact() y truncate()

### Lo que SÍ debe crearse o modificarse

#### 10b — MySQL + MongoDB backends

**Crear** `scripts/dh_data/mysql.py`:
```python
def handle(profile, credentials, operation, params):
    # operation: "query"
    # params: {"sql": "...", "params": {...} (opcional)}
    #
    # 1. Validar que la sentencia comience con SELECT/SHOW/DESCRIBE/EXPLAIN
    # 2. Rechazar multi-statement (; seguido de otra sentencia)
    # 3. Bloquear INTO OUTFILE, LOAD_FILE, procedimientos, locks
    # 4. Conectar: mysql --defaults-extra-file=<creds> -h 127.0.0.1 -P <port> --batch --raw -e "<sql>"
    # 5. Timeout 30s, limit 1000 filas
    # 6. Convertir salida tabular a array de objetos JSON
    # 7. Redactar secretos en output
    # 8. Devolver {"rows": [...], "truncated": true/false}
```

**Crear** `scripts/dh_data/mongodb.py`:
```python
def handle(profile, credentials, operation, params):
    # operation: "find" | "aggregate"
    # params: {"collection": "...", "filter": {}, "projection": {}, "pipeline": []}
    #
    # 1. Usar PyMongo MongoClient con URI desde credentials
    # 2. Validar que pipeline no contenga $out/$merge/$where/$function/mapReduce
    # 3. Bloquear JavaScript (no $where, no mapReduce)
    # 4. find() con limit(1000), aggregate con límite similar
    # 5. Timeout 30s
    # 6. Devolver {"documents": [...], "truncated": true/false}
```

**Crear** `tests/data-mysql.test.py`:
- SQL con INSERT/UPDATE/DELETE/DROP → policy violation (exit 2)
- SQL con INTO OUTFILE → policy violation
- SQL con LOAD_FILE → policy violation
- SQL multi-statement (SELECT 1; DROP TABLE x) → policy violation
- SQL válido SELECT → success con rows
- SQL SELECT con LIMIT > 1000 → truncated: true
- Timeout simulado → runtime error (exit 1)
- Secretos en output → redactados

**Crear** `tests/data-mongodb.test.py`:
- Pipeline con $out → policy violation
- Pipeline con $merge → policy violation
- Pipeline con $where → policy violation
- Pipeline con mapReduce → policy violation
- find() válido → success con documents
- Pipeline sin $match → warning pero permitido
- Timeout simulado → runtime error

#### 10c — DynamoDB read

**Crear** `scripts/dh_data/dynamodb.py`:
```python
def handle_read(profile, credentials, operation, params):
    # credentials: aws-profile://<profile-name>
    # operation: "GetItem" | "Query" | "Scan"
    # params: {"tableName": "...", "key": {}, ...}
    #
    # 1. Usar boto3 con AWS_PROFILE desde credentials
    # 2. Solo permitir GetItem, Query, Scan
    # 3. Scan con explicit limit (max 100)
    # 4. Timeout 30s
    # 5. Devolver {"items": [...], "count": N}
```

**Crear** `tests/data-dynamodb-read.test.py`:
- PutItem → policy violation
- DeleteItem → policy violation
- BatchWriteItem → policy violation
- GetItem con keys → success
- Scan sin filter pero con limit → limited results

#### 10d — DynamoDB write 2-step

**Ampliar** `scripts/dh_data/dynamodb.py`:
```python
TOKEN_STORE = {}  # nonce -> {"payload": {...}, "expires": timestamp}

def handle_write(profile, credentials, operation, params):
    # operation: "prepare" | "confirm"
    # params (prepare): {"tableName", "keys", "fields", "condition?"}
    # params (confirm): {"token", "tableName", "keys", "fields", "condition?"}
    #
    # PREPARE:
    # 1. Generar preview canónico del payload completo
    # 2. Crear token = sha256(payload + timestamp + random)
    # 3. Guardar en TOKEN_STORE con expiración 60s
    # 4. Devolver {"confirmationRequired": true, "preview": {...}, "token": "..."}
    #
    # CONFIRM:
    # 1. Buscar token en TOKEN_STORE
    # 2. Si no existe → "Token expirado o inválido" (exit 4)
    # 3. Comparar payload completo (tableName, keys, fields, condition)
    # 4. Si difiere → "Payload no coincide con el preview" (exit 4)
    # 5. Eliminar token (no replay)
    # 6. Ejecutar PutItem/UpdateItem
    # 7. Devolver {"attributes": {...}}
```

**Crear** `tests/data-dynamodb-write.test.py`:
- Token expirado → confirmation invalid (exit 4)
- Token reutilizado (replay) → confirmation invalid
- Payload diferente (keys cambiadas) → confirmation invalid
- Confirmación exitosa → attributes devueltos

#### 10e — Object storage + markdown commands + doctor + E2E

**Crear** `scripts/dh_data/object_storage.py`:
```python
def handle(profile, credentials, operation, params):
    # credentials: AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY desde credentialsRef
    # operation: "get-object"
    # params: {"bucket": "...", "key": "..."}
    #
    # 1. boto3 client con endpoint_url del túnel
    # 2. HeadObject primero para ContentLength
    # 3. Si >10MB: devolver metadata, no contenido
    # 4. Si <=10MB: GetObject con streaming
    # 5. Temp file cleanup con trap
    # 6. Detectar content type, devolver contenido o metadata
```

**Actualizar** `commands/mysql-query.md`:
```markdown
# MySQL Query

Ejecuta consulta SELECT via custom tool dh_mysql_query.

1. Lee connections.yaml, busca profile.
2. Construye JSON con profile y SQL.
3. Invoca dh_mysql_query con el JSON.
4. Devuelve resultado JSON.
```

(Similar para los otros 4 commands: mongodb-query → dh_mongodb_query,
dynamodb-read → dh_dynamodb_read, dynamodb-write-confirmed →
dh_dynamodb_write, object-storage-read → dh_object_storage_read)

**Actualizar** `scripts/doctor.sh`:
- Agregar verificación de existencia de `tools/dh-mysql-query.ts` (y otros 4)
- Agregar verificación de existencia de `agents/data-access.md`
- Agregar verificación de que data-access.md tiene `bash: "*": deny`

**Crear** `tests/data-object-storage.test.py`:
- Path traversal en key → policy violation
- Binario >10MB → metadata only
- Timeout simulado → runtime error
- Secretos en output → redactados

**Crear** `tests/data-e2e.test.sh`:
- Ejecutar install.sh en HOME temporal
- Verificar que tools/ y agent existen
- Ejecutar uninstall.sh
- Verificar que tools/ y agent se eliminaron
- Ejecutar doctor.sh (con stubs) y verificar que data-access agent está presente

**Actualizar** `.github/workflows/ci.yml`:
- Agregar steps al job e2e para: data-mysql.test.py, data-mongodb.test.py,
  data-dynamodb-read.test.py, data-dynamodb-write.test.py,
  data-object-storage.test.py, data-e2e.test.sh

**Actualizar** `docs/project-memory.md`:
- Agregar sección de data tools con enlaces a executor, herramientas y agente

---

## Plan de commits (10b–10e)

| Sub-commit | Archivos nuevos | Archivos modificados | Tests |
|------------|----------------|---------------------|-------|
| **10b** | `scripts/dh_data/mysql.py`, `scripts/dh_data/mongodb.py`, `tests/data-mysql.test.py`, `tests/data-mongodb.test.py` | — | SQL multi-statement, INTO OUTFILE, LOAD_FILE, $out/$merge/$where, timeout, truncation |
| **10c** | `scripts/dh_data/dynamodb.py` (handle_read), `tests/data-dynamodb-read.test.py` | — | PutItem/DeleteItem/BatchWriteItem reject, GetItem/Query/Scan success, timeout |
| **10d** | `tests/data-dynamodb-write.test.py` | `scripts/dh_data/dynamodb.py` (handle_write) | Token expirado, replay, payload diferente, confirmación exitosa |
| **10e** | `scripts/dh_data/object_storage.py`, `tests/data-object-storage.test.py`, `tests/data-e2e.test.sh` | `commands/*.md` (5), `scripts/doctor.sh`, `.github/workflows/ci.yml`, `docs/project-memory.md` | Path traversal, binario >10MB, install/uninstall simétrico, doctor detecta, CI |

---

## Reglas para la sesión que implemente esto

1. **Branch:** crear `feat/closed-data-tools` desde `main`
2. **Commits:** uno por sub-commit (10b, 10c, 10d, 10e)
3. **Tests:** dentro del mismo commit que el código que prueban
4. **Push + CI verde** antes del siguiente commit
5. **No directo a main:** PR al final con validate, e2e, gitleaks
6. **Al terminar:** `git rm docs/pending-review-6-data-tools.md`

### Notas técnicas

- `executor.py` ya hace `from dh_data.mysql import handle` — solo crear el módulo
- Las importaciones desde `scripts/dh_data/` funcionan sin `__init__.py` ejecutando
  `python3 scripts/dh_data/executor.py` desde el root del repo
- Los tests correr con: `python3 tests/data-mysql.test.py`
- CI ejecuta desde `.github/workflows/ci.yml` — agregar steps al job `e2e`
- OpenCode custom tools requieren TypeScript y Zod — ya están creadas en `tools/`
- Los exit codes del executor: 0=ok, 1=runtime error, 2=policy violation, 3=confirmation required, 4=confirmation invalid
- `security.py` chequea prefijos permitidos: secrets/mysql/, secrets/mongodb/, secrets/tunnels/, secrets/tokens/
- `redaction.py` redacta password/secret/token/aws_ patterns automáticamente
- Los markdown commands actuales están en `commands/` — actualizar las restricciones
  y apuntar a las custom tools `dh_*`
- `docs/project-memory.md` existe y tiene una sección de seguridad donde agregar
  la documentación de data tools

---

## Documentos de referencia externos

- [Custom Tools | OpenCode](https://opencode.ai/docs/custom-tools/)
- [Permissions | OpenCode](https://opencode.ai/docs/permissions/)

---

> **⚠️ RECORDATORIO: Cuando todos los commits 10b–10e estén implementados,
> mergeados a main y CI esté verde, ejecutar:**
>
> ```bash
> git rm docs/pending-review-6-data-tools.md
> git commit -m "docs: eliminar plan temporal de review-6 data tools"
> git push
> ```
>
> Este archivo es planificación temporal, no documentación permanente.
