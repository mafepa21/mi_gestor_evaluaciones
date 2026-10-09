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
- `AppleBridgeBootstrap.current()` abre un driver completo y lo deja abierto: para leer la ruta usar `AppleBridgeBootstrap.databasePath`, nunca `current().databasePath`.
- `PlannerWorkspaceViewModel.bind` marca `isLoaded` tras horario + semana; previsión, exámenes 1º Bach, planes de SA y mes llegan después. Una vista que dependa de esos datos no debe asumir que existen cuando `isLoaded` es `true`.
- La sincronización de exámenes de 1º Bach se guarda en `UserDefaults` (`planner.exams1Bach.lastSyncKey`, versión + ids de grupo); para forzarla, borrar esa clave.
- Los PRAGMA que devuelven fila (`mmap_size`) fallan con `driver.execute`: usar `executeQuery` y llamar a `cursor.next()`.
- Un repositorio KMP sin `withContext(Dispatchers.Default)` corre la consulta en el hilo principal cuando lo llama Swift: la UI se congela. Comprobarlo antes de culpar a SwiftUI.
- SyncLAN en Mac: la app habla con su helper con `MacCommandCenterCoordinator.helperLocalToken` (stdin, solo loopback). No volver a una contraseña fija.
- Fechas de eventos: se guardan a las 00:00 locales. Nunca compararlas con `AppDateTimeSupport.isoDateString` (formatea en UTC); usar el calendario local.
- `PlannerWorkspaceSection.rawValue` se guarda en preferencias: para cambiar el nombre visible usar `toolbarTitle`, no el `rawValue`.
- La app no tiene localización en español: `Locale.current` da meses en inglés. En formateadores de fecha visibles usar `Locale(identifier: "es_ES")`.
- Los números de franja propios (P10, P11…) se asignan después de los del centro: en pantalla mostrar la hora, no el número.
- Los hitos de la semana llegan duplicados (uno por grupo): contar por fecha + título.
- La cabecera grande de SA (`expandedProgressHeader`) solo se pinta en Resumen.
- Celdas de la Semana (`PlannerWeekMiniatureGrid`): la materia más repetida del horario (`dominantSubject`) no se pinta; solo se etiqueta la de otra materia (p. ej. Tutoría). En franjas sin sesión, `entry.preview` es la materia y `entry.title` repite la materia si no hay bloque: entonces se muestra "Sin planificar".
- `PlannerWorkspaceIOS` y `PlannerToolbar` usan `@Environment(\.kmpBridgeReference)`, no `@EnvironmentObject`: no volver a observar el bridge entero (redibuja el Planner con cada cambio del Cuaderno o de SyncLAN).
- `PlannerWorkspaceViewModel` no reenvía `weekBoard.weekRenderModel`. Una vista nueva que pinte la rejilla o la cobertura de la semana debe observar `vm.weekBoard` (`@ObservedObject var weekBoard`), no leerlo solo a través de `vm`.
- `learningSituationSessionPlansAll()` busca la versión por id en `listAllSessionSequenceVersions()` y exige el mismo `learningSituationId`. La regla "plan ya canónico" vive en `KmpBridge.isCanonicalSessionPlanJSON` (sin estado, testeada); cambiarla solo ahí.
- Nunca llamar a funciones `suspend` de KMP dentro de `async let`, `Task.detached` o `TaskGroup`: Kotlin exige el hilo principal y la app se cierra ("Calling Kotlin suspend functions from Swift/Objective-C is currently supported only on main thread"). Encadenar `try await` en el `@MainActor`; el repositorio ya salta a `Dispatchers.Default`.
