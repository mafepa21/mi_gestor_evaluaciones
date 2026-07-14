# Plan de corrección de bugs — rama `feature/medidas-apoyo-nivel-iii-iv` (2026-07-13)

Revisión del diff completo `main...feature/medidas-apoyo-nivel-iii-iv` (~5.000 líneas).
Este plan está pensado para que lo ejecute un agente (Sonnet) de forma autónoma.

## Reglas de trabajo para el agente

- Trabaja sobre la rama `feature/medidas-apoyo-nivel-iii-iv` (o una rama hija `fix/...` si `main` ya la absorbió).
- **Un commit atómico por bug**, formato `fix(<ámbito>): <descripción>` (p.ej. `fix(medidas): ...`). No agrupes bugs distintos en un commit.
- Actualiza `docs/CHANGELOG.md` con una entrada por fix (misma disciplina que el resto del repo, en español).
- Verificación mínima tras cada cambio:
  - Cambios Kotlin (`kmp/shared`, `kmp/data`): `./gradlew :shared:desktopTest :data:desktopTest` desde `kmp/`.
  - Cambios Swift: compilar `xcodebuild -project kmp/iosApp/MiGestorKMPiOS.xcodeproj -scheme MiGestorKMPMac build` (o el scheme iOS). Nota: hay fallos preexistentes de CI ajenos a esta rama; compara contra el estado previo, no exijas verde absoluto.
- No toques `EvaluationDesign.swift` ni `desktopApp/` salvo lo indicado.
- Mensajes de UI siempre en español.

---

## Prioridad ALTA

### B1 — Los guardados de medidas silencian errores y reportan éxito igualmente

**Archivos:**
- `kmp/iosApp/App/SupportMeasureBulkImportSheet.swift` → `confirmImport()`
- `kmp/iosApp/App/WorkspaceCreationSheets.swift` → `SupportMeasureFormSheet.save()`

**Problema:** Ambos usan `_ = try? await bridge.saveSupportMeasure(...)` dentro de un bucle y después llaman incondicionalmente a `onImported()`/`onSaved()` y `dismiss()`. Si el guardado falla (error de BD, bridge), el docente ve la hoja cerrarse como si todo hubiera ido bien y las medidas no existen. Es especialmente grave en la importación masiva (decenas de registros NEE).

**Fix:**
1. En `confirmImport()`: envolver el bucle en `do/catch` por fila, contar `savedCount` y `failedCount`. Si `failedCount > 0`, NO cerrar la hoja: mostrar `errorMessage` (ya existe el alert) con "Se han guardado X medidas; Y han fallado: <primer error>". Solo llamar `onImported()` + `dismiss()` si `failedCount == 0` (y aún así llamar `onImported()` si `savedCount > 0`, para refrescar la ficha).
2. En `SupportMeasureFormSheet.save()`: mismo patrón. Añadir `@State private var errorMessage: String?` y un `.alert` (copiar el patrón del alert de `SupportMeasureBulkImportSheet`). Solo `dismiss()` en éxito.

**Criterio de aceptación:** ningún `try?` sobre `saveSupportMeasure` en estos dos archivos; un fallo de guardado deja la hoja abierta con mensaje de error visible.

---

### B2 — Las filas "sugeridas" se importan sin confirmación manual del docente

**Archivos:**
- `kmp/iosApp/AppleShared/SupportMeasureBulkImport.swift` → `match(rows:against:)`, `SupportMeasureImportRow`
- `kmp/iosApp/App/SupportMeasureBulkImportSheet.swift` → `confirmedCount`, `importRow`, `studentPicker`, `confirmImport()`

**Problema:** El contrato documentado (doc comment de `SupportMeasureMatchStatus` y del propio sheet, y commit `cf5ac107` "confirmación manual obligatoria") dice que solo `.exact` se autoselecciona y que cualquier coincidencia parcial exige elección manual. Pero `match()` precarga `row.confirmedStudent = candidates.first` para `.suggested`, y `confirmImport()` guarda toda fila con `confirmedStudent != nil`. Resultado: una sugerencia del emparejador de apellidos abreviados que el docente nunca tocó se importa igual — asignar una medida NEE al alumno equivocado.

