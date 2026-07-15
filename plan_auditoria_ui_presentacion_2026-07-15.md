# Plan de corrección — Auditoría de UI de presentación: encuadre, hojas flotantes y fluidez (2026-07-15)

Auditoría estática de la capa SwiftUI Apple (`kmp/iosApp/App`, `kmp/iosApp/AppleShared`, `kmp/iosApp/MacApp`) complementaria al `plan_auditoria_ui_2026-07-15.md` (UI-1…UI-17, **ya en ejecución: no duplicar ni pisar esos ítems**). Este plan cubre tres ejes que aquel no trató:

1. **Encuadre**: contenido que desborda la pantalla o la ventana (frames fijos sin guarda de plataforma, hojas macOS más grandes que un portátil de 13").
2. **Tamaño de hojas y menús flotantes**: petición directa del usuario — las hojas de creación/edición (Nueva columna, medidas Nivel III, etc.) y los popovers deben ser más grandes para consultar la información con comodidad.
3. **Fluidez**: transiciones de módulo y estados de carga (parpadeo de estados vacíos, encadenamientos frágiles de hojas).

## Contexto técnico

- Deployment target: iOS 16.0 / macOS 26.0. `presentationSizing` (iOS 18+) debe ir tras `if #available(iOS 18.0, *)`.
- En macOS `presentationDetents` no aplica: cada sheet necesita `frame(minWidth:idealWidth:minHeight:idealHeight:)`; sin él, sale al tamaño mínimo del contenido.
- Referencia de pantalla pequeña macOS: MacBook Air 13" = **1280×832 pt** lógicos por defecto. Ninguna sheet debe exigir más que eso.
- La ventana principal macOS tiene `frame(minWidth: 900, minHeight: 600)` (`MiGestorKMPMacApp.swift:24`).
- Sistema de animaciones centralizado en `UiFeatureFlags` (`AppleShared/AppleAppEnvironment.swift:33-147`), con soporte de Reduce Motion. Usarlo siempre; no crear curvas ad-hoc nuevas.

## Reglas de trabajo para el agente

- Trabaja en la rama `fix/auditoria-ui-presentacion-2026-07` (ya creada en el worktree `.claude/worktrees/auditoria-ui-encuadre`).
- **Un commit atómico por ítem**, formato `fix(<ámbito>): <descripción>` (`fix(alumnado): ...`, `fix(cuaderno): ...`). Entrada en `docs/CHANGELOG.md` por fix, en español.
- Verificación mínima tras cada cambio: `xcodebuild -project kmp/iosApp/MiGestorKMPiOS.xcodeproj -scheme MiGestorKMPMac build` (y el scheme iOS cuando el cambio afecte a iOS). Hay fallos preexistentes de CI ajenos (PR #112, task_bff6235a/task_ec3ba015): compara contra el estado previo.
- No toques `KmpBridge.swift`, `kmp/shared/`, `kmp/data/`, `EvaluationDesign.swift` ni `desktopApp/`.
- **Coordinación con el plan UI-1…UI-17 en marcha**: UI-1 toca `WorkspaceCreationSheets.swift` y UI-8 toca las presentaciones de `StudentProfilesWorkspaceView.swift`/`CoursesWorkspaceView.swift`. Los ítems P1, P4 y P5 de este plan tocan zonas colindantes: rebasa sobre `main` cuando aterrice aquella rama antes de empezar esos tres ítems, y limita los cambios a los `frame`/detents (no a la lógica de guardado ni al mecanismo `.sheet(item:)` que introduce UI-8).
- Mensajes de UI siempre en español. Cambios quirúrgicos: no refactorices más allá de lo que pide cada ítem.

---

## Prioridad ALTA — Encuadre (desbordamientos reales)

### P1 — Hojas de medidas Nivel III/IV con `minWidth` fijo sin guarda de plataforma: desbordan en iPhone

**Archivos:**
- `kmp/iosApp/App/SupportMeasureBulkImportSheet.swift:56` — `.frame(minWidth: 620, idealWidth: 720, minHeight: 480, idealHeight: 680)` **sin `#if os(macOS)`**.
- `kmp/iosApp/App/SupportMeasureGroupOverviewSheet.swift:48` — `.frame(minWidth: 560, idealWidth: 680, minHeight: 480, idealHeight: 680)` **sin guarda**.

**Problema:** Ambas hojas se presentan desde `StudentProfilesWorkspaceView` (módulo Alumnado, alcanzable en iPhone y iPad) además de `MacStudentsView`. En iPhone (~390 pt de ancho) un `minWidth` de 560/620 fuerza el contenido más allá de los bordes del sheet: cabecera y filas cortadas, botones del pie parcialmente inaccesibles.

**Fix:** envolver el frame en `#if os(macOS)`; en la rama `#else`, `.frame(maxWidth: .infinity, maxHeight: .infinity)` + `.presentationDetents([.large])` + `.presentationDragIndicator(.visible)` (mismo patrón que `WorkspaceCreateSheetScaffold`, `WorkspaceCreationSheets.swift:255-261`).

**Criterio de aceptación:** en iPhone (simulador iPhone SE/15), abrir "Importar medidas Nivel III" y "Medidas del grupo" muestra todo el contenido dentro de pantalla, sin recorte horizontal. En macOS el tamaño no cambia.

### P2 — Hoja de columnas ocultas del Cuaderno y placeholders con frames sin guarda

**Archivo:** `kmp/iosApp/App/NotebookModuleDialogs.swift` (L281, L295, L302).

**Problema:** `NotebookHiddenColumnsSheet` se presenta con `.frame(minWidth: 420, minHeight: 360)` sin guarda de plataforma (L295), y los dos placeholders `NotebookContentUnavailableView` de respaldo llevan `.frame(minWidth: 420, minHeight: 260)` también sin guarda (L281, L302). En iPhone, 420 pt de `minWidth` supera el ancho del sheet y recorta los bordes. (El organizador de columnas en L268-275 sí está bien guardado: copiar ese patrón.)

**Fix:** replicar el bloque `#if os(macOS) frame / #else detents` del organizador (L268-275) en los tres puntos. `NotebookHiddenColumnsSheet` ya declara sus detents internos (`NotebookHiddenColumnsSheet.swift:62`), así que en la rama iOS basta `.frame(maxWidth: .infinity, maxHeight: .infinity)`.

**Criterio de aceptación:** "Columnas ocultas" en iPhone se ve completa; en macOS conserva 420×360 mínimos.

### P3 — Hojas de rúbricas en macOS más grandes que una pantalla de 13" e inconsistentes entre puntos de entrada

**Archivos:**
- `kmp/iosApp/MacApp/MacRubricsView.swift:291` — `RubricBulkEvaluationSheet` con `.frame(minWidth: 1320, minHeight: 860)`.
- `kmp/iosApp/App/NotebookModuleView.swift:1306` — la **misma** hoja con `.frame(width: 1180, height: 760)` (fija, no redimensionable).
- `kmp/iosApp/MacApp/MacRubricsView.swift:242`, `kmp/iosApp/MacApp/MacDashboardView.swift:1510` — `RubricsBuilderScreen` con `.frame(minWidth: 1200, minHeight: 820)`.

**Problema:** En un MacBook Air 13" (1280×832 pt) una sheet de 1320×860 mínimos **no cabe en la pantalla**: los bordes y los botones inferiores quedan fuera del área visible y no hay forma de encogerla. La builder (1200×820) roza el límite y con barra de menú tampoco cabe en alto. Además, la misma hoja de evaluación masiva tiene tres tamaños distintos según desde dónde se abra (1320×860, 1180×760 fija) — comportamiento errático para el usuario.

**Fix:**
1. Definir una única constante/`ViewModifier` (p. ej. en `MacAppStyle`) para cada hoja: evaluación masiva `min 960×620, ideal 1200×760`; builder de rúbricas `min 960×640, ideal 1180×760`. Sin `maxWidth/maxHeight` para que el usuario pueda agrandarla, y nunca `width/height` fijos.
2. Aplicarla en los tres puntos de entrada (y en cualquier otro `RubricsBuilderScreen`/`RubricBulkEvaluationSheet` presentado en macOS; hay otro builder en `MacDashboardView`).

**Criterio de aceptación:** en una ventana/pantalla de 1280×832, ambas hojas se abren completas, con los botones de acción visibles, y su tamaño es el mismo desde Rúbricas, Cuaderno y Dashboard.

---

## Prioridad ALTA — Hojas flotantes más grandes (comodidad de lectura)

### P4 — Scaffold común de hojas de creación en macOS: subir tamaños

**Archivo:** `kmp/iosApp/App/WorkspaceCreationSheets.swift:256` (`WorkspaceCreateSheetScaffold`).

**Problema:** `frame(minWidth: 560, idealWidth: 640, maxWidth: 720, minHeight: 520, idealHeight: 620)` se queda corto para hojas con varias tarjetas (`CreateEvaluationSheet`, `CreatePESessionSheet`, `SupportMeasureFormSheet` con su catálogo Nivel III de ~20 medidas en 4 grupos): obliga a hacer scroll constante y el `maxWidth: 720` impide aprovechar pantallas grandes.

**Fix:** subir a `minWidth: 640, idealWidth: 760, maxWidth: 900, minHeight: 600, idealHeight: 760`. Un solo cambio beneficia a todas las hojas de creación (curso, alumno, evaluación, sesión EF, prueba física, material y medida de apoyo).

**Criterio de aceptación:** en macOS, "Nueva medida de apoyo" muestra el grupo "Aprendizaje" completo del catálogo Nivel III sin scroll en el tamaño ideal; todas las hojas del scaffold siguen cabiendo en 1280×832.

### P5 — Medidas Nivel III y hojas de creación en iPad: usar hoja tipo página

**Archivos:** `kmp/iosApp/App/WorkspaceCreationSheets.swift:255-261` (scaffold, rama iOS) y presentaciones de `SupportMeasureFormSheet` en `kmp/iosApp/App/StudentProfilesWorkspaceView.swift:96-116`.

**Problema:** en iPadOS los `presentationDetents` se ignoran y el sheet sale como form-sheet estándar (~540 pt de ancho): el catálogo Nivel III y las hojas de creación quedan estrechos habiendo pantalla de sobra.

**Fix:** en la rama iOS del scaffold, añadir `if #available(iOS 18.0, *) { content.presentationSizing(.page) }` (con fallback sin cambios para iOS 16/17). No tocar la variante iPhone (los detents ya dan pantalla completa).

**Criterio de aceptación:** en iPad (iOS 18+), "Nueva medida de apoyo" y "Nueva evaluación" ocupan hoja tipo página (más ancha y alta que el form-sheet); en iPhone nada cambia.

### P6 — "Nueva columna" (Cuaderno) pequeña en macOS e iPad

**Archivo:** `kmp/iosApp/App/AddColumnSheet.swift:536` (macOS) y `:530-533` (iOS).

**Problema:** la hoja más usada del Cuaderno abre a 560×620 ideales con `maxWidth: 640` en macOS: la parrilla de tipos de columna, la sección de rúbricas con buscador y el pie caben apretados. En iPad, form-sheet estándar.

**Fix:** macOS → `minWidth: 600, idealWidth: 700, maxWidth: 840, minHeight: 620, idealHeight: 760`. iPad → mismo tratamiento `presentationSizing(.page)` de P5.

**Criterio de aceptación:** en macOS la sección de rúbricas muestra ≥4 filas sin scroll interno con el tamaño ideal; la hoja sigue cabiendo en 1280×832.

### P7 — Hojas del Cuaderno sin frame macOS o con tamaño fijo pequeño

**Archivos y estado actual:**
- `NotebookAICommentSheet` — **sin frame macOS** (call site `NotebookModuleView.swift:1242` → `notebookAISheet`, `NotebookModuleView.swift:1849-1860`): abre al tamaño mínimo del contenido.
- `NotebookAverageEditorSheet` — `frame(width: 560, height: 640)` fijo (`NotebookModuleView.swift:1262`): no redimensionable.
- `NotebookFormulaEditorSheet` — `frame(width: 660, height: 640)` fijo (`NotebookFormulaEditorSheet.swift:30`).
- `NotebookGroupManagementSheet` — `frame(minWidth: 550, minHeight: 480)` (`NotebookModuleView.swift:1293`), justo para su lista + editor.

**Fix (todo bajo `#if os(macOS)`):**
- AI comment: añadir `frame(minWidth: 640, idealWidth: 720, minHeight: 560, idealHeight: 680)`.
- Average editor: `frame(minWidth: 600, idealWidth: 680, minHeight: 600, idealHeight: 720)` (min/ideal, no fijo).
- Formula editor: `frame(minWidth: 660, idealWidth: 760, minHeight: 640, idealHeight: 720)` (min/ideal, no fijo).
- Group management: `minWidth: 620, minHeight: 560`.

**Criterio de aceptación:** las cuatro hojas abren con tamaño cómodo en macOS, son redimensionables por el usuario y ninguna exige más de 1280×832.

---

## Prioridad MEDIA — Menús flotantes y detents

### P8 — Popovers estrechos: selector de clase y explicación de media

**Archivos:**
- `kmp/iosApp/App/NotebookClassPickerComponents.swift:70-71` (`width: 250, maxHeight: 350`) y `:117-118` (`width: 230, maxHeight: 320`).
- `kmp/iosApp/App/NotebookModuleView.swift:1216` y `:1230` — popover de explicación de media con `frame(width: 360, height: 500)`.

**Problema:** el selector de clase trunca nombres de grupo largos ("1º ESO A — Educación Física") a 250/230 pt; la explicación de la media (desglose de columnas y pesos) obliga a scroll en 360×500 con listas de ≥8 columnas.

**Fix:** selector de clase → `width: 300, maxHeight: 420` (ambas variantes). Explicación de media → `width: 440, height: 560`. Comprobar que el popover sigue cabiendo bajo su ancla en un iPad apaisado (1024 pt de alto usable).

**Criterio de aceptación:** un nombre de grupo de 35 caracteres se lee sin truncar; la explicación de una media de 8 columnas se ve sin scroll o con scroll mínimo.

### P9 — Hojas iOS ancladas a `.medium` que se quedan cortas con el teclado

**Archivos:**
- `StudentProfilesWorkspaceView.swift:1044` (`StudentEditorSheet`).
- `PhysicalTestsWorkspaceView.swift:2115` (editor de pesos/baremo).
- `PlannerDayView.swift:570` (nota rápida del planner, con `isFocused = true` en `onAppear`: el teclado tapa media hoja).
- `TournamentModule.swift:67`.
- `ClassroomCaptureBar.swift:159`.

**Problema:** con detent único `.medium`, al aparecer el teclado la mitad inferior de la hoja queda oculta y no hay gesto para ampliar.

**Fix:** cambiar a `.presentationDetents([.medium, .large])` en los cinco puntos (el usuario decide; `.medium` sigue siendo el tamaño inicial).

**Criterio de aceptación:** en iPhone con teclado desplegado, cada una de estas hojas puede expandirse a `.large` arrastrando.

---

## Prioridad MEDIA — Fluidez de transiciones y carga

### P10 — Flash de estado vacío en Cursos al entrar al módulo

**Archivo:** `kmp/iosApp/App/CoursesWorkspaceView.swift:194` (+ `.task` en `:100-108`).

**Problema:** la lista de grupos muestra "No hay curso activo." / "Este curso escolar no tiene grupos." siempre que `bridge.classes.isEmpty`, sin distinguir "aún cargando" de "realmente vacío". Al entrar por primera vez al módulo (antes de que `ensureClassesLoaded()` termine) el usuario ve parpadear el mensaje de vacío aunque tenga cursos — carga "sucia".

**Fix:** `@State private var hasLoadedInitialData = false`, ponerlo a `true` al final del `.task`; mientras sea `false` y `bridge.classes.isEmpty`, mostrar `ProgressView()` en la sección en lugar del texto de vacío. **No tocar `KmpBridge.swift`** (regla de oro): resolver en la vista. Auditar el mismo patrón en los demás módulos que leen `bridge.classes.isEmpty` directamente en su primer render (búsqueda rápida: `grep -n "classes.isEmpty" kmp/iosApp/App/*.swift`) y aplicar el mismo gate donde ocurra en el primer frame.

**Criterio de aceptación:** entrar en Cursos recién abierta la app nunca muestra el texto de vacío si hay grupos; con BD realmente vacía el mensaje aparece tras la carga, sin parpadeo intermedio.

### P11 — Transición de módulo del iPhone fuera del sistema de animaciones

**Archivo:** `kmp/iosApp/App/IPadWorkspaceShell.swift:786-792` (`AppWorkspaceShell.body`).

**Problema:** el shell iPhone usa una transición ad-hoc (`.opacity` con curvas inline `easeOut 0.15`/`easeIn 0.10`) en lugar de `uiFeatureFlags.contentSwitchTransition` como iPad (`IOSRootView.swift:957`) y macOS (`MacRootView.swift:139/145`). No respeta Reduce Motion (curvas fijas) y el cambio de módulo se siente distinto entre plataformas.

**Fix:** sustituir por `.transition(uiFeatureFlags.contentSwitchTransition)` y envolver el cambio de `activeModule` en `withAnimation(uiFeatureFlags.animation(.easeOut(duration: 0.22)))` (mismo patrón que `IOSRootView.swift:218`). Requiere que `uiFeatureFlags` esté accesible en el shell (ya lo está vía environment).

**Criterio de aceptación:** cambiar de módulo en iPhone anima igual que en iPad; con Reduce Motion activo, cross-fade corto sin escala.

### P12 — Encadenamiento "cerrar hoja → abrir otra" con `DispatchQueue` en el organizador de columnas y evaluación masiva

**Archivos:**
- `kmp/iosApp/App/NotebookModuleDialogs.swift:195-266` — todos los callbacks del organizador (`onRename`, `onDelete`, `onDeleteMultiple`, `onAddColumn`, `onCreateCategory`, `onCreateTab`, `onCreateSummary`, `onOpenGroupManagement`) hacen `isOrganizationMenuPresented = false` + `DispatchQueue.main.async { presentar siguiente }`; `onGenerateSummary` usa `asyncAfter(0.2)` (L251).
- `kmp/iosApp/App/RubricBulkEvaluationSheet.swift:80` — `asyncAfter(0.35)`.

**Problema:** es la misma familia que UI-16 del plan anterior (allí solo se corrige el planner iOS): presentar una hoja mientras la anterior aún se descarta es poco fiable — en dispositivos lentos la segunda hoja no llega a presentarse y la acción se pierde en silencio. Los delays mágicos (0.2 s, 0.35 s) son carreras codificadas a mano. `MacRootView.presentPendingPlannerDiarySession` (~L245-260) documenta el patrón correcto: aparcar la acción pendiente en un `@State` y ejecutarla en el `onDismiss` del sheet.

**Fix:** añadir `@State private var pendingOrganizerAction: OrganizerFollowUp?` (enum con casos por acción), que cada callback rellene antes de cerrar; en el `onDismiss` del sheet del organizador, ejecutar y limpiar la acción pendiente. Aplicar el mismo tratamiento al `asyncAfter` de `RubricBulkEvaluationSheet`. No tocar los sitios ya cubiertos por UI-16.

**Criterio de aceptación:** desde el organizador, "Renombrar", "Eliminar", "Nueva columna", "Nueva categoría", "Nueva pestaña" y "Generar resumen" abren siempre su hoja destino (probar 10 veces seguidas en simulador con animaciones lentas activadas); no queda ningún `asyncAfter` de encadenamiento en esos dos archivos.

---

## Prioridad BAJA

### P13 — `WeightEditorSheet` es código muerto

**Archivo:** `kmp/iosApp/App/WeightEditorSheet.swift`.

Ningún punto del código lo presenta (verificado con grep sobre `kmp/iosApp`; el flujo real de pesos usa el editor de `PhysicalTestsWorkspaceView` y `NotebookAverageEditorSheet`). Verificar de nuevo antes de borrar (incluido el `project.pbxproj`) y eliminarlo.

### P14 — Focus del campo nombre en "Nueva columna" con delay mágico

**Archivo:** `kmp/iosApp/App/AddColumnSheet.swift:510-514`.

`DispatchQueue.main.asyncAfter(0.15) { isNameFocused = true }` — funciona, pero es frágil ante animaciones lentas. Sustituible por `.defaultFocus($isNameFocused, true)` (iOS 17+/macOS 14+) con fallback al hack actual en iOS 16. Solo si sobra tiempo; no es visible para el usuario cuando funciona.

---

## Orden de ejecución sugerido

| Fase | Ítems | Motivo |
|---|---|---|
| 1 | P1, P2 | Desbordamientos visibles en iPhone (peor encuadre) |
| 2 | P3 | macOS 13": hojas inutilizables, botones fuera de pantalla |
| 3 | P4, P6, P7 | Petición directa: hojas más grandes (scaffold primero, es 1 línea que beneficia a 7 hojas) |
| 4 | P5, P8, P9 | Comodidad iPad + popovers + detents |
| 5 | P10, P11, P12 | Fluidez de carga y transiciones |
| 6 | P13, P14 | Limpieza |

## Verificación global al cerrar

1. Compilan los schemes Mac e iOS sin errores nuevos respecto al estado previo.
2. Smoke test manual por plataforma:
   - iPhone: importación de medidas Nivel III y columnas ocultas del Cuaderno completamente encuadradas; hojas `.medium` ampliables a `.large`.
   - iPad: hojas de creación tipo página (iOS 18); transición de módulo animada y coherente.
   - macOS en ventana 1280×832: evaluación masiva de rúbricas y builder caben enteras; "Nueva columna", "Nueva medida de apoyo", editor de fórmulas y comentario IA abren con los tamaños nuevos y son redimensionables.
   - Entrar en Cursos tras arranque en frío: sin flash de "No hay curso activo.".
3. `registrar-avance-app` como capa final: changelog, evidencias y nota de PR.
