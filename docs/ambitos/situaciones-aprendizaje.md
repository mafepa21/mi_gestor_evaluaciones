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
- **Pendiente:** rediseño de usabilidad (ticket `codex/ui-situaciones-aprendizaje`).

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
- ⚠ **Compilar:** `Frameworks/` (MiGestorKit) no está en git. Enlazarlo desde el checkout principal antes de `xcodebuild`.
