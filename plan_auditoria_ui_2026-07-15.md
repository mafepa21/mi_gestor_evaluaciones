# Plan de corrección — Auditoría de UI de todas las pantallas (2026-07-15)

Auditoría estática de la capa SwiftUI Apple (`kmp/iosApp/App`, `kmp/iosApp/AppleShared`, `kmp/iosApp/MacApp`, ~78.500 líneas) centrada en: estructura de datos de la UI, paneles desplegables, menús laterales/inspectores y ciclo de vida de estado. Este plan está pensado para que lo ejecute un agente (Sonnet) de forma autónoma.

## Pantallas auditadas

- **Shells**: `IOSRootView` (iPad split view), `AppWorkspaceShell`/`WorkspaceModuleSwitcher` (iPhone), `MacRootView` (macOS), `WorkspaceLayoutState` (registro de acciones de toolbar).
- **Uso diario**: Dashboard, Cuaderno (grid, toolbar, inspector, plano de clase), Asistencia, Cursos, Alumnado.
- **Secundarios**: Planner iOS/Mac, Situaciones de aprendizaje (+importadores), Diario, Hub de evaluación, Rúbricas/Informes, Biblioteca, Sesiones EF, Condición física, Incidencias, Material, Torneos, Ajustes, Backups, Sync.
- Los equivalentes macOS (`MacAttendanceView`, `MacStudentsView`, `MacPhysicalTestsView`, `MacRubricsView`, `MacDashboardView`) están bien alineados con el patrón `.task(id:)`/`appOnChange` y no presentan los bugs de las variantes iOS, salvo lo indicado abajo.

## Reglas de trabajo para el agente

- Trabaja en una rama `fix/auditoria-ui-2026-07` desde `main`.
- **Un commit atómico por bug**, formato `fix(<ámbito>): <descripción>` (p.ej. `fix(cuaderno): ...`). No agrupes bugs distintos en un commit.
- Actualiza `docs/CHANGELOG.md` con una entrada por fix, en español.
- Verificación mínima tras cada cambio Swift: compilar `xcodebuild -project kmp/iosApp/MiGestorKMPiOS.xcodeproj -scheme MiGestorKMPMac build` (o el scheme iOS). Hay fallos preexistentes de CI ajenos; compara contra el estado previo.
- No toques `KmpBridge.swift`, `kmp/shared/`, `kmp/data/`, `EvaluationDesign.swift` ni `desktopApp/` (regla de oro de `AGENTS.md`).
- Mensajes de UI siempre en español. Cambios quirúrgicos: no refactorices más allá de lo que pide cada ítem.

---

## Prioridad ALTA

### UI-1 — Todas las hojas de creación silencian errores y cierran como si hubieran guardado

**Archivo:** `kmp/iosApp/App/WorkspaceCreationSheets.swift`
(`CreateCourseSheet.save()` ~L40, `CreateStudentSheet.save()` ~L121, `CreateEvaluationSheet.save()` ~L183, `CreatePESessionSheet.save()` ~L394, `CreatePhysicalTestSheet.save()` ~L478, hoja de incidencias ~L594). También `kmp/iosApp/App/PlannerWorkspaceViewModel+BulkOperations.swift:111` (`plannerUpsertSession`).

**Problema:** Es el mismo defecto que el B1 del plan 2026-07-13 pero generalizado: todos los `save()` usan `try?` y llaman a `close()` incondicionalmente. Si `createClass`, `createStudentInSelectedClass`, `createEvaluation`, `createPESession`, `createPhysicalTest` o `createIncident` fallan (BD, bridge), el docente ve la hoja cerrarse "con éxito" y el dato no existe. Además, en `CreateCourseSheet` el `guard` de validación hace `return` silencioso dentro del `Task`: si el nivel no es numérico, el botón Guardar no hace nada perceptible.

**Fix:**
1. En cada sheet: `@State private var errorMessage: String?` + `.alert` (copiar el patrón de `SupportMeasureBulkImportSheet`).
2. Sustituir `try?` por `do/catch`; en `catch`, poner `errorMessage` y NO cerrar. Solo `close()` en éxito.
3. En `CreateCourseSheet`, mover la validación numérica a `canSave` (deshabilitar Guardar) en lugar del guard silencioso.
4. En `PlannerWorkspaceViewModel+BulkOperations`, contar fallos del bucle y exponerlos por el mecanismo de mensaje transitorio ya existente en el VM.

**Criterio de aceptación:** ningún `try? await bridge.create...`/`saveIncident` en esos archivos; un fallo de guardado deja la hoja abierta con alert visible.

