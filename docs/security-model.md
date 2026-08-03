# Modelo de seguridad

## Clases de activos

- Código y políticas versionadas.
- Configuración local no secreta.
- Credenciales y comandos de infraestructura.
- Código propietario y documentación interna.
- Datos de testing y producción.

Un repositorio privado protege visibilidad, pero no es secret storage.

## Frontera de confianza

Los executors trusted usan herramientas aprobadas. Los modelos restricted no reciben shell arbitrario ni lectura directa de secretos. Las tools cerradas cruzan la frontera con una operación estrecha y salida sanitizada.

## Limitación conocida

`read: deny` no aísla archivos si Bash puede invocar `cat`, intérpretes o clientes. RTK reduce volumen, no permisos.

## Túneles

Los endpoints locales y `commandRef` viven en `connections.yaml`. Los comandos reales viven en `secrets/tunnels/`, fuera de Git. Doctor puede revisar puerto, ruta y permisos; nunca lee o ejecuta el comando.

## Código propietario

La política definitiva para modelos restricted sigue abierta. Default: no enviar código propietario fuera de modelos y herramientas trusted aprobados.
