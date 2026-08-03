# Tooling transversal

## Orden de uso

| Herramienta | Responsabilidad |
|---|---|
| CodeGraph | Comprender arquitectura, flujo, callers e impacto antes de leer ampliamente. |
| Engram | Recuperar y persistir decisiones, fixes, convenciones y cierres de sesión. |
| Ponytail | Elegir la solución mínima correcta después de entender el flujo. |
| Caveman | Reducir comunicación cuando el detalle completo no fue solicitado. |
| RTK | Comprimir salida de shell, tests y logs. |
| Gentle AI | Routing, SDD opcional, review y receipts. |

## Límites

- Ponytail no simplifica seguridad, validación, accesibilidad ni prevención de pérdida de datos.
- Caveman modifica respuestas al usuario, no nombres, código, documentación o evidencia requerida.
- CodeGraph no reemplaza compiladores, lint o tests.
- Engram no recibe secretos.
- RTK no es un sistema de permisos.
- Ninguna herramienta reconstruye autoridad privada de Gentle AI.
