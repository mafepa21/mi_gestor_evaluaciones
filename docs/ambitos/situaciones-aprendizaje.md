# Ámbito: situaciones-aprendizaje

Rutas relativas a `kmp/iosApp/`. Snapshot del 2026-10-03 (solo lectura, sin compilar).

## 1. Estado Actual
- **Objetivo del ámbito:** crear, importar (.docx), programar y evaluar Situaciones de Aprendizaje (SdA) en iPhone, iPad y Mac.
- **Pantalla:** maestro-detalle. `masterColumn` (336-384 pt, `App/LearningSituationsWorkspaceView.swift:797`) + `detailColumn` (:931). Secciones del detalle: `documentSection` (:1079), `linkedSection` (:1127).
- **Funciones:** importar uno o varios .docx (`.fileImporter` :729), vista previa de importación, programar sesiones, evaluación (instrumentos, pruebas físicas, rúbricas), duplicar, cambiar estado, borrar (uno o lote), selección múltiple, abrir módulos vinculados (`onOpenModule` :1137).
- **Estados:** `LearningSituationStatus` borrador/activo/archivado (:1455-1466).
- **Deuda UI (vista principal):** 1 `fileImporter`, 5 `.sheet(item:)` (:736-772), 3 `.alert`, 0 popovers. Todo en un archivo de 3144 líneas.
- **Deuda UI (hoja de evaluación, :1748-2372):** 4 hojas anidadas (:1952, :1961, :1970, :1977). `AssessmentImportPreview` (:2372) y `RubricImportPreview` (:3066) pesan ~700 líneas cada una.
- **Filtros:** un solo `Menu` (`situationFiltersMenu` :909) con 3 `Picker` (Grupo, Materia, Trimestre).
- **ScheduleSheet** (`App/LearningSituationScheduleSheet.swift`, 1125 líneas): muchos `@State`, varios `Picker`/`DatePicker`, `fileImporter` propio.
- **Rediseño hecho (2026-10, rama `codex/ui-situaciones-aprendizaje`):** la vista principal queda en ~600 líneas y se reparte en `LearningSituationsListColumn`, `LearningSituationDetailView`, `LearningSituationsComponents`, `LearningSituationImportReviewSheet`, `LearningSituationDuplicateSheet`, `LearningSituationEvaluationSheet` y `LearningSituationAssessmentReviewView` (todos en `App/`). Los números de línea de arriba son anteriores al rediseño: buscar por nombre de símbolo.
- **Pendiente:** QA visual (iPhone, iPad, Mac estrecho, letra XXL); errores de guardar/borrar/importar aún en alerta; botón «Abrir Planner» en el aviso «sin periodos»; pesos ≠ 100 % avisan pero no bloquean; filas repetidas y fechas en inglés en «Lo que se creó» (datos, no diseño).

## 2. Terreno de Juego (Ficheros y Límites)
- **Propios:** `App/LearningSituationsWorkspaceView.swift` (vista :650-1493, hojas privadas, `LearningSituationScheduleProjection` :96-600), `App/LearningSituationScheduleSheet.swift`.
- **Instanciada en:** `App/WorkspaceModuleSwitcher.swift:72`, `App/IOSRootView.swift:1098`, `MacApp/MacRootView.swift:598` (solo pasan `selectedClassId` y `onOpenModule`).
- **Solo lectura:** `App/Bridge/KmpBridge+LearningSituations.swift`, `AppleShared/LearningSituationDocumentImportService.swift`.
- **Protegidos:** `KmpBridge.swift`, `EvaluationDesign.swift`, `kmp/shared/domain/`, SQLDelight, `kmp/desktopApp/`.

