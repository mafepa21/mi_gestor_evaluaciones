# Plan: auto-creación de Cursos y Asignaturas al importar horario (2026-07-25)

## Contexto

El asistente "Configurar mi horario" (`TeacherScheduleWizard.swift`, paso 2 "Horario") permite
importar un `.xlsx` del horario docente. El parser (`ScheduleExcelImportService.swift`) ya
detecta grupos y materias por celda, y al confirmar la importación
(`TeacherScheduleSettingsViewModel.importSchedulePreview`) ya crea automáticamente los grupos
(`SchoolClass`, "Curso" en la UI) que no existan — pero:

- No les asocia `subjectId`: el catálogo de `Subject` ("Asignatura") nunca se toca.
- `subjectLabel` de cada franja se guarda como texto libre.
- La reimportación del mismo Excel no es idempotente: los solapes idénticos se marcan como
  **conflicto** y bloquean el botón "Importar horario" (`preview.conflicts.isEmpty` en
  `ScheduleImportPreviewSheet.swift`), en vez de tratarse como "ya importado".
- `groupCode(from:)` solo reconoce grupos con "ESO" en el nombre; grupos de Bachillerato/FP no se
  deduplican y se duplican en cada reimportación.
- `parseCell` pierde el emparejamiento asignatura↔grupo cuando una celda tiene varias entradas
  separadas por `/` (ej. `EFI:1ESOA / MUS:2ESOB`): `subjectCodes` y `groupCodes` se acumulan en
  arrays independientes y se deduplican por separado, así que el bucle de guardado
  (`importSchedulePreview`) escribe el mismo `subjectLabel` (el primero) para todos los grupos de
  la celda.

Se ha revisado el diseño con un agente Opus antes de escribir código; las decisiones de este plan
recogen esa consulta.

## Decisiones de diseño

**D1 — Granularidad del Curso**: seguir creando 1 `SchoolClass` por `groupCode` (no por
combinación grupo+asignatura). La matrícula (`class_students`) cuelga de `SchoolClass`; dividir
por asignatura obligaría a matricular el mismo alumnado varias veces y no es lo que pide el
usuario ("para... poder asignar a cada curso sus alumnos"). En su lugar, se rellena `subjectId`
en el grupo cuando es inequívoco: si el conjunto de asignaturas del grupo (excluyendo tutoría)
tiene exactamente 1 elemento y el grupo no tiene ya `subjectId`, se hace backfill vía
`updateClass`. Si tiene ≥2, se deja sin asignatura fija y se avisa en el preview. Si el grupo ya
tenía `subjectId` puesto a mano, no se toca nunca.

**D2 — Matching de Asignaturas**: cascada determinista sobre clave normalizada (trim + fold
diacríticos/mayúsculas + colapsar espacios): (1) `code` normalizado exacto → reutilizar; (2)
`name` de leyenda normalizado == `name` de un `Subject` existente → reutilizar, **sin sobrescribir
el nombre del catálogo**; (3) sin match → crear con `code`/`name` del Excel. El centinela
`"Clase"` (fallback literal de `resolveSubjectName` cuando el código no está en la leyenda) nunca
genera una asignatura — se crea con `name = code` y aviso en el preview en su lugar.

**D3 — Transparencia**: tarjeta nueva "Se creará" en `ScheduleImportPreviewSheet`, entre
`summary` y `emptySlotControl`, con el resumen de grupos/asignaturas nuevos y reutilizados, y un
único interruptor global para desactivar la creación de asignaturas (los grupos no son opcionales:
sin grupo no hay franja que guardar, igual que hoy).

**D4 — Idempotencia**: (a) reclasificar como aviso (no conflicto bloqueante) el solape *idéntico*
(misma clase, día, hora inicio/fin) y omitirlo al guardar; (b) `groupCode(from:)` gana un segundo
criterio de coincidencia por nombre normalizado contra `groupDisplayName`, para no depender solo
del patrón "ESO"; (c) el índice de asignaturas se recalcula sobre `bridge.subjects` al inicio del
import; (d) el backfill de `subjectId` solo escribe si estaba `nil`, así que una segunda pasada es
no-op.

**D5 — Alcance**: todo se resuelve en `kmp/iosApp/App/` y `kmp/iosApp/AppleShared/`. No hace falta
tocar `kmp/shared/` ni `kmp/data/`: `createClass(name:course:subjectId:)`,
`updateClass(...:subjectId:)` y `saveSubject(id:code:name:stageCycleId:)` ya existen en
`KmpBridge.swift` con lo necesario, y `classes.subject_id` ya admite `NULL`. No se añade
`UNIQUE(code)` a `subjects` (rompería catálogos existentes con duplicados y no cubre el matching
por nombre del nivel 2).

## Bloque A — Parser: emparejar asignatura y grupo

### A1. `ImportedScheduleSlot` gana `assignments: [(subjectCode, groupCode)]`

En `ScheduleImportModels.swift`: nuevo `struct ImportedSlotAssignment: Hashable { let
subjectCode: String; let groupCode: String }` y campo `assignments: [ImportedSlotAssignment]` en
`ImportedScheduleSlot`. `subjectCodes`/`groupCodes` pasan a ser propiedades computadas derivadas
de `assignments` (con `stableUnique`) para no romper los ~10 puntos de lectura existentes
(preview sheet, `detectConflicts`, `buildWarnings`, bucle de guardado).

