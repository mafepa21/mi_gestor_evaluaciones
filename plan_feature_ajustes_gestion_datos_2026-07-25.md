# Plan: menú "Gestión de datos" en Ajustes (2026-07-25)

## Contexto

El usuario pidió, en la misma conversación que la auto-creación de cursos/asignaturas al
importar horario (ver `plan_feature_horario_auto_creacion_2026-07-25.md`, PR #155), un menú en
Ajustes para eliminar rápidamente Cursos, Asignaturas, Rúbricas y Situaciones de aprendizaje.

Decisión ya acordada con el usuario (`AskUserQuestion` en la conversación): **una sola pantalla
"Gestión de datos"** con una sección por tipo de entidad, cada una con selección múltiple y
borrado en lote — no una pantalla de entrada que navegue a 4 pantallas separadas.

Hoy Ajustes → "Datos y seguridad" (`SettingsDangerZoneView.swift`) solo tiene el borrado total
de la app (`wipeAllData()`, exige escribir "BORRAR", borra el archivo SQLite completo). No hay
ningún borrado granular por tipo de entidad ahí. El único precedente de selección múltiple +
borrado en lote en la app es `LearningSituationsWorkspaceView.swift` (`isSelectionMode` +
`Set<Int64>` + alert + bucle de borrado) — se usa como referencia de patrón, pero no se toca ese
archivo ni se reutiliza literalmente (esa vista es una `List(selection:)` que ocupa toda la
pantalla; aquí necesito 4 secciones independientes en una sola pantalla, así que la selección se
implementa con filas propias en vez de anidar 4 `List` dentro de un `ScrollView`).

## Alcance y lo que se descarta

- **No se toca `KmpBridge.swift`** (archivo protegido por `AGENTS.md`). Esto descarta mostrar
  "N alumnos matriculados" por curso (requeriría un método nuevo `studentCount(forClassId:)`,
  ver hallazgo de la exploración) — en su lugar, el aviso de borrado de un curso es un texto
  fijo que explica qué se borra en cascada (alumnado, asistencia, evaluaciones, notas), que es
  más importante que la cifra exacta y no requiere tocar el archivo protegido.
- **No se toca `kmp/shared/` ni `kmp/data/`**: no hace falta esquema nuevo; todo se resuelve con
  los métodos y propiedades `@Published` que `KmpBridge` ya expone (`classes`, `subjects`,
  `rubrics`, `deleteClass`, `deleteSubject`, `deleteRubric`, `learningSituations()`,
  `deleteLearningSituation`, `refreshRubrics()`).
- **No se arregla** el bug ya detectado en `RubricsViewModel.deleteRubric` (Kotlin,
  fire-and-forget con `catch { }` vacío) — está en `kmp/shared/viewmodel/`, fuera del alcance de
  una tarea de UI. En su lugar, el borrado en lote de rúbricas hace una verificación honesta
  después: refresca `bridge.rubrics` y avisa si alguna de las rúbricas seleccionadas sigue
  presente, en vez de asumir que todas se borraron.
- Cursos y Asignaturas sí tienen borrado `async throws` real (`deleteClass`/`deleteSubject`); el
  borrado en lote captura el error de cada elemento individualmente (mejora sobre el patrón de
  `LearningSituationsWorkspaceView`, que corta el bucle entero al primer fallo).

## Diseño

Un componente reutilizable `BulkDeleteSection` (lista de `DataManagementItem` planos —
`id: Int64, title: String, subtitle: String?` — desacoplado de los tipos KMP concretos) con:
modo selección, checkbox por fila, "Eliminar (N)" + alert de confirmación con el aviso
específico de la entidad, borrado individual vía swipe/menú contextual con su propio alert.

`DataManagementSettingsView` (nueva, en `AppleShared/`, mismo patrón que
`DataSecuritySettingsView`) compone 4 `BulkDeleteSection`, una por entidad, mapeando
`bridge.classes` / `bridge.subjects` / `bridge.rubrics` / `learningSituations()` (este último
cargado en `.task`, como ya hace el resto de la app, porque no hay `@Published` para SA) a
`DataManagementItem`.

Se añade como sección nueva de Ajustes (no dentro de "Datos y seguridad", para no mezclar el
borrado nuclear con el borrado granular — son acciones de intención distinta):

- `SettingsSectionDescriptor.all` (iOS/iPad, `SettingsWorkspaceView.swift`): nueva entrada
  `"datamgmt"`.
- `SettingsRoute` (macOS, `AppSettingsModels.swift`): nuevo caso `.dataManagement`.
- Router de detalle en ambos (`settingsDetail(for:)` en iOS, `detailViewForRoute(_:)` en macOS).

## Archivos que se van a tocar

- `kmp/iosApp/AppleShared/DataManagementSettingsView.swift` (nuevo)
- `kmp/iosApp/App/SettingsWorkspaceView.swift`
- `kmp/iosApp/AppleShared/AppSettingsModels.swift`
- `kmp/iosApp/MacApp/MacSettingsView.swift`
- `kmp/iosApp/MiGestorKMPiOS.xcodeproj/project.pbxproj` (regenerar con XcodeGen, archivo nuevo)
- `docs/CHANGELOG.md`

## Orden de trabajo y commits

1. `feat(ajustes): añadir pantalla de gestión de datos con borrado en lote` (componente +
   vista + wiring en ambas plataformas)
2. `docs(plan): plan del menú de gestión de datos en Ajustes` (este documento, en el mismo
   commit o en uno separado según convenga al cerrar)

## Verificación exigida

- Build real macOS (`xcodebuild -scheme MiGestorKMPMac build`, `DEVELOPER_DIR` al Xcode de
  `~/Downloads`) — mismo procedimiento que en el PR #155.
- No hay target de tests Swift para esta pantalla.
- No se prueba visualmente en simulador en esta tarea (mismo límite que el PR anterior); queda
  pendiente de verificación manual por el usuario o una sesión con acceso a simulador.