## 3. Modelo de Datos y Dominio
- **KMP:** `LearningSituation`, `LearningSituationStatus`, `...Version`, `...ClassLink`, `...LinkedResource`, `...SessionPlan`, `...SessionSequenceVersion`, `PlannerEvaluationPeriod`.
- **Swift (AppleShared):** `LearningSituationImportDraft` y sus derivados (tabla, criterio, evaluación, sesión), `...DocumentImportBatch/Failure`, `LearningSituationImportError`.
- **Proyección de horario:** `LearningSituationScheduledSlot`, `...ScheduledDestination`, `...SequenceKind` (canonicalWeekly, legacyWeekly, routeAware, linear).
- **Flujo:** .docx -> borrador -> vista previa -> `confirmImport` -> situación -> vínculo a grupos -> programar sesiones -> materializar evaluación en Cuaderno.

## 4. Trampas Encontradas (Gotchas y Lecciones Aprendidas)
- ⚠ **Planner:** `ScheduleSheet` usa `PlannerEvaluationPeriod` y `programLearningSituationSessions` crea eventos del Planner. No cambiar la lógica de proyección (`canonicalBlockCount` = pares) al rediseñar.
- ⚠ **Cuaderno:** la hoja de evaluación materializa columnas y pestañas. No romper categorías, rúbricas ni columnas ocultas.
- ⚠ **Una vista, tres sistemas:** la usan iOS, iPadOS y macOS. Antes de añadir `#if os`, comprobar los tres.
- ⚠ **Hojas `private struct`:** al extraerlas a otro archivo hay que quitar `private`. Un archivo Swift nuevo exige `xcodegen --spec kmp/iosApp/project.yml` y commitear `project.pbxproj`.
- ⚠ **Ids estables:** las hojas usan `.sheet(item:)` con structs `Identifiable`. Mantener ids estables.
- ⚠ **`loadedDetailSituationId`** evita recargar el detalle. Respetarlo al tocar la selección.
- ⚠ **Filtro por grupo** depende de `classIdsBySituation`, que se carga aparte de `classLinks`.
- ⚠ **Navegación anidada:** la vista ya vive dentro del `NavigationSplitView` del shell y el shell trae su buscador. No añadir otro `NavigationSplitView` ni `.searchable` dentro. En ancho estrecho se usa pila propia con «‹ Situaciones».
- ⚠ **Estado de despliegue compartido:** `expandedCurriculumSections` guarda también el bloque «creado» («Lo que se creó»). Empieza en `["criterios"]`; todo lo demás va plegado.
- ⚠ **«Inicio común» en Programar** ya no pisa las fechas por grupo: hace falta pulsar «Aplicar a todos».
- ⚠ **`PhysicalTestsImportPreviewSheet`** tiene un parámetro opcional para abrirse como pantalla con «Atrás» dentro de Evaluar. Se sigue usando como hoja desde otros sitios.
- ⚠ **Archivadas** ocultas por defecto en la lista; «Desarchivar» devuelve la situación a Activa.
- ⚠ **Compilar:** `Frameworks/` (MiGestorKit) no está en git. Enlazarlo desde el checkout principal antes de `xcodebuild`.
- ⚠ **Motor de torneos** (`kmp/iosApp/AppleShared/Tournament/`, portado de TourneyFlow): valor puro `TournamentPlan` sin SwiftData. Calendario y resultados se identifican por **nombre de equipo**, así que los nombres deben ser únicos (`duplicatedTeamNames`).
- ⚠ **Nombres:** `TournamentStatus` y `TournamentTeam` ya existen en la app (`IPadWorkspaceShell.swift`, `TournamentModule.swift`, módulo antiguo). El motor usa `TournamentPlanStatus` y `TournamentPlanTeam`. Los demás tipos (`Standing`, `MatchResult`, `ScheduledRound`…) no chocan hoy; comprobar antes de añadir tipos con esos nombres.
- ⚠ **Tests del motor** viven en `PlannerTests/` (target macOS `MiGestorPlannerTests`, que arranca la app entera). Si el framework KMP está desfasado respecto a Swift, ese target no compila; hay que reconstruir `MiGestorKit` antes.
- ⚠ **pbxproj:** tras añadir un `.swift` nuevo hay que regenerar con `xcodegen --spec kmp/iosApp/project.yml` y commitear `project.pbxproj`. El sandbox de Claude necesita `dangerouslyDisableSandbox` para xcodegen/xcodebuild.
- ⚠ **Compilar sin tocar el framework compartido:** el preBuildScript `build_apple_framework.sh` escribe en `Frameworks/` (symlink al checkout principal). Para comprobar sin reconstruir, generar un spec temporal sin `preBuildScripts`/`postBuildScripts`, no commitearlo.
- ⚠ **Torneos persistidos (migración 46):** tabla `learning_situation_tournaments` con `id` TEXT (UUID), no autoincremental. Los JSON (`config`, `team_snapshot`, `schedule`, `results`, `knockout_results`) son opacos para KMP; los codifica el motor Swift.
- ⚠ **Versión de esquema:** `AppDatabase.Schema.version` = nº de `.sqm` + 1 (ahora 47). `N.sqm` migra de N a N+1. Al añadir una tabla `learning_situation%` hay que actualizar el test `schema migration from 22...` de `LearningSituationsRepositorySqlDelightTest`.
- ⚠ **SyncLAN con doble implementación:** la instantánea y el tombstone por diferencia de ids salen de `SqlDelightSyncAdapter.kt`; la aplicación entrante y el borrado en Apple están además en `KmpBridge+SyncLAN.swift`. Una entidad nueva hay que tocarla en las dos, más `enqueueLocalChange` en el bridge al guardar/borrar.
- ⚠ **Backup:** es copia completa del SQLite (no lista de tablas), así que la tabla entra sola. El borrado selectivo sí lista tablas: `WipeCategory.LEARNING_SITUATIONS` en `DatabaseWipe.kt`.
- ⚠ **Grupos como equipos:** `workGroupsLinkedToLearningSituation` recorre los cursos enlazados a la SdA (`classLinks`) y filtra `NotebookWorkGroup.learningSituationId`. Un grupo de otro curso no enlazado no aparece.
- ⚠ **Swift nuevo:** `KmpBridge+Tournaments.swift` exige regenerar el proyecto con xcodegen (lo hace otro worker).
- ⚠ **Pantallas de torneos** (`App/Tournament/`, prefijo `Sda`): `LearningSituationTournamentsSection` se monta en `LearningSituationDetailView` con `.id(situation.id)` (reinicia esqueleto al cambiar de SdA). Detalle y modo directo viven en una hoja con su propia `NavigationStack`; el modo directo se apila (no es otra hoja).
- ⚠ **Un torneo = un curso:** `classId` del registro es el del curso elegido; si los grupos son de varios cursos, la hoja pide curso y solo ofrece los grupos de ese curso.
- ⚠ **Guardado:** `SdaTournamentStore` aplica el cambio en pantalla al momento y guarda en cola de uno en uno (gana el último estado). Si falla, `saveFailed` muestra «Reintentar». Borrar espera al guardado en curso para no resucitar el torneo.
- ⚠ **Resultados:** usar siempre `TournamentPlan.setScore/clearScore` (no tocar `savedResults` a mano). En eliminatoria borra los resultados dependientes si cambia un ganador; en liguilla + cruces los cruces no se pueden puntuar hasta cerrar la fase de grupos (`groupStageIsComplete`) y antes se enseñan los huecos «Clasificado 1 Grupo A», no un clasificado provisional.
- ⚠ **Aviso de grupos cambiados:** compara `team_snapshot_json` con los grupos actuales del mismo curso solo para los grupos que ya estaban en el torneo (un grupo nuevo no avisa: puede haberse dejado fuera). «Actualizar equipos» borra resultados y genera calendario nuevo; falla si quedan menos de 2 grupos.
- ⚠ **Duración de sesión:** «¿Cabe en una sesión?» sale del horario docente (`plannerTeacherScheduleSlots`, duración más repetida del curso). `plannerTeacherSchedule()` es `getOrCreate`: leerlo puede crear el horario primario vacío. Sin horario no se inventa un valor.
- ⚠ **«Crear grupos»** abre el Cuaderno del curso (`onOpenModule(.notebook, ...)`), no `NotebookGroupManagementSheet`: esa hoja depende del estado del Cuaderno cargado y de su toast.
- ⚠ **Compilar sin tocar el framework:** spec temporal sin `preBuildScripts`/`postBuildScripts`, `xcodegen --spec <tmp>.yml --project <dir>` y enlazar `Frameworks` dentro de `<dir>` (el `SRCROOT` pasa a ser ese directorio). Con otro worker reconstruyendo `Frameworks/`, esperar a que existan `ios/` y `macos/` con los tipos de torneo.
- ⚠ **Tests de `SdaTournamentSupport`** (`PlannerTests/SdaTournamentSupportTests.swift`) se pueden pasar sin el framework KMP con un paquete SwiftPM temporal que enlace `AppleShared/Tournament/*.swift`, `SdaTournamentSupport.swift` y copias de `TournamentRecord`/`TournamentWorkGroupTeam`.
- ⚠ **Torneo sin SdA:** `learning_situation_tournaments.learning_situation_id` es NULL a propósito (torneos migrados del módulo antiguo de EF, solo de curso). `listTournaments(situationId)` no los devuelve: usar `tournaments(forClassId:)` (bridge) o `listTournamentsByClass`. En SyncLAN salen aparte (`listTournamentsWithoutSituation`) porque el snapshot recorre por situación. La migración 46 sigue sin publicar: si ya se publicó una build con la tabla antigua, hace falta una `47.sqm` que recree la tabla.
- ⚠ **Módulo antiguo de torneos retirado:** ya no existen `TournamentModule.swift`, `CreateTournamentSheet` ni `TournamentViewState`. `PETournamentsWorkspaceView` (`App/Tournament/`) es un placeholder de solo lectura. Los tipos antiguos viven como `Legacy*` en `App/Tournament/LegacyTournamentMigrator.swift` solo para decodificar.
- ⚠ **Migrador al arrancar:** `bridge.migrateLegacyTournamentsIfNeeded()` se llama en `AppleAppRootView` (iOS y macOS) tras `bridge.bootstrap()`, porque `KmpBridge.swift` es protegido. Marca en UserDefaults `workspace.pe.tournaments.migratedToSda.v1`; la clave antigua `workspace.pe.tournaments.v1` NO se borra (copia de seguridad). Idempotente por id (UUID antiguo): si el torneo ya existe en la base no se vuelve a escribir.
- ⚠ **Qué pierde la migración:** BYE (partidos contra «BYE» se descartan), 0-0 (sin campo «jugado» en el módulo antiguo, solo cuenta como jugado si hay algún tanto), marcadores de cruces sin equipos reales, texto libre de pista (solo queda el número), orden de `round` (se renumeran las rondas) y la regla de puntos 3/1/0 propia del torneo (el motor usa la suya). Deporte, puntos, desempate, colores, sesiones enlazadas y niveles/incompatibilidades se guardan en `TournamentPlan.legacyExtras` (`config_json`).
- ⚠ **`legacyExtras` es opcional:** `TournamentPlanConfigSnapshot` y `TournamentPlan` lo conservan al guardar; los torneos nuevos no lo emiten (JSON idéntico al de antes). Si se reescribe el snapshot, no perderlo.
- ⚠ **Cruces del motor:** en eliminatoria usa `Ganador P<n>` (n = posición entre los partidos eliminatorios) y `Clasificado <pos> Grupo <letra>`. El migrador traduce `1A`/`Ganador SF1`/`Ganador <equipo>` del módulo antiguo a esos textos.
- ⚠ **Compilar en worktree:** `Frameworks/` del worktree es una carpeta local (no symlink) construida con `PLATFORM_NAME=iphonesimulator|macosx ARCHS=arm64 GRADLE_USER_HOME=$HOME/.gradle ./scripts/build_apple_framework.sh`. `:shared:test` pide Android SDK: en local usar `:shared:desktopTest`. En el sandbox, `$TMPDIR` cambia al usar `dangerouslyDisableSandbox`: guardar logs en una ruta absoluta.