En `ScheduleExcelImportService.parseCell`: poblar `assignments` con el par de cada segmento
separado por `/`. Commit propio (`refactor`) para poder revertirlo aislado si algo se rompe.

## Bloque B — Servicio de resolución de catálogo

### B1. `ScheduleImportCatalogResolver`

Tipo nuevo en `kmp/iosApp/AppleShared/ScheduleImportCatalogResolver.swift`, sin dependencia de
`KmpBridge` (recibe arrays planos, testeable):

- `normalizedKey(_:) -> String`.
- `resolveSubjects(preview:existingSubjects:) -> SubjectResolution` (matched / toCreate / avisos),
  excluyendo el centinela `"Clase"` y códigos vacíos.
- `resolveGroups(preview:existingGroups:) -> GroupResolution`, con doble clave (código parseado +
  nombre normalizado contra `groupDisplayName`).
- `subjectByGroup(preview:) -> [String: Set<String>]`, ignorando `kind == .tutoring`, base del
  backfill de D1.

## Bloque C — Wiring en el ViewModel

`TeacherScheduleSettingsView.swift` (`TeacherScheduleSettingsViewModel`):

- `previewScheduleImport`: calcula el plan de catálogo y lo publica junto al preview
  (`@Published var scheduleImportPlan: ScheduleImportCatalogPlan?`).
- `previewWithExistingConflicts`: separa el solape idéntico (aviso, no bloquea) del solape
  distinto (conflicto real, sigue bloqueando).
- `ensureImportedGroups` → `ensureImportedCatalog(_:createSubjects:)`: crea asignaturas faltantes
  (si `createSubjects`), crea grupos faltantes ya con `subjectId` cuando aplica D1, y hace
  backfill de `subjectId` en grupos existentes sin asignatura. Corrige de paso el
  `ensureClassesLoaded()` redundante dentro del bucle (ya lo hace `createClass`).
- `importSchedulePreview`: usa `assignments` para escribir el `subjectLabel` correcto por grupo
  (arregla el bug de A1), omite franjas ya existentes idénticas, y recibe `createSubjects: Bool`
  desde el sheet.

## Bloque D — UI del preview

`ScheduleImportPreviewSheet.swift`: tarjeta `catalogPlanCard` (mismo tratamiento visual que
`emptySlotControl`) entre `summary` y `emptySlotControl`, con toggle `createSubjects` (`@State`,
por defecto `true`). `onConfirm` gana el parámetro `createSubjects`.

## Bloque E — Wizard

`TeacherScheduleWizard.swift:130-137`: propagar `vm.scheduleImportPlan` y el nuevo parámetro del
closure de confirmación al `ScheduleImportPreviewSheet`.

## Fuera de alcance (no se implementa ahora)

- Modo "reemplazar horario existente" frente a "añadir".
- Dividir un grupo en varios cuando imparte ≥2 asignaturas (el usuario lo hace a mano duplicando
  el grupo desde Cursos si quiere cuadernos separados).
- Generalizar `groupCode(from:)` más allá del rescate por nombre normalizado (Bloque B).
- El menú de "Gestión de datos" en Ajustes para borrado rápido de Cursos/Asignaturas/Rúbricas:
  tarea aparte, decidido con el usuario.

## Orden de trabajo y commits

1. `refactor(horario): emparejar asignatura y grupo en el parser de importación` (Bloque A)
2. `feat(horario): resolver catálogo de cursos y asignaturas al importar` (Bloque B + C)
3. `ui(horario): mostrar los cursos y asignaturas que se crearán al importar` (Bloque D + E)
4. `docs(plan): plan de auto-creación de cursos y asignaturas al importar horario` (este documento)

Cada commit lleva su entrada en `docs/CHANGELOG.md` bajo `## Unreleased`.

## Verificación exigida

- `swiftc -parse` de los archivos tocados (no hay target de tests Swift para este importador).
- Build real del target iOS/macOS con `DEVELOPER_DIR` apuntando al Xcode de `~/Downloads` (ver
  memoria del proyecto) si el entorno lo permite; si no, decirlo explícitamente en el PR.
- Caso probado a mano con el Excel `Horario_del_Profesor_20260725_144036.xlsx` adjuntado por el
  usuario: importar, comprobar cursos/asignaturas creados, reimportar y comprobar 0 duplicados.

## Archivos que se van a tocar

- `kmp/iosApp/AppleShared/ScheduleImportModels.swift`
- `kmp/iosApp/AppleShared/ScheduleExcelImportService.swift`
- `kmp/iosApp/AppleShared/ScheduleImportCatalogResolver.swift` (nuevo)
- `kmp/iosApp/AppleShared/ScheduleImportPreviewSheet.swift`
- `kmp/iosApp/App/TeacherScheduleSettingsView.swift`
- `kmp/iosApp/App/TeacherScheduleWizard.swift`
- `kmp/iosApp/MiGestorKMPiOS.xcodeproj/project.pbxproj` (regenerar con XcodeGen al añadir el
  archivo nuevo, si el entorno lo permite)
- `docs/CHANGELOG.md`