**Fix (mantener la preselección visual, exigir confirmación explícita):**
1. Añadir a `SupportMeasureImportRow` un campo `var isManuallyConfirmed: Bool = false`. En `match()`, poner `isManuallyConfirmed = true` solo en la rama `.exact`; en `.suggested` mantener la precarga de `confirmedStudent` pero con `isManuallyConfirmed = false`.
2. En el sheet, `setConfirmedStudent(_:for:)` pone `isManuallyConfirmed = (student != nil)`.
3. Redefinir `confirmedCount`/`needsReviewCount` y el filtro de `confirmImport()` sobre `confirmedStudent != nil && isManuallyConfirmed`.
4. En `importRow`, para filas sugeridas no confirmadas, añadir un botón compacto "Confirmar" junto al desplegable que marque `isManuallyConfirmed = true` sin abrir el menú (para no penalizar el caso feliz).
5. Ajustar el texto del resumen: "Las filas sugeridas necesitan confirmación (botón Confirmar o desplegable) antes de importarse."

**Criterio de aceptación:** con un Excel cuyo nombre solo matchea de forma abreviada, el contador "Confirmados" es 0 hasta que el docente pulsa Confirmar o elige en el desplegable; solo `.exact` cuenta de inicio.

---

### B3 — Editar una medida permite guardar nivel/tipo incoherentes

**Archivo:** `kmp/iosApp/App/WorkspaceCreationSheets.swift` → `SupportMeasureFormSheet` (`canSave`, `save()`).

**Problema:** En modo edición, `canSave` es siempre `true`. Si el docente edita una medida de Nivel IV (p.ej. ACIS) y cambia el segmento a Nivel III sin marcar ninguna medida del catálogo, `save()` hace `selectedTypesIII.first ?? existingMeasure.measureType` → guarda `level = .iii` con `measureType = .acis` (tipo de Nivel IV). Queda un registro incoherente en BD (el `level` de la fila contradice `measureType.level`) que además pinta mal en las vistas de grupo.

**Fix:**
1. `canSave` en edición: `level == .iii ? !selectedTypesIII.isEmpty : true` (igual que en alta).
2. En `save()` (ambos caminos, alta y edición), derivar el nivel del tipo al construir el draft: en `draft(for:)`, usar `type.level` en lugar del `level` del picker (son equivalentes cuando la UI es coherente, y elimina la posibilidad de desalineación).
3. Al cambiar el nivel en edición (`appOnChange(of: level)`), si se vuelve al nivel original de la medida, re-preseleccionar el tipo original (mejora, opcional).

**Criterio de aceptación:** es imposible persistir una fila cuyo `level` ≠ `measureType.level`. Añadir esta aserción como test si es viable (ver B4, capa Kotlin: `SaveStudentSupportMeasureUseCase` puede validar `require(levelOf(measureType) == level)` — el mapeo nivel→tipos existe solo en Swift; si se añade en Kotlin, replicar la tabla en `Models.kt` con una función `SupportMeasureType.level()`).

---

## Prioridad MEDIA

### B4 — Editar una medida machaca metadatos en BD (created_at, end_date, sync_version)

**Archivos:**
- `kmp/iosApp/App/KmpBridge.swift` → `saveSupportMeasure(id:draft:)`
- `kmp/data/src/commonMain/kotlin/com/migestor/data/repository/SqlDelightRepositories.kt` → `StudentSupportMeasureRepositorySqlDelight.save`
- `kmp/data/src/commonMain/sqldelight/com/migestor/data/db/AppDatabase.sq` → `upsertSupportMeasure`

**Problema:** `upsertSupportMeasure` es `INSERT OR REPLACE`. Al editar (id != nil), el bridge pasa `createdAtEpochMs: 0`, `endDateIso: nil`, `isActive: true`, `syncVersion: 1`. Consecuencias: (a) `created_at_epoch_ms` se resetea a 0; (b) si la fila estaba retirada, se reactiva y pierde `end_date_iso`; (c) `sync_version` vuelve a 1 aunque `retire` la hubiera subido, rompiendo la monotonía que usa la sincronización.

