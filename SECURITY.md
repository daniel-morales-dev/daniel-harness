# Política de seguridad

## Reportar una exposición

Detén la operación e informa la clase de credencial y su ubicación sin citar el valor. No copies secretos en issues, chats, commits, logs o capturas.

## Respuesta

1. Considera comprometido todo secreto hardcodeado o compartido en texto plano.
2. Revócalo o rótalo en el sistema propietario.
3. Elimínalo de la configuración activa y usa una referencia externa.
4. Revisa historial Git y logs para medir propagación.
5. Aplica privilegio mínimo a la credencial nueva.

Reescribir historial requiere autorización separada. Rotar tiene prioridad porque borrar texto no invalida una credencial.

## Frontera de almacenamiento

El repositorio contiene código, políticas, schemas y ejemplos sintéticos. La configuración local del usuario vive en `~/.config/daniel-harness/`; los secretos viven bajo `secrets/` con directorios `700` y archivos `600`.

Nunca versiones tokens, passwords, API keys, claves privadas, URLs con credenciales, `.cnf`, comandos SSH reales, hosts internos, dumps, resultados de consultas o logs productivos.

Los comandos reales de túneles se guardan localmente en `secrets/tunnels/*.command`. El doctor solo muestra la ruta del archivo, nunca su contenido.

## Frontera de modelos

`read: deny` no aísla secretos si Bash u otro intérprete siguen disponibles. Los modelos restricted usan tools cerradas que reciben parámetros no secretos, aplican políticas internamente y devuelven resultados sanitizados.

## Mínimo privilegio

- MySQL/MariaDB operativo es siempre read-only.
- DynamoDB exige confirmación exacta de operación, profile, región, tabla, keys, campos y condición.
- El harness puede proponer un `GRANT`, pero nunca ejecutarlo.
- Mutaciones productivas requieren confirmación incluso con modelos trusted.
- El harness detecta túneles, pero nunca los abre o repara.

## Gentle AI y OpenCode

No edites archivos administrados por Gentle AI. Usa su installer, `gentle-ai sync`, capability negotiation y skill registry. La configuración OpenCode con headers o env debe redactarse antes de compartirla.
