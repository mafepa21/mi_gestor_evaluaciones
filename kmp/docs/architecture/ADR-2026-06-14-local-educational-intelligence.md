# ADR 2026-06-14 - Inteligencia Educativa local estructurada

## Estado

Aceptado.

## Contexto

La app ya dispone de datos docentes estructurados en KMP: cuaderno, medias, asistencia, rubricas, evidencias, tendencias y radar docente. Foundation Models aporta valor si convierte esa evidencia en objetos breves para SwiftUI, pero no debe convertirse en una fuente de verdad ni controlar la interfaz.

## Decision

La Inteligencia Educativa local se implementa como una capa Swift sobre datos existentes:

- KMP calcula hechos, medias, pesos, columnas incluidas/excluidas, pendientes y tendencias.
- Foundation Models genera objetos Swift renderizables, no texto libre como contrato principal.
- SwiftUI presenta esos objetos en contexto, sin chat generico ni navegacion decidida por el modelo.
- Todo caso debe tener fallback determinista local cuando Foundation Models no este disponible.

La primera entrega vive en el inspector del Cuaderno con:

- `StudentInsightDraft`
- `AverageExplanationDraft`
- `TutorMeetingSummaryDraft`
- `StudentInsightEvidence`

La segunda entrega aplica el mismo criterio a informes:

- `StudentReportSummary` es el objeto estructurado para fortalezas, aspectos a vigilar, areas de progreso, recomendaciones y versiones docente/familia.
- `AIReportDraft` se mantiene como envoltorio compatible para las vistas existentes y para texto editable/exportable.

La tercera entrega inicia el mismo criterio en Educacion Fisica:

- `PhysicalProgressAnalysis` resume estado, fortalezas, debilidades, recomendaciones y alertas desde snapshots de pruebas fisicas.
- La primera integracion es por grupo/test en la pestaña Informes; no persiste datos ni recalcula marcas.

La cuarta entrega inicia IA preventiva:

- `EarlyWarning` clasifica severidad, causas, evidencia, recomendaciones y confianza desde `StudentInsightEvidence`.
- La primera integracion vive en el inspector del alumno; no persiste alertas ni crea decisiones automaticas.

## Consecuencias

- No se recalculan medias ni pesos en Swift ni en Foundation Models.
- Los prompts deben incluir evidencia acotada y trazable.
- Las futuras ampliaciones preventivas deben seguir el mismo patron: datos KMP, objeto Swift, UI nativa.
- Cualquier cambio que requiera datos nuevos debe justificarse antes de tocar `KmpBridge.swift`, `kmp/shared` o `kmp/data`.
