# ADR 003: Pestaña de evaluación con pesos por bloque

Fecha: 2026-11-24 · Estado: aceptado · Ticket: `docs/planes/ticket_pestana_evaluacion_pesos_2026-11-24.md`

## Contexto

Cada pestaña del Cuaderno tenía su propia Media. El docente organiza el trimestre por situaciones de aprendizaje (una pestaña por SA), así que nada reunía la evaluación entera. Hacían falta dos niveles de peso: el de cada nota en su bloque y el de cada bloque en la evaluación.

## Decisión

- La jerarquía que ya existía en datos (`notebook_tabs.parent_tab_id`, sincronizada) define la evaluación: una pestaña raíz con hijas es una evaluación y sus hijas son los bloques.
- Migración 50: `notebook_tabs.weight REAL` (NULL = mismo peso que los demás) y tabla `quick_note_phrases` (fichas propias, borrado lógico).
- La nota de evaluación se calcula en KMP (`NotebookEvaluation`), no en Swift. Es Σ peso del bloque × media del bloque / Σ pesos de los bloques con nota. Un bloque sin notas no cuenta como 0.
- El Resumen no copia columnas: muestra las de sus bloques con categorías de mentira (`evalblock:<id>`), que no se guardan.
- Borrar una evaluación suelta sus bloques (ViewModel y repositorio). `upsertTab` pasa a `ON CONFLICT DO UPDATE` para que guardar un padre nunca arrastre a las hijas.
- Sync: `weight` va siempre en el payload de pestaña. Si falta la clave (dispositivo antiguo), se conserva el valor local. Las fichas viajan por `ModuleRecordsSync`.

## Consecuencias

- Hay que actualizar iPad y Mac a la vez. Una versión antigua solo enseña pestañas raíz: tras organizar, los bloques no se verían allí. Si borrara una evaluación, borraría en cascada sus bloques.
- Los grupos de trabajo generales de una evaluación se comparten entre sus bloques (`NotebookWorkGroupPolicy.canonicalTabId`, regla ya existente).
- Si una pestaña raíz ya tenía columnas propias antes de tener hijas, esas columnas se ven en el Resumen pero no entran en la nota de evaluación.
