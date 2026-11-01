# Ticket M · Voz de Pista sugiere criterios y niveles de rúbricas y listas de cotejo

Maqueta aprobable: `mockup/voz-de-pista-criterios.html` (7 estados, revisada contra HIG).

## Objetivo / contexto

Cuando el docente describe cómo trabaja un alumno («ejecuta golpes técnicos adecuados y se mueve bien por la pista»), hoy Voz de Pista lo guarda como observación o pide una nota suelta. Debe reconocer qué criterios de la rúbrica (o ítems de la lista de cotejo) se mencionan, proponer un nivel para cada uno y dejar que el docente lo confirme en la bandeja. Regla: lo que no se dice no se valora.

## Alcance

- Instrumentos: rúbricas (columna con `rubricId` + `evaluationId`), listas de cotejo y formularios estructurados con ítems `CHECK` o `SCALE_1_4`.
- Detección: Apple Intelligence en el dispositivo (Foundation Models) con lista cerrada de criterios y niveles de la clase; reserva por reglas (palabras clave del criterio y del descriptor) si no está disponible.
- Bandeja: tarjeta de evaluación con frase subrayada por criterio, control segmentado de niveles por criterio, descriptor del nivel, «Sugerido: X» + «Volver a la sugerencia», criterios no mencionados plegados (DisclosureGroup), lista de cotejo con Sí / No / Sin marcar.
- Observación que encaja con criterios: sugerencia en línea «Evaluar con rúbrica», conservando la observación.
- Estados: sin criterio claro (no se preselecciona, chips de criterios), cargando (`ProgressView`), error al leer la plantilla (guardar como observación).
- Barra de la hoja: Cancelar / Aplicar (n) en la toolbar.

## Fuera de alcance

- Crear o editar rúbricas desde Voz de Pista.
- Cambios en KMP, SQLDelight o `KmpBridge.swift`.
- App de escritorio (`desktopApp`).

## Modelo de datos (sin cambios de esquema)

- Rúbrica: `rubricsRepository.getRubricDetail(rubricId)` para leer criterios y niveles; `saveRubricAssessment(studentId, evaluationId, criterionId, levelId)` por criterio confirmado (ya recalcula la nota con solo los criterios valorados).
- Estructurados: `getTemplateForColumn(columnId)` para ítems; `saveResponses(...)` solo con los ítems confirmados (`boolValue` para CHECK, `numberValue` 1-4 para SCALE_1_4).
- Acción en la bandeja: nuevo campo opcional `criterionProposals: [CourtVoiceCriterionProposal]?` (criterionId/itemId, nivel sugerido, nivel elegido, fragmento de evidencia, confianza). Opcional para no romper la bandeja guardada (`CourtVoiceInboxStore`).

## Plan

1. Descriptores: cargar criterios/niveles e ítems de las columnas visibles al abrir la hoja (caché por clase).
2. Servicio: `matchCriteria(text:, instrument:)` en `AppleFoundationCourtVoiceService` con salida guiada (`@Generable`) restringida a ids existentes; reserva por reglas.
3. Bandeja: nueva subvista `CourtVoiceCriteriaEditor` (archivo propio) usada por la tarjeta de evaluación rápida y por la sugerencia en observaciones.
4. Persistencia en `persistSingleEvaluationAction`: rama rúbrica y rama estructurada con respuestas; nunca `saveGrade` directo para estas columnas.
5. Accesibilidad: radiogroup nativo vía `Picker(.segmented)`, `.inline` en tamaños de accesibilidad, valores «Logrado, 3 de 4, sugerido», anuncios de error.
6. Tests en `CourtVoiceCaptureTests`: emparejamiento por reglas, no mencionados sin valor, «no recoge» → No, conversión de observación.

## Criterios de aceptación

- Dictar «Lucía ejecuta golpes técnicos adecuados y se mueve bien por la pista» con la rúbrica de bádminton propone 2 criterios con nivel y deja los otros 2 sin valorar.
- Al aplicar, solo se guardan los criterios confirmados; la nota de la celda coincide con la de la evaluación masiva para esos mismos niveles.
- En una lista de cotejo, lo no dicho queda «Sin marcar», nunca «No».
- Frase vaga: acción no preseleccionada y sin niveles inventados.
- Funciona sin Apple Intelligence (reglas) y sin red.
- VoiceOver lee criterio, nivel y si es sugerido. Objetivos de 44 pt. Dynamic Type XXL sin cortes.

## Validación

- `xcodebuild test -scheme MiGestorPlannerTests -only-testing:MiGestorPlannerTests/CourtVoiceCaptureTests`.
- Build `MiGestorKMPiOS` (simulador iPad) y `MiGestorKMPMac`.
- Prueba manual con datos de prueba (nunca alumnado real): rúbrica, lista de cotejo, observación convertida, Dynamic Type grande y VoiceOver.

## Agentes

- `worker` (Sonnet) para pasos 1, 3, 5 y 6; `architect` (Opus) para el paso 2 (diseño del emparejamiento y su salida guiada); `ui-reviewer` sobre capturas reales; `janitor` antes de fusionar.

## Riesgos

- Falsos positivos del emparejamiento: mitigado con confianza mínima, evidencia visible y no preselección por debajo del umbral.
- Rendimiento con muchas rúbricas: limitar a las columnas visibles de la pestaña activa.