**Fix (en la capa de datos, no en cada llamador):**
1. En `StudentSupportMeasureRepositorySqlDelight.save`, cuando `id != null`, leer primero la fila existente (añadir query `selectSupportMeasureById` en `AppDatabase.sq`) y preservar: `created_at_epoch_ms` original, `end_date_iso`/`is_active` originales salvo que el llamador los cambie deliberadamente, y `sync_version = max(existente, syncVersion) + 1`.
2. Alternativa más simple y explícita: añadir una query `updateSupportMeasure` (UPDATE de los campos editables: level, measure_type, start_date_iso, responsible, intensity, follow_up_notes, document_ref, review_due_iso, updated_at_epoch_ms, device_id, sync_version = sync_version + 1) y usarla cuando `id != null`, dejando el INSERT solo para altas. **Preferir esta opción.**
3. Ampliar `StudentSupportMeasureRepositoryIntegrationTest` (`kmp/data/src/desktopTest/.../StudentSupportMeasureRepositoryIntegrationTest.kt`): editar una medida existente debe conservar `created_at_epoch_ms` e incrementar `sync_version`; editar una medida retirada no debe reactivarla.

**Criterio de aceptación:** los tests nuevos de `:data:desktopTest` pasan.

---

### B5 — Borrados destructivos sin confirmación (macOS medidas, torneos, material)

**Archivos:**
- `kmp/iosApp/MacApp/MacStudentsView.swift` → contextMenu de `macSupportMeasureRow` llama a `deleteSupportMeasure(measure)` directamente.
- `kmp/iosApp/App/LibraryAndPEWorkspaceViews.swift` → `PETournamentsWorkspaceView.deleteTournament` y `PEMaterialWorkspaceView.deleteMaterialRecord` se ejecutan directamente desde swipe/contextMenu.

**Problema:** En iOS, eliminar una medida pasa por `confirmationDialog`; en macOS el mismo gesto borra sin preguntar. Eliminar un torneo borra equipos, partidos y resultados sin confirmación. Inconsistente y peligroso (borrado real, no papelera).

**Fix:**
1. `MacStudentsView`: añadir `@State private var pendingDeleteSupportMeasure: SupportMeasureRow?` + `confirmationDialog` idéntico al de `StudentProfilesWorkspaceView` (mismo texto: "Se eliminará este registro por completo. Si solo quieres cerrarla, usa \"Retirar\"."). El contextMenu solo setea el pending.
2. `PETournamentsWorkspaceView`: `@State var pendingDeleteTournament: TournamentViewState?` + `confirmationDialog` ("Se eliminará el torneo, sus equipos y todos los resultados.").
3. `PEMaterialWorkspaceView`: mismo patrón ("Se eliminará el registro de material.").

**Criterio de aceptación:** ningún borrado se ejecuta directamente desde un gesto; todos pasan por `confirmationDialog`.

---

### B6 — Importar el mismo Excel dos veces duplica todas las medidas

**Archivo:** `kmp/iosApp/App/SupportMeasureBulkImportSheet.swift` → `confirmImport()`.

**Problema:** No se comprueba si el alumno ya tiene la medida activa. Reimportar (algo natural: el docente actualiza el Excel a mitad de curso) duplica todos los registros.

**Fix:**
1. En `confirmImport()`, antes del bucle, cargar por alumno confirmado sus medidas activas: `try await bridge.supportMeasures(for: student.id)` (cachear en un diccionario `[Int64: Set<SupportMeasureTypeUI>]` filtrando `isActive && level == .iii`).
2. Saltar cada `measure` ya activa para ese alumno; contar `skippedCount`.
3. Reflejarlo en el mensaje final/estado: "X medidas importadas, Y omitidas por estar ya registradas." (usar `bridge.status` o el alert de B1).

**Criterio de aceptación:** importar dos veces el mismo archivo deja exactamente las mismas filas en BD que importarlo una vez.

---

### B7 — `updatePhysicalTest` borra fórmula y rúbrica de la evaluación editada

