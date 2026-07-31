# Instrumentos de autoevaluación/coevaluación ponderables — 2026-07-31

## Alcance

Las siete SA de 1º de Bachillerato pasan a llevar **un** instrumento que rellena el alumnado y que
cuenta en la nota (10 % en todas, restado de otro instrumento para mantener la suma en 100 %).

| SA | Instrumento nuevo o convertido | Peso restado de |
|---|---|---|
| SA1 Building Health | Rúbrica de autoevaluación del rol Coach (antes quiz auxiliar sin peso) | Rúbrica de diseño del plan (40 → 30 %) |
| SA2 Bádminton | Rúbrica de autoevaluación del Progress Lab (nueva) | Rúbrica de progreso técnico (55 → 45 %) |
| SA3 Pilota Valenciana | Rúbrica de autoevaluación técnico-táctica (nueva, recoge la pieza `TechSelfCheck`) | Rúbrica técnico-táctica (35 → 25 %) |
| SA4 Primeros Auxilios | Rúbrica de autoevaluación del rol de rescatador y observador (nueva) | Rúbrica de RCP (50 → 40 %) |
| SA4b Balonmano | Rúbrica de autoevaluación y coevaluación de cierre (fusiona la rúbrica 4 y el quiz 7) | — (mantiene el 10 % del instrumento 4) |
| SA5 Ultimate Frisbee | Rúbrica de autoevaluación del Torneo Inclusivo (nueva) | Rúbrica técnico-táctica de torneo (50 → 40 %) |
| SA6 Acrosport | Rúbrica de autoevaluación y coevaluación de cierre (antes quiz sin peso) | Rúbrica de ejecución técnica (40 → 30 %) |

## Cambios en la app

- `LearningSituationAssessmentInstrumentsImportService`: nuevos `kind` `.selfAssessment` y
  `.peerAssessment`, con `isStudentAuthored`. Se activan solo si el título trae
  autoevaluación/coevaluación **y** hay tabla de rúbrica de 4 niveles; si no, sigue el
  comportamiento histórico (`.checklist`). Estrategia de puntuación `.observationScale1To4`.
- `KmpBridge`: la plantilla estructurada genera ítems `rub_<n>` (`SCALE_1_4`, con los cuatro
  descriptores en `helpText`) y `open_<n>` (`TEXT`). `makeInstrumentItems` acepta textos de ayuda
  por clave.
- `NotebookInstrumentsRepositorySqlDelight.deriveStudentRubricScore`: nota = media de los
  `rub_<n>` respondidos, en escala 1-4; los `open_<n>` no intervienen.
- `AssessmentInstrumentSourceKind` (KMP) gana `SELF_ASSESSMENT`/`PEER_ASSESSMENT`, mapeados a
  `NotebookInstrumentTemplateKind.FORM` en `MaterializeLearningSituationAssessmentUseCase`.

## Publicación web

El instrumento tiene plantilla estructurada (no rúbrica guardada), así que `publishWebForm` lo
acepta sin cambios: los ítems 1-4 viajan como `scale1To4` y las preguntas como `text`. La entrega
importada pasa por `saveResponses`, que es quien deriva y guarda la nota.

Limitación de diseño conservada: la rúbrica ponderable valora siempre a quien la rellena. La app
atribuye cada respuesta a quien la escribe, así que una valoración sobre otro alumno/a acabaría en
la fila equivocada; esa coevaluación clásica (SA4, instrumentos 2 y 4) sigue en papel, validada por
muestreo e introducida por el profesorado.

## Verificación

- `./gradlew :data:desktopTest --tests "*NotebookInstrumentsRepositorySqlDelightTest*"`: 6/6 en
  verde, incluido el test nuevo
  `saveResponses derives a self-assessment score from the rubric items and ignores the open questions`
  (4+3+2 → 3,0 en 1-4 → 6,67 sobre 10 en la hoja; la respuesta abierta no altera el cálculo).
- Importador real compilado aparte (`swiftc` sobre
  `LearningSituationAssessmentInstrumentsImportService.swift` + ZIPFoundation) y ejecutado sobre
  los siete `instrumentos_evaluacion*.docx` recompilados con pandoc: los siete detectan su
  instrumento `selfAssessment` con peso, `countsTowardAverage = true`, sus indicadores de rúbrica y
  sus preguntas abiertas; los pesos suman 100 % en las siete y **no queda ningún aviso**.
- `scripts/verify_apple_builds.sh`: macOS nativo e iOS Simulator compilan correctamente.