---

### UI-2 — El campo de búsqueda global del iPad no hace nada fuera de Cuaderno/Asistencia

**Archivos:** `kmp/iosApp/App/IOSRootView.swift` (`IOSGlobalContextRow.activeSearchBinding` ~L832, `IOSWorkspaceContent` ~L948).

**Problema:** `IOSGlobalContextRow` muestra "Buscar módulos, grupos o alumnado..." en todos los módulos. Para módulos distintos de `.notebook`/`.attendance` escribe en el `@State searchText` de `IOSRootView`, que se pasa como `@Binding` a `IOSWorkspaceContent`… donde **nunca se usa** (Cursos, Alumnado, Situaciones, Rúbricas, Informes, etc. tienen su propio `searchText` interno). El docente escribe y no se filtra nada.

**Fix (opción recomendada, quirúrgica):** ocultar el campo de búsqueda global en los módulos donde no está conectado (mostrarlo solo en `.notebook` y `.attendance`), eliminando el binding muerto `searchText` de `IOSWorkspaceContent`. Alternativa (más cara): propagar el binding a cada workspace; NO hacerla en este plan.

**Criterio de aceptación:** en iPad, el campo de búsqueda solo aparece donde realmente filtra; no queda ningún `@Binding var searchText` sin consumir en `IOSWorkspaceContent`.

---

### UI-3 — Búsqueda del Cuaderno (toolbar iPad/Mac): pérdida de pulsaciones y cursor saltando

**Archivos:** `kmp/iosApp/App/IPadWorkspaceShell.swift` (`WorkspaceLayoutState.setNotebookSearchText` ~L221), `kmp/iosApp/App/NotebookModuleToolbarState.swift` (`toolbarStateKey` ~L324, `scheduleToolbarStateSync` ~L302).

**Problema:** El `TextField` de búsqueda del cuaderno (toolbar de `IOSRootView` y `MacRootView`) usa un binding cuyo `set` llama a `setNotebookSearchText`, que **difiere** la asignación con `publishDeferred` (Task + yield). El `get` devuelve el valor viejo durante un ciclo → con escritura rápida se pierden caracteres y el cursor salta al final. Además, cada pulsación dispara `scheduleToolbarStateSync` (debounce 50 ms) que reescribe `notebookSearchText` completo vía `configureNotebookToolbar`, pudiendo pisar lo tecleado. Nótese que `setAttendanceSearchText` (~L436) ya hace la asignación síncrona: el cuaderno debe seguir el mismo patrón.

**Fix:**
1. En `setNotebookSearchText`, `setNotebookSurfaceMode` y `setNotebookGroupFilter`: asignar el `@Published` de forma síncrona y llamar a la acción, igual que las variantes de asistencia. Mantener `publishDeferred` solo en `configure*/clear*/update*` (que se invocan desde dentro de la evaluación del body).
2. En `syncToolbarState`, no machacar `notebookSearchText` si el valor entrante es igual al actual (o excluir el searchText del update masivo).

**Criterio de aceptación:** teclear rápido (10+ caracteres) en la búsqueda del cuaderno en iPad regular y macOS no pierde caracteres ni mueve el cursor; la lista se filtra con cada pulsación.

---

### UI-4 — Acciones de la toolbar del Cuaderno operan sobre datos obsoletos al cambiar de pestaña

**Archivo:** `kmp/iosApp/App/NotebookModuleToolbarState.swift` (`toolbarStateKey` ~L324-329).

**Problema:** Los closures registrados en `configureNotebookToolbar`/`macToolbarActions.configure` capturan el snapshot `data` del momento de la sincronización, y solo se re-registran cuando cambia `toolbarStateKey`. La clave NO incluye `bridge.selectedNotebookTabId` ni `searchText`. Cambiar de pestaña del cuaderno mantiene el mismo número de filas y puede mantener el de columnas → la clave no cambia → "Exportar" (`exportText`), "Marcar todos presentes" y el listado de grupos del filtro siguen usando la pestaña anterior.

**Fix:** añadir `bridge.selectedNotebookTabId ?? "all"` y `searchText` a `toolbarStateKey`.

**Criterio de aceptación:** con dos pestañas con igual nº de filas/columnas, tras cambiar de pestaña el texto de "Exportar" refleja las columnas de la pestaña activa.

---

### UI-5 — Botón "Inspector" muerto en el módulo Alumnado (iPad)

**Archivo:** `kmp/iosApp/App/IOSRootView.swift` (`toggleInspector()` ~L241-250, `supportsInspector` ~L1218-1225).

