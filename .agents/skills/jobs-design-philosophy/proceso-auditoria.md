# Proceso de auditoría — Jobs Design Philosophy

Usar solo cuando la tarea pide un diagnóstico completo de una pantalla o app, no para un ajuste puntual (para eso basta `SKILL.md`).

## Fase 1 — Diagnóstico de la app

1. Inventario de pantallas y focos: ¿cuáles son las 3 tareas/flujos principales?
2. Auditoría de complejidad visual: elementos interactivos vs. jerarquía.
3. Fricción: clics/toques para terminar la tarea principal (Test del Bizqueo).
4. Respiro y alineación: ¿se usa correctamente el whitespace y la rejilla de 8pt?

## Fase 2 — Puntuación (1-10)

| Principio | Puntuación | Problema detectado |
|---|---|---|
| Simplicidad radical y formas | X/10 | ... |
| Whitespace y padding | X/10 | ... |
| Jerarquía visual y rejillas | X/10 | ... |
| Foco en el usuario / flujos | X/10 | ... |
| Consistencia / radios / biseles | X/10 | ... |

Diagnóstico global: resumen de los problemas principales.

## Fase 3 — Plan de adaptaciones priorizadas

- **Crítico**: rompe obviedad o simplicidad. Arreglar agrupaciones y reducir acciones por pantalla.
- **Importante**: degrada la experiencia. Padding, rejilla 8pt, eliminación de dividers/ruido.
- **Refinamiento**: micro-interacciones, radios concéntricos, biseles sutiles.

## Fase 4 — Implementación

- Justificar el razonamiento espacial (p. ej. "aumento el padding a 24dp para aislar el contenedor primario").
- Refactorizar componentes UI monolíticos en partes más pequeñas si el cambio lo requiere.
- No modificar lógica de negocio ni estado subyacente.

## Checklist final

- [ ] Espaciado, margen y padding en múltiplos de 8 (o 4 en excepciones menores).
- [ ] Radios de contenedores anidados concéntricos.
- [ ] Dividers innecesarios eliminados en favor de whitespace.
- [ ] Supera el Test del Aire y el Test del Bizqueo.
- [ ] Cada pantalla tiene una única tarea principal obvia.
- [ ] Tipografía con jerarquía clara (máximo 3 niveles/pesos).
- [ ] Sin impacto en lógica de negocio o estado de la app.
