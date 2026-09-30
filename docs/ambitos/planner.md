# Ámbito: Planner (visor de sesión)

## Estado actual

- Visor de sesión de repaso rápido (`codex/visor-sesiones-repaso-rapido`): un solo `ScrollView` con columna de ~820 pt, sin selector de actividad ni pestañas. Guion por bloques, estados cargando/vacío/error y "Evidencia y trazabilidad" plegada.

## Terreno de juego

- `kmp/iosApp/App/PlannerSessionDetailSheet.swift` (hoja e inspector), `PlannerSessionReviewComponents.swift` (vistas del guion), `PlannerSessionDetailComponents.swift` (barra, chunks CLIL, adjuntos, visual ampliado), `PlannerSessionDetailProjection.swift` (proyección y `PlannerSessionReviewBuilder`).
- Tests: `kmp/iosApp/PlannerTests/PlannerSessionDetailProjectionTests.swift` y `PlannerSessionDetailLayoutTests.swift`.

## Trampas

- El target de tests `MiGestorPlannerTests` es macOS y usa el scheme `MiGestorPlannerTests`; `Frameworks/` (MiGestorKit) no está en git: un worktree nuevo necesita enlazarlo desde el checkout principal antes de compilar.
- Archivo Swift nuevo => `xcodegen --spec kmp/iosApp/project.yml` y commitear el `project.pbxproj`.
- `PlannerSessionReviewStep.startOffsetMinutes` es acumulado sin contar el descanso; las recogidas (`isCollection`) no tienen hora ni avanzan el acumulado. Sin minutos conocidos, no hay hora.
- La línea "Recogida: ..." del texto docente se extrae como paso propio; la consigna CLIL sale del texto (`removingCLILConsigna`) y se muestra pegada al paso.
- Los datos secundarios de cada actividad (alumnado, evidencia, temporización, plan si va lento/rápido, continuidad, material) solo se ven con "Ver más" (`PlannerSessionReviewStep.extras`); no quitarlos.
- El visor pide `renderedActivityVisuals[activityKey]`: la clave del paso debe ser la misma que la de la actividad normalizada.
- `WorkspaceFlowLayout` usa `ViewThatFits(in: .vertical)`: no envuelve en horizontal. Para "dos columnas o una" usar `ViewThatFits(in: .horizontal)` con `idealWidth` fijo en la primera opción.
- "Ver más" detecta el recorte midiendo el texto completo oculto frente al limitado a 4 líneas; si se cambia la fuente de uno, cambiar la del otro.
- `PlannerSessionMaterialChipsView`, `PlannerSessionZoneCardsView` y `PlannerFormattedTextView` quedaron sin usos en el visor (candidatos a limpiar en otro ticket); `PlannerSessionCLILBanner` se conserva porque lo usa `PlannerFormattedTextView`.
- `xcodebuild` puede reescribir `*.xcscheme`: restaurar antes de commitear.