**Problema:** `supportsInspector` incluye `.students`, así que la toolbar muestra el botón Inspector en Alumnado; pero `toggleInspector()` solo enruta `.notebook/.dashboard/.diary` (default: `break`). El botón no hace nada (solo voltea un `@SceneStorage` que nadie lee — ver UI-11). `StudentProfilesWorkspaceView` no tiene inspector conmutable (su panel de detalle es fijo).

**Fix:** quitar `.students` de `supportsInspector`.

**Criterio de aceptación:** en Alumnado (iPad) no aparece botón Inspector; en Dashboard y Diario sigue funcionando.

---

## Prioridad MEDIA

### UI-6 — Asistencia iOS: carrera al cambiar de fecha rápidamente

**Archivo:** `kmp/iosApp/App/AttendanceWorkspaceView.swift` (~L198-203).

**Problema:** `appOnChange(of: selectedDate)` lanza `Task { reloadClassOverviews(); reloadAttendance() }` sin cancelar el anterior (el cambio de clase sí usa `classSelectionTask` con cancel). Navegando rápido entre días, una respuesta lenta de un día anterior puede pisar `recordsByStudentId`/`history` del día visible.

**Fix:** añadir `@State var dateReloadTask: Task<Void, Never>?`, cancelar antes de relanzar y comprobar `Task.isCancelled` antes de asignar resultados (patrón ya presente en `syncClassSelection`). `MacAttendanceView` ya lo resuelve con `.task(id: selectedDate)`: replicar ese enfoque también vale.

**Criterio de aceptación:** cambiar de fecha N veces seguidas deja siempre los registros de la última fecha.

### UI-7 — Asistencia iOS: cerrar el inspector con el gesto del sistema bloquea la reapertura

**Archivo:** `kmp/iosApp/App/AttendanceWorkspaceView.swift` (~L176-219).

**Problema:** `.inspector(isPresented: $isAttendanceInspectorPresented)` se sincroniza desde la computada `isInspectorPresented` (= hay selección y no hay focus mode) solo en `appOnChange` de selección/focus. Si el usuario cierra el inspector con el affordance del sistema, `selectedStudentId` queda puesto; volver a tocar al MISMO alumno no dispara `appOnChange(of: selectedStudentId)` y la ficha no reabre.

**Fix:** añadir `.appOnChange(of: isAttendanceInspectorPresented)` que, al pasar a `false` sin `historySelection`/focus de por medio, limpie `selectedStudentId` y `historySelection` (equivalente a "Cerrar ficha").

**Criterio de aceptación:** cerrar el inspector arrastrando y volver a tocar el mismo alumno reabre su ficha.

### UI-8 — Hojas de edición con `.sheet(isPresented:) + if let` y `State(initialValue:)`: datos obsoletos / hoja en blanco

**Archivos:**
- `kmp/iosApp/App/CoursesWorkspaceView.swift` (~L25 + `CourseClassEditorSheet` ~L1030).
- `kmp/iosApp/App/StudentProfilesWorkspaceView.swift` (~L96-128: `SupportMeasureFormSheet` de alta y edición, `StudentEditorSheet`).
- `kmp/iosApp/App/LibraryAndPEWorkspaceViews.swift` (~L838: `EditPESessionOperationalSheet`).
- `kmp/iosApp/App/PlannerWorkspaceIOS.swift` (~L70: `PlannerSessionDetailSheet`).

**Problema:** Patrón frágil documentado: la presentación depende de un `Bool` y el contenido de un `if let` sobre otro estado. Si el item se anula durante la animación se presenta una hoja en blanco; y como los editores copian el modelo a `@State` en `init`, una re-presentación con el contenido aún vivo muestra los datos del elemento anterior (editar grupo A, cerrar, editar grupo B).

**Fix:** migrar a `.sheet(item:)` con payload `Identifiable`. Para "crear" (item nil) usar un enum wrapper (`enum ClassEditorTarget: Identifiable { case new; case edit(SchoolClass) }`). No cambiar la lógica interna de los editores.

**Criterio de aceptación:** editar dos elementos consecutivos muestra siempre los datos del segundo; no puede aparecer una hoja vacía.

### UI-9 — Sesiones EF: timer inline re-renderiza el panel completo cada segundo

**Archivo:** `kmp/iosApp/App/LibraryAndPEWorkspaceViews.swift` (~L847).

