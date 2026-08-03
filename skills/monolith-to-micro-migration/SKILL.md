---
name: monolith-to-micro-migration
description: >
  Migra comportamiento observable de alegra-app PHP al microservicio de Bills
  TypeScript. Activa solo ante una intención explícita de migración o paridad.
---

# Monolith → micro migration (bills backend)

Traducir comportamiento del monolito (`alegra-app`, PHP 7.0.9/ZF1) al microservicio
(`api-alegra-bills-backend`, TypeScript). NO copiar archivos completos — solo el
fragmento acordado.

## Inputs

| Input | Uso |
|---|---|
| **Goal** | Qué debe hacer el equivalente TS (una oración) |
| **Source fragment** | PHP, diff, o líneas del monolito |
| **Linear task** | ID (ej. ACEXPEN-1876): criterios de aceptación y alcance |
| **Target file** | Si ya está claro; si no, el agente propone tras inspeccionar el repo |

## No fallbacks ni suposiciones (obligatorio)

- No agregues fallbacks (`??`, `||`) si el monolito no los tiene para ese caso.
- No inventes comportamiento: expandí el fragmento leyendo el método completo en `alegra-app`, o pregunta con archivo:línea.
- Si un helper PHP no tiene equivalente TS: deja `// TODO: <ISSUE-ID> — descripción` y reporta el gap.
- Únicos valores default aceptables: los que el monolito ya codifica.

## Flujo obligatorio

### 1. Scope

Del fragmento, extrae reglas de negocio que pertenecen al dominio Bill en el micro
vs side effects (inventario, writes fuera del agregado). Lo que NO pertenece al
micro: deja TODO + issue y nota en Linear si aplica.

### 2. Mapa monolito ↔ micro

Encuentra el punto de inserción en el TS backend. Compara métodos PHP con
entidades TS (Bill, BillCategory, BillTax, etc.). Identifica feature flags,
metadata, país/applicationVersion y constantes existentes.

### 3. Diseño de migración

- Path único cuando el monolito bifurca (evitar ramas duplicadas).
- Sin magic strings: constantes dedicadas en `shared/constants/` con `as const`.
- Complejidad cognitiva máxima 10 por función (ESLint).
- Early return, helpers, policy object. Sin ternarios anidados.
- Tipos explícitos en contratos públicos/API. `import type { Bill }` para el agregado.
- Nombres de archivo: camelCase + sufijo (`.util.ts`, `.mapper.ts`). Sin guiones en nombres nuevos.
- Métodos <50-60 caracteres; si el nombre describe un proceso completo, dividir.
- MySQL repos: solo SELECT. UPDATE/INSERT/DELETE → TODO con alternativa.
- Repositorio = SQL + binding + delegación a mapper. Row→DTO en `shared/database/mappers/`.
- Interfaces en `shared/database/repositories/interfaces/`.
- Una responsabilidad por repositorio. Lecturas de tablas fuera del agregado van en repositorio dedicado.
- Resultado vacío → `null`. Falla de driver → `logger.error` + rethrow.

### 4. Implementación

- Toca solo archivos necesarios para el fragmento acordado.
- Mantén estilo del archivo target.
- Paridad por comportamiento observable (montos, ramas, orden, contrato API).
- Mejora estructura sin romper el contrato. Si un fix de calidad cambia un monto o campo, necesita acuerdo explícito.

### 5. Verificación

- Tests unitarios en el área tocada (patrón existente del proyecto).
- `npm test` en tests relevantes + consumidores directos.
- `npm run lint`.
- `npm run type-check` (tsc --noEmit) — ESLint no reemplaza TypeScript.
- Si un test falla: diagnosticar (regresión real vs mock desactualizado vs try/catch ocultando error).

## Delivery

- Lista numerada de archivos cambiados y qué hace cada cambio.
- Riesgos por país/flag donde el comportamiento difiera del monolito.
- Decisiones (una oración cada una).
- Mensaje de commit sugerido (Conventional Commits, type en inglés, descripción español, ≤120 chars). NO ejecutar git.

## Linear

Si hay issue vinculado y el trabajo está verificado (tests + lint verdes):
1. Comentario de cierre (Linear MCP `save_comment`): resumen breve en español.
2. Estado Done (`save_issue` con `state: Done`).

## Anti-patterns resumen

- Error messages al cliente con detalles internos (DB, campos, PHP).
- Copia ciega del monolito (ramas enormes, duplicación item/category).
- Migrar calls que persisten otros bounded contexts sin decisión explícita.
- Fat repository (interfaces, mapRow, JSON parsing en mismo archivo que SQL).
- Fat repository ownership (queries de metadata-admin en CompanyRepository).
- Error en DB → catch + warn + null (debe ser logger.error + rethrow).
- Comentarios ruidosos de migración (equivalencia monolito en PR, no en código).
- Fallbacks/defaults inventados que no aparecen en el monolito.
- Ocultar ignorancia (preferir TODO + delivery honesto sobre implementación adivinada).
- Ejecutar git commit (solo proponer mensaje).
