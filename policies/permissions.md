# Permisos de herramientas

Los permisos combinan scope, reglas del proyecto, confianza del modelo, entorno y capacidad.

## Defaults

- Lee documentación del proyecto antes de implementar.
- Usa CodeGraph para arquitectura, flujo, referencias e impacto.
- Pregunta antes de mutar producción, instalar dependencias, desplegar o crear rama.
- Niega acceso directo a rutas de secretos.
- Niega shell arbitrario a modelos restricted.

## Tools cerradas

Una tool cerrada posee el acceso a credenciales y aplica la política. Recibe parámetros no secretos, valida la operación y devuelve salida sanitizada.

RTK comprime salida; no concede ni restringe permisos.
