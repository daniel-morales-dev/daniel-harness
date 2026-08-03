# ADR 0005: Gentle AI como autoridad de workflow y RDD

## Estado

Aceptado

## Decisión

Gentle AI decide la ruta direct/delegated/optional SDD y administra RDD, receipts y recovery. Daniel Harness no usa tamaño o riesgo para forzar SDD y no reconstruye autoridad privada.

## Alternativa descartada

Mantener un clasificador propio `trivial/pequeño/mediano/grande/crítico` produciría dos orquestadores con decisiones incompatibles y acoplaría el harness a comportamiento que Gentle AI ya posee.

## Consecuencias

- El harness se concentra en contexto, policies, Linear, MCPs y seguridad.
- SDD requiere solicitud explícita o propuesta aceptada.
- Risk puede fortalecer review, pero no elegir SDD.
- La integración debe negociar capabilities y respetar adapters soportados.
