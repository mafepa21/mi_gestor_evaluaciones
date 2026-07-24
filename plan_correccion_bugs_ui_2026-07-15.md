# Plan de corrección de bugs de UI/usabilidad — rama `fix/ui-errores-silenciados-y-teclados` (2026-07-15)

Plan pensado para que lo ejecute un agente (Sonnet) de forma autónoma.

## Reglas de trabajo para el agente

- Rama nueva desde `main`: `fix/ui-errores-silenciados-y-teclados`.
- **Un commit atómico por bug**, formato `fix(<ámbito>): <descripción>`. No agrupes bugs distintos en un commit.
- Actualiza `docs/CHANGELOG.md` con una entrada por fix, en el mismo commit que el fix, bajo `## Unreleased` → `### Fixed`.
- No hace falta verificación con tests (no hay tests Swift; no se toca Kotlin).
- No tocar `kmp/iosApp/App/KmpBridge.swift`, `kmp/iosApp/App/EvaluationDesign.swift`, `kmp/shared/`, `kmp/data/`, `kmp/desktopApp/`.
- Cambios quirúrgicos: no refactorizar, no reformatear código circundante, imitar el estilo del archivo.
- Mensajes de UI siempre en español.

---

## Prioridad ALTA

### B1 — Las hojas de creación silencian errores de guardado y cierran como si todo hubiera ido bien

**Archivo:** `kmp/iosApp/App/WorkspaceCreationSheets.swift`

**Problema:** Siete hojas usan `try?` sobre la llamada al bridge dentro de `save()` y después llaman a `close()`/`dismiss()` incondicionalmente. Si el guardado falla (error de BD/bridge), el docente ve cerrarse la hoja creyendo que el dato existe, y no existe. Afectadas: `CreateCourseSheet.save()`, `CreateStudentSheet.save()`, `CreateEvaluationSheet.save()`, `CreatePESessionSheet.save()`, `CreatePhysicalTestSheet.save()`, `CreatePEIncidentSheet.save()` (la rama de fallo hoy no muestra ningún error, aunque tampoco cierra), `CreatePEMaterialRecordSheet.save()`. No se toca `CreateTournamentSheet` (no persiste vía bridge) ni `SupportMeasureFormSheet` (ya corregida en una rama previa).

**Fix:** replicar en cada hoja el patrón ya existente de `SupportMeasureFormSheet` en el mismo archivo:
1. `@State private var errorMessage: String?`.
2. Un `.alert` con binding derivado (`get: { errorMessage != nil }`) que muestra el texto y botón OK.
3. En `save()`: `do { _ = try await bridge...; close() } catch { errorMessage = "No se pudo crear <el recurso>: \(error.localizedDescription)" }`. Solo cerrar/descartar en éxito.
4. Mantener intactos los `guard` de validación previos.

**Criterio de aceptación:** no queda ningún `try?` sobre llamadas de guardado del bridge en ese archivo (fuera de las hojas excluidas); un fallo deja la hoja abierta con alerta visible.

**Commit:** `fix(app): mostrar error y no cerrar las hojas de creación cuando falla el guardado`

---

## Prioridad MEDIA

### B2 — Cambiar el estado de una sesión del planner finge éxito y actualiza la UI aunque la persistencia falle

**Archivo:** `kmp/iosApp/App/PlannerWorkspaceViewModel+BulkOperations.swift`, función `setSessionStatus(_:status:)`.

**Problema:** `_ = try? await bridge.plannerUpsertSession(...)` seguido incondicionalmente de `updateLocalSession(session, status: status)`. Si el upsert falla, la UI muestra el nuevo estado (p. ej. "Cerrada") pero la BD conserva el anterior; en la siguiente recarga el estado revierte en silencio. Lo usan `markCompleted` y el deshacer de la vista Día.

**Fix:** envolver en `do/catch`. En éxito, comportamiento actual. En error: NO llamar a `updateLocalSession`, y publicar el error en `bulkSummary` (el canal que ya usa este ViewModel para mensajes de operaciones, ya usado por `deleteSession` en el mismo archivo). Mensaje: "No se pudo actualizar el estado de la sesión.". Mantener `await reloadJournalSummaries()` solo en éxito.

**Commit:** `fix(planner): no fingir éxito al cambiar el estado de una sesión si falla la persistencia`

---

### B3 — Campos numéricos sin teclado numérico en iOS

**Archivos:**
- `kmp/iosApp/App/NotebookStructuredInstrumentSupport.swift`: `TextField("Valor", text: $item.numberValue)` (caso `.number`).
- `kmp/iosApp/App/LearningSituationsWorkspaceView.swift`: `TextField("Peso %", text: weightBinding(for: index))`.
- `kmp/iosApp/App/PhysicalTestsWorkspaceView.swift`: `PhysicalTestSheetTextField(title: "Peso", ...)`.

**Problema:** El teclado completo QWERTY aparece para campos que solo aceptan números; el proyecto ya tiene el helper multiplataforma `.appKeyboardType(.decimalPad)` (en `kmp/iosApp/AppleShared/AppleViewCompatibility.swift`) usado en el resto de la app, pero falta en estos puntos.

**Fix:** añadir `.appKeyboardType(.decimalPad)` en el punto de uso de cada `TextField`. No modificar componentes genéricos reutilizables.

**Criterio de aceptación:** los tres campos abren teclado decimal en iOS.

**Commit:** `fix(ui): teclado decimal en campos numéricos de instrumentos, situaciones de aprendizaje y tests físicos`

---

## Orden de ejecución sugerido

1. B1 (mayor impacto en integridad de datos percibida por el docente).
2. B2 (mismo patrón, otra zona del código).
3. B3 (cambio mecánico, independiente de los anteriores).

## Qué NO tocar

- `kmp/iosApp/App/KmpBridge.swift`, `kmp/iosApp/App/EvaluationDesign.swift`, `kmp/shared/`, `kmp/data/`, `kmp/desktopApp/`.
- `CreateTournamentSheet` y `SupportMeasureFormSheet` en `WorkspaceCreationSheets.swift` (fuera de alcance de B1, la segunda ya corregida).
- El componente genérico `PhysicalTestSheetTextField` (el modificador de teclado se aplica en el punto de uso, no en el componente).
