# Ámbito: Planner (visor de sesión)

## Estado actual

- Visor de sesión de repaso rápido (`codex/visor-sesiones-repaso-rapido`): un solo `ScrollView` con columna de ~820 pt, sin selector de actividad ni pestañas. Guion por bloques, estados cargando/vacío/error y "Evidencia y trazabilidad" plegada.

## Terreno de juego

- `kmp/iosApp/App/PlannerSessionDetailSheet.swift` (hoja e inspector), `PlannerSessionReviewComponents.swift` (vistas del guion), `PlannerSessionDetailComponents.swift` (barra, chunks CLIL, adjuntos, visual ampliado), `PlannerSessionDetailProjection.swift` (proyección y `PlannerSessionReviewBuilder`).
- Tests: `kmp/iosApp/PlannerTests/PlannerSessionDetailProjectionTests.swift` y `PlannerSessionDetailLayoutTests.swift`.

## Trampas

- Documentos de sesiones en párrafos (Tavernes) van por `parsePlanLegacy`: el guion sale de `legacyPhaseActivities` (fases «N. … · M minutos»). Esas actividades usan el tipo por defecto, no «narrative»: con «narrative», `PlannerSessionPlanPayloadNormalizer` rehace las secciones y pierde la de chunks CLIL.
- El texto del paso pasa por `PlannerSessionReviewBuilder.reviewDetail` (quita «U01 · », el título «…»: repetido y parte listas en línea). «Alumnado» en extras compara con el texto sin limpiar (`rawDetail`).
- «Ahora» usa `PlannerSessionLiveProgress.state`: minutos de reloj desde `startTime`, sumando 15 min de descanso al llegar al bloque `precededByBreak`. La hora de la franja (55 min) puede no coincidir con los minutos del plan (80): se sigue el plan.
- La barra de tiempos lleva al paso con `proxy.scrollTo(activityKey)`: cada `PlannerReviewStepRow` lleva `.id(step.id)`; si cambia el id del paso, cambiar ambos.
- Repaso ancho (hoja ≥ 900 pt, solo `.sheet` y con plan cargado): `wideReviewContent` en vez de `reviewScrollContent`. Umbrales en `PlannerSessionDetailLayoutPolicy` (`wideMinimumWidth`, `railWidth`, `guideColumnCount`). Lo que se añada a `loadedBody` hay que añadirlo también al repaso ancho.
- `PlannerDocxWebView` solo recarga si cambia el HTML (coordinador): no volver a `loadHTMLString` en cada `update`.
- Avisos y montaje se deduplican sin el prefijo de unidad (`withoutUnitPrefix`): «U10 · X» y «X» cuentan como el mismo.
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
- Ninguna vista usa ya `@EnvironmentObject var bridge`. Una vista nueva que pinte datos del bridge usa `@StateObject private var bridgeWatch = KmpBridgeWatch()` y `var bridge: KmpBridge { bridgeWatch.bridge(bridgeReference) { [.init($0.classes)] } }` con las propiedades que lee (estados Kotlin grandes, por identidad: `.init(ObjectIdentifier($0.notebookState as AnyObject))`). Si pasa el bridge a una hija con `let bridge`, la lista debe incluir lo que lee la hija. Las raíces y hojas ponen el bridge con `.kmpBridgeEnvironment(bridge)`, no con `.environmentObject(bridge)`: la app de Mac no pasaba la referencia.
- `PlannerWorkspaceViewModel` no reenvía `weekBoard.weekRenderModel`. Una vista nueva que pinte la rejilla o la cobertura de la semana debe observar `vm.weekBoard` (`@ObservedObject var weekBoard`), no leerlo solo a través de `vm`.
- `learningSituationSessionPlansAll()` busca la versión por id en `listAllSessionSequenceVersions()` y exige el mismo `learningSituationId`. La regla "plan ya canónico" vive en `KmpBridge.isCanonicalSessionPlanJSON` (sin estado, testeada); cambiarla solo ahí.
- Nunca llamar a funciones `suspend` de KMP dentro de `async let`, `Task.detached` o `TaskGroup`: Kotlin exige el hilo principal y la app se cierra ("Calling Kotlin suspend functions from Swift/Objective-C is currently supported only on main thread"). Encadenar `try await` en el `@MainActor`; el repositorio ya salta a `Dispatchers.Default`.
- El Mes no se carga en `bind`: lo carga `PlannerMonthCalendarView` con `.task(id: monthReloadKey)`, y `reloadSessionsOnly` solo lo recarga si `activeSection == .month`. Una vista nueva que lea `monthSessions` fuera del Mes debe pedirlo ella.
- `vm.forecastRows` no lo pinta nadie en el Planner y `reloadScheduleConfiguration` ya no lo carga por defecto (`includeForecast: false`).
- Al reaparecer, el Planner usa `refreshOnReappear()` (máximo una vez cada 30 s). Tras cambiar el horario hay que llamar a `reloadAll()`, como hace el cierre del asistente.
- El `PlannerWorkspaceViewModel` lo crea `WorkspaceBridgeStores.planner`, no la vista: `PlannerWorkspaceIOS(viewModel:)` y `MacPlannerView(vm:)` lo reciben. No volver a `@StateObject` en la vista (se perdería la semana al salir). `bind` solo carga la primera vez; al volver manda `refreshOnReappear()`.
- Eventos del calendario y planes de SA: leerlos con `vm.plannerCalendarEvents()` y `vm.plannerSessionPlansAll()` (copia de 30 s). Tras escribir en el calendario, poner `vm.cachedCalendarEvents = nil` antes de recargar.
- Importar horario: `ScheduleImportCatalogResolver.resolveGroups` empareja automáticamente solo si hay un único grupo con el nombre exacto y ninguno con sufijo («4º ESO A - Tavernes»). Si hay varios, el código queda en `ambiguousCandidatesByCode` y la hoja pide elegir (`scheduleImportGroupChoices`); no volver a coger «el primero».
- Nombres de grupo en pantalla: usar `bridge.classDisplayNames()` (o `vm.groupName(_:)` en el horario) para distinguir grupos repetidos. Es solo visual: lo que se guarda (p. ej. `groupName` de sesiones) sigue usando `schoolClass.name`.
- En el Planner, el nombre visible es `vm.groupLabel(for:)` (`groupLabelById`, se rellena en `reloadPlannerGroups`). Una subvista privada sin `vm` debe recibir la etiqueta como parámetro (p. ej. `PlannerMonthSessionPill.groupLabel`). No usar la etiqueta para agrupar ni guardar: el informe PDF y el diario siguen con `groupName`.
- ⌘/⌥ al soltar: `PlannerDragModifiers.isCopyModifierPressed`. En iPad depende de `startMonitoring()` (lo llama el `init` del coordinador); sin esa escucha, `GCKeyboard.coalesced` es nil y la copia se convierte en movimiento.
- Grupos repetidos con franjas en días cruzados: tarjeta del horario (`sameNameGroupDaysCallout`, lógica en `SameNameGroupScheduleDays`). Solo mueve franjas; las sesiones ya planificadas se quedan en su grupo.
- `copySessions`/`shiftSelectedSessions` con `CANCEL` aplican todo si no hay choques; con choques no tocan nada y devuelven `failed`. Antes devolvían siempre «0 copiadas».
- El repositorio copia la sesión tal cual (estado, `startTime`/`endTime`, `teacherScheduleSlotId`). `copySession` en Swift la reescribe con la hora y la franja del grupo de destino; si no, `rebuildVisiblePlannerStructure` la pinta con la hora del original.
- «Grupo N» en la Semana = franja cuyo grupo no está en `bridge.classes` (grupo borrado). Se arregla en el horario («Pasar a…»); al copiar arrastrando ahí, se usa el grupo de origen.
- Copiar a otra semana: `plannerCopySessions(dayOffset:)` sin `targetDayOfWeek`. Las copias fuera de la semana visible no están en `vm.sessions`: leerlas con `plannerGetSession`.
- «Programar sesiones» numera las horas con `LearningSituationScheduleProjection.visibleSlots` (centro + horas propias P10, P11…, igual que la Semana). No volver a `plannerTimeSlots()` solo: las horas propias caían en el periodo 1 y las dos horas de una doble se pisaban (también al guardar, que empareja por periodo).
- Secuencia lineal: una sesión «Doble» (`sessionType` con doble/double, sin «simple», o `blockRole == .long`) ocupa la hora siguiente si va seguida (≤20′). Se decide por el tipo, no por minutos: en Tavernes una doble da 60′ útiles.
- El importador marca «Doble» si el encabezado no dice el tipo y una línea empieza por «Duración…» y dice doble (`isDoubleDurationLine`), en el lector de párrafos (`parsePlanLegacy`) y en el de tablas.
- Visor «Documento / Guion» (`PlannerSessionViewMode`, `@AppStorage("planner.sessionDetail.viewMode")`): el modo Documento solo aparece si `isLoadingRenderedDocument || renderedDocument != nil`; si el render falla, se cae al guion. No cambiar los `rawValue`.
- Recorte del Word (`PlannerSessionDocxRenderer.selectSessionBlocks`): un párrafo con texto vacío nunca es cabecera (antes `wanted.hasPrefix("")` lo daba por bueno y salía el documento entero). «Sesión S01» = sesión 1.
