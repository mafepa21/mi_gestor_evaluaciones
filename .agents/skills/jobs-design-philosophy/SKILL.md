---
name: jobs-design-philosophy
description: Analiza cualquier app y propone adaptaciones aplicando la filosofía de diseño de Steve Jobs: simplicidad radical, formas básicas, espacios generosos (whitespace), rejillas disciplinadas (8pt) y reducción de carga cognitiva. Úsalo cuando quieras refactorizar o auditar la UI/UX de una aplicación con los principios de Apple bajo la era Jobs.
version: 3.0.0
---

# Jobs Design Philosophy

Diseño de interfaces con geometría simple, espaciado consistente y whitespace, para minimizar la carga cognitiva.

## Principios

- **Simplicidad radical**: una pantalla, una tarea principal obvia. Eliminar todo lo que no aporte valor funcional o emocional directo.
- **Foco absoluto en el usuario**: cero fricción en el flujo principal; opciones avanzadas ocultas, camino obvio siempre correcto.
- **Jerarquía visual**: un único elemento de mayor peso por pantalla; tipografía (tamaño/peso/espaciado) comunica jerarquía sin depender de color.
- **Consistencia**: patrones de interacción predecibles; sin gestos ni metáforas inventadas sin razón.
- **Interacciones que desaparecen**: la mejor interacción es la que el usuario no recuerda haber hecho.

## Reglas de espaciado

- Espaciado, márgenes y padding en múltiplos de 8 (`8dp`, `16dp`, `24dp`, `32dp`, `48dp`, `64dp`); 4 solo para microajustes tipográficos puntuales.
- Elementos relacionados a 8dp de separación; grupos distintos a 32-48dp.
- Si el whitespace ya separa visualmente, elimina el divider.
- Radios de contenedores anidados concéntricos: `R_int = R_ext - padding`.

## Validación antes de cerrar un cambio

- **Test del Bizqueo**: entrecerrando los ojos, ¿qué resalta? ¿es la acción primaria?
- **Test del Aire**: ¿hay margen suficiente para que la vista descanse entre bloques?
- **Test de la Obviedad**: sin leer texto, ¿es evidente la jerarquía y cómo interactuar?

## Alcance del cambio

Modificación quirúrgica: no tocar lógica de negocio subyacente salvo petición expresa. Si el cambio contradice una regla de `AGENTS.md`, actualizar `AGENTS.md` en el mismo cambio.

## Auditoría completa de una pantalla o app

Para un diagnóstico exhaustivo con puntuación y plan de fases (no para un ajuste puntual), cargar `proceso-auditoria.md` en este mismo directorio.
