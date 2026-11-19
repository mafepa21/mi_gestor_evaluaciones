# Diseño técnico · Portal fase 2 «Mis notas» (architect, 2026-11-19)

Complementa `ticket_portal_alumnado_fase2_notas_2026-11-19.md`. Rutas relativas a `kmp/`.

## 1. Saber que una nota cambió: vigilar la base

No hay un punto común en Swift: el grid guarda por el ViewModel de Kotlin (`iosApp/App/Bridge/KmpBridge+Notebook.swift:107-182`), las rúbricas escriben desde Kotlin (`RubricEvaluationViewModel.kt:319`, `RubricBulkEvaluationViewModel.kt:321/345/400`), `enqueueLocalChange` está en el archivo protegido y `NotebookRefreshBus` no lleva `classId` ni lo emite el guardado normal.

Decisión: `AppleShared/WebPortalGradesWatcher.swift`, una sola entrada `schedulePortalGradesRepublish(classId:)`, alimentada por:

1. `container.gradesRepository.observeGradesForClass(classId)` (`Contracts.kt:249`) y `container.notebookCellsRepository.observeClassCells(classId)` (`Contracts.kt:343`), descartando la primera emisión. Cubre grid, rúbricas, ordinales, pruebas físicas, importación web y Sync LAN aplicado en el Mac (mismo driver).
2. `.lanSyncRemoteChangesApplied` (`KmpBridge+SyncLAN.swift:937-941`): si toca `LanSyncRefreshPlan.steps(...).notebookEntities` (`:5361-5366`), marcar todos los grupos vigilados.
3. Una línea en la rama de cambio externo de `checkLocalDbFileModification` (`KmpBridge+SyncLAN.swift:4934`) que marque todos los grupos vigilados.
4. `NotebookRefreshBus.shared.refreshSignal`: pesos, columnas y ocultas → todos los grupos vigilados.

- `FlowAsyncSequence` no se cancela (`KmpFlowSupport.swift:11-38`): un vigilante por grupo, en un `Set`, nunca se para; si el grupo está apagado, no hace nada.
- Arranque al final de `refreshClasses()` (`KmpBridge+Students.swift:15`) y al encender un interruptor, solo en grupos con alguna columna activa. Idempotente.
- Resumen en memoria del bloque `notas` por alumno: no subir si no cambió.

## 2. Informe del grupo sin abrirlo en el Cuaderno

- `container.notebookRepository.loadNotebookSnapshot(classId)` (`Contracts.kt:405`, `NotebookRepositorySqlDelight.kt:46`): hoja completa, fuera del hilo principal y con caché.
- Para que la media coincida con el Cuaderno y el PDF (media de la pestaña activa, `NotebookViewModel.kt:1267-1301`):
  - pestaña = `restoredSelectedNotebookTab(forClassId:)` (`KmpBridge+Rubrics.swift:361`) o la primera de `sheet.tabs`;
  - filtro: `tabIds.contains(tab) || (sharedAcrossTabs && tabIds.isEmpty)`;
  - recalcular con `computeAverageExplanation(columns:)` (`Models.kt:1862`, solo llamarla);
  - rehacer la fila con `NotebookRow(student:cells:weightedAverage:averageExplanation:persistedCells:persistedGrades:)` (`Models.kt:1670`).
- Sobrecarga `buildStudentGradeReports(classId:columns:rows:)` en `KmpBridge+GradeReports.swift:16`; la de `data:` le delega y el PDF no cambia.

## 3. Fecha, materia y grupo

- `fecha` = `column.dateEpochMs` (`Models.kt:1355`) en `yyyy-MM-dd` local; si falta, se omite. No usar `trace.createdAt`.
- `grupo` = nombre de la clase (como `WebPortalPublisher.swift:229`).
- `materia` = `SchoolClass.subjectId` (`Models.kt:163`) con `subjectsRepository.listSubjects()` (`KmpBridge+Students.swift:53`); si no hay, se omite.

## 4. Rendimiento

- Hilo principal: solo contabilidad (un `Task` por grupo que duerme 600 s y se reinicia con cada aviso; avisos de Kotlin → `Task { @MainActor in … }`).
- Informe, JSON y cifrado en `Task.detached(priority: .utility)` o funciones `nonisolated`.
- Caché de hojas de 4 entradas (`NotebookPerformanceCaches.kt:45-62`): publicar grupos de uno en uno con `WebPortalPublishQueue`.
- Solo se vigilan grupos con alguna columna activa (cada guardado relanza 2N consultas pequeñas).

## Criterios extra

- Ninguna edición en `KmpBridge.swift`, `shared/domain`, sqldelight ni `NotebookModuleView`.
- Nota llegada del iPad con el grupo cerrado en el Mac → portal entre 10 y 11 min después.
- PDF y portal con la misma media para la misma pestaña (test).
- Con el Cuaderno editando, nada del portal por encima de 5 ms en el hilo principal.