**Problema:** `.onReceive(Timer.publish(every: 1...).autoconnect())` está inline en el `body`: cada evaluación crea un publisher nuevo y `now = tick` fuerza re-evaluación por segundo de las dos variantes de `ViewThatFits` (lista + detalle), con re-suscripción continua. Coste de CPU/batería permanente aunque no haya sesión activa.

**Fix:** patrón de `PlannerDayView:34`: `private let nowTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()` como propiedad, y limitar la actualización al stat "Activa" (p. ej. extrayendo el stat a una subvista que sea la única que observe `now`), o usar `TimelineView(.periodic(...))` solo alrededor del texto del cronómetro.

**Criterio de aceptación:** el panel de sesiones EF no re-evalúa su `body` completo cada segundo (verificable con `Self._printChanges()` temporal o por inspección de la estructura).

### UI-10 — Importador de instrumentos: crash potencial por índices en Binding

**Archivo:** `kmp/iosApp/App/LearningSituationsWorkspaceView.swift` (`importedInstrumentRows` ~L1402).

**Problema:** `ForEach(Array((instrumentImportDraft?.instruments ?? []).indices), id: \.self)` con `set: { instrumentImportDraft?.instruments[index].isSelected = $0 }`. Si el draft se sustituye por una reimportación con menos filas mientras la vista sigue montada, el subscript revienta (out of bounds). El editor hermano (~L1888) deriva el índice de forma segura vía `firstIndex(where:)`; este no.

**Fix:** iterar sobre los elementos con id estable (`ForEach(instrumentImportDraft?.instruments ?? [], id: \.id)`) y mutar buscando el índice por id dentro del `set`, con `guard` de rango.

**Criterio de aceptación:** reimportar un archivo con menos instrumentos con la lista abierta no puede provocar index-out-of-range; los toggles siguen funcionando.

### UI-11 — Estado persistido del shell iPad: restauración sin validar y `SceneStorage` muerto

**Archivo:** `kmp/iosApp/App/IOSRootView.swift` (~L39-43, ~L202-212, ~L241).

**Problema:** (a) `restorePersistedDataState()` restaura `selectedStudentId` persistido sin comprobar que el alumno exista o pertenezca a la clase restaurada — la validación que sí se hace en el `appOnChange` de clase no cubre el arranque, porque el alumno se asigna DESPUÉS de lanzarse esa tarea. (b) `@SceneStorage("ios.root.inspectorVisible")` se escribe en `toggleInspector()` pero jamás se lee para restaurar nada: estado muerto que además desincroniza su significado con los inspectores por módulo.

**Fix:** (a) tras `restorePersistedDataState`, validar el alumno contra `bridge.students(forClassId:)` y anularlo si no pertenece (reutilizar la lógica del `appOnChange`). (b) eliminar `inspectorVisible` y su toggle (los inspectores por módulo ya persisten su propio estado), o conectarlo de verdad; eliminar es lo coherente con la simplicidad del repo.

**Criterio de aceptación:** arrancar con un alumno persistido que ya no está en la clase no deja selección fantasma; no queda `SceneStorage` sin lector.

### UI-12 — Sidebar iPad: módulo EF activo queda huérfano al desactivar el perfil de EF

**Archivos:** `kmp/iosApp/App/IOSRootView.swift` (`normalizedModule` ~L198, restauración de `persistedModule` ~L194), `kmp/iosApp/App/IOSFeatureRegistry.swift`.

**Problema:** Si el docente está en `peTests` (u otro módulo `requiresPhysicalEducationProfile`) y desactiva el perfil EF en Ajustes, el módulo desaparece del menú lateral pero sigue activo y persistido: al reabrir, la app restaura una pantalla sin entrada en el sidebar (sin selección visible ni forma de volver a ella desde el menú).

**Fix:** en `normalizedModule(_:)`, si `module.requiresPhysicalEducationProfile` y el perfil EF no está en `TeacherSubjectProfile.decodeSet(...)`, devolver `.dashboard`. Aplicarlo también cuando cambie el ajuste de perfiles (appOnChange del `@AppStorage` correspondiente en `IOSRootView`).

**Criterio de aceptación:** desactivar el perfil EF con un módulo EF activo redirige a Dashboard; reabrir la app nunca restaura un módulo oculto.

### UI-13 — macOS: inspector genérico abierto por defecto mostrando un placeholder

**Archivo:** `kmp/iosApp/MacApp/MacRootView.swift` (`detailPane` ~L128-154, `featureInspector` ~L482-536).