**Archivo:** `kmp/iosApp/App/KmpBridge.swift` → `updatePhysicalTest(...)`.

**Problema:** Al guardar la edición pasa `formula: nil, rubricId: nil` fijos. Si la evaluación subyacente tuviera fórmula o rúbrica vinculada (posible si la prueba se creó/ajustó desde el cuaderno), editar nombre/peso las borra silenciosamente.

**Fix:** `PhysicalTestsWorkspaceView.updatePhysicalTest` ya tiene el `test.evaluation` completo: pasar `evaluation.formula` y `evaluation.rubricId` a través de `bridge.updatePhysicalTest` (añadir parámetros `formula: String?` y `rubricId: Int64?` y propagarlos a `saveEvaluation` y al payload de `enqueueLocalChange`).

**Criterio de aceptación:** editar el peso de una prueba física no altera `formula` ni `rubric_id` en la fila `evaluations`.

---

## Prioridad BAJA

### B8 — "REPETICIÓN" con acento no se reconoce en la columna "Otras"

**Archivo:** `kmp/iosApp/AppleShared/SupportMeasureBulkImport.swift` → `parse(url:)`, bloque `otrasColumn`.

**Problema:** `value.uppercased() == "REPETICION"` no matchea "Repetición" (con tilde), que es como lo escribirá un docente en español. La medida cae a nota en vez de marcarse.

**Fix:** normalizar con folding diacrítico antes de comparar, p.ej. `value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES")).uppercased() == "REPETICION"` (o reutilizar `normalizedTokens` y comparar `["REPETICION"]`).

### B9 — `fromCatalogCode` corrompe códigos al reemplazar ".0" en cualquier posición

**Archivo:** `kmp/iosApp/AppleShared/SupportMeasureShared.swift` → `fromCatalogCode(_:)`.

**Problema:** `.replacingOccurrences(of: ".0", with: "")` reemplaza en cualquier posición ("1.05" → "15"), no solo el sufijo decimal de Excel ("3.0" → "3").

**Fix:** reemplazar solo el sufijo: `if normalized.hasSuffix(".0") { normalized.removeLast(2) }` (tras el trim/uppercase, antes de quitar espacios).

### B10 — `deleteSession` del planner silencia errores y anuncia éxito

**Archivo:** `kmp/iosApp/App/PlannerWorkspaceViewModel+BulkOperations.swift` → `deleteSession(_:)`.

**Problema:** `try? await bridge.plannerDeleteSession(...)` seguido de `bulkSummary = "Sesión eliminada."` incondicional.

**Fix:** `do/catch`; en el catch, `bulkSummary = "No se pudo eliminar la sesión: \(error.localizedDescription)"` y no tocar la selección.

### B11 — La vista de medidas del grupo carga en serie (N llamadas secuenciales)

**Archivo:** `kmp/iosApp/App/SupportMeasureGroupOverviewSheet.swift` → `loadMeasures()`.

**Problema:** un `for` con `await` por alumno; con 30 alumnos son 30 round-trips secuenciales al bridge. Solo lentitud, no corrupción.

**Fix:** usar `withTaskGroup` para paralelizar las llamadas `bridge.supportMeasures(for:)` (o añadir al bridge un `activeSupportMeasures(forStudents:)` que haga una sola query con `WHERE student_id IN (...)` — preferible si se quiere tocar KMP; si no, el task group es suficiente).

---

## Orden de ejecución sugerido

1. B1 (base para B2/B6: introduce manejo de errores en `confirmImport`).
2. B2, B6 (misma zona de código; commits separados).
3. B3 (formulario).
4. B4 (Kotlin + tests de integración).
5. B5, B7 (independientes).
6. B8–B11 (rápidos).

## Qué NO tocar

- La precarga visual de sugerencias (commit `74fc88f1`) se mantiene: B2 solo añade el requisito de confirmación explícita.
- El filtro por columna "Clase" en la importación importa solo las filas visibles: es intencional (el contador del footer lo refleja).
- `NotebookViewModel.loadGeneration`, la invalidación de `NotebookSheetMemoryCache` y `deriveObservationGridScore` están correctos según esta revisión; no refactorizar.