**Problema:** El shell aplica `.inspector(isPresented: $isInspectorVisible)` (por defecto `true`) a todos los módulos salvo asistencia/planner/diario, pero `featureInspector` solo tiene contenido real para notebook, students, backups, physicalTests y planner; Dashboard, Cursos, Rúbricas, Informes, Situaciones, Sync y Ajustes muestran `MacModuleInspectorPlaceholder` reservando 320-440 pt de ancho permanentemente. Falla el "Test del Aire": una columna entera sin tarea.

**Fix:** introducir en `MacFeatureDescriptor.Feature` (o en el switch de `detailPane`) el conjunto de features con inspector real y aplicar el modifier `.inspector` solo a esas; para el resto, renderizar el contenido sin inspector (y ocultar el botón de toolbar de inspector si lo hubiera para esas features).

**Criterio de aceptación:** en macOS, Dashboard/Cursos/Rúbricas/Informes/Situaciones/Sync/Ajustes usan todo el ancho; Cuaderno/Alumnado/Backups/Cond. física conservan su inspector.

---

## Prioridad BAJA

### UI-14 — Código muerto: binding de explicación de media siempre nil

**Archivos:** `kmp/iosApp/App/NotebookModuleView.swift` (~L304-309), `kmp/iosApp/App/NotebookModuleOrganization.swift` (~L459).

`mappedExplanationItemBinding` devuelve `Binding(get: { nil }, set: { _ in })` y se engancha a `.notebookAverageExplanation(item:)` en el botón de media; el flujo real usa `averageExplanationRow` (sheet/popover en `NotebookModuleView` ~L1184-1230). Eliminar el binding y el modifier huérfano (verificar antes que ningún otro sitio use `notebookAverageExplanation`).

### UI-15 — `appOnChange(of: selectedClassId)` duplicado en Condición física

**Archivo:** `kmp/iosApp/App/PhysicalTestsWorkspaceView.swift` (~L366-367). Consolidar los dos handlers en uno (`reload()` + `syncSelectedClassDefaults()`).

### UI-16 — Planner iOS: "Abrir diario" cierra el sheet y navega en el mismo ciclo

**Archivo:** `kmp/iosApp/App/PlannerWorkspaceIOS.swift` (~L70-100). `MacRootView` documenta (comentario en `presentPendingPlannerDiarySession`, ~L245-260) que encadenar "cerrar sheet + navegar" en el mismo ciclo es poco fiable, y lo resuelve aparcando la sesión y navegando en `onDismiss`. La variante iOS hace `selectedDetailSession = nil` + `onOpenDiary?(...)` seguidos. Replicar el patrón `onDismiss` de Mac (estado `pendingDiaryContext` + navegación en el `onDismiss` del sheet).

### UI-17 — Deuda de arquitectura (documentar, no refactorizar ahora)

Añadir a `docs/` (o al ADR que corresponda) dos riesgos detectados:
1. **Tres routers de módulos paralelos** (`IOSWorkspaceContent.academicContent/evaluationAndPEContent`, `AppWorkspaceShell.activeWorkspace`, `MacRootView.featureContent`) que deben mantenerse sincronizados a mano al añadir un módulo.
2. **`WorkspaceLayoutState` como registro global de closures** (~35 acciones): los closures capturan snapshots (`data`) y dependen de claves de invalidación manuales (`toolbarStateKey`) — origen de UI-3/UI-4. Cualquier módulo nuevo que lo use debe incluir TODAS sus dependencias en su clave.

---

## Orden de ejecución sugerido

| Fase | Ítems | Motivo |
|---|---|---|
| 1 | UI-1 | Pérdida silenciosa de datos (peor clase de bug del repo) |
| 2 | UI-3, UI-4 | Cuaderno = pantalla de uso diario nº 1 |
| 3 | UI-2, UI-5 | Controles visibles que no hacen nada (confianza del usuario) |
| 4 | UI-6, UI-7, UI-8, UI-10 | Carreras y crashes potenciales |
| 5 | UI-9, UI-11, UI-12, UI-13 | Rendimiento y coherencia de shells |
| 6 | UI-14, UI-15, UI-16, UI-17 | Limpieza y documentación |

## Verificación global al cerrar

1. Compilan los schemes Mac e iOS sin errores nuevos.
2. Smoke test manual mínimo por plataforma: crear grupo con fallo simulado no cierra la hoja; búsqueda del cuaderno filtra sin perder caracteres; cambiar pestaña + exportar refleja la pestaña activa; asistencia con cambios rápidos de fecha muestra el día correcto.
3. `registrar-avance-app` como capa final: changelog, evidencias y nota de PR.
