# Plan: Cuaderno de Notas fluido, funcional y premium (macOS + iPadOS)

Fecha: 2026-07-03. Ámbito: `kmp/iosApp/App/Notebook*.swift`, `kmp/iosApp/MacApp/NotebookMacLayout.swift`, `kmp/iosApp/MacApp/MacRootView.swift` (toolbar). No tocar `KmpBridge.swift`, `kmp/shared/`, `kmp/data/` salvo lo indicado.

Skills aplicables: `notebook-grid-performance` (fases 1–2), `notebook-toolbar-ownership` (fase 4.4), `swiftui-polish` (fase 4), `registrar-avance-app` al cierre de cada fase.

## Diagnóstico resumido

El grid usa una arquitectura de 3 paneles (zona fija izquierda, centro scrollable, Media fija derecha) con scroll vertical sincronizado vía `UIScrollView`/`NSScrollView` hosteados (`NotebookDataGrid.swift`) y filas `Equatable` con fingerprint por panel (`NotebookGridContent.swift`). La base es sólida, pero:

- `NotebookModuleView.swift` es una God View de ~2.150 líneas con ~100 `@State`: cualquier cambio de estado caliente invalida todo el `body`.
- El hover de fila vive en `NotebookGridContainer` (ancestro de los 3 paneles) y se anima con `withAnimation`: mover el ratón invalida los 3 stacks completos en macOS.
- La sincronización de scroll por delegado tiene lag de 1 frame entre paneles en scroll rápido/momentum.
- ⌘Z solo está cableado en un menú que no se renderiza en macOS (`toolbarMode == .macShellOwned`); no hay redo ni integración con `UndoManager`.
- La edición numérica en macOS pasa por popover-teclado táctil; no hay navegación con flechas ni escritura directa estilo hoja de cálculo.
- El feedback "Guardando → Sincronizado" de celda es un temporizador fijo (700 ms + 1,4 s) que no refleja el guardado real: un fallo también muestra "Sincronizado".
- El contenido de menús (filtros, pestañas, vista) está triplicado entre barra compacta, overflow y `toolbarTitleMenu`, con textos ya divergentes.
- Accesibilidad casi ausente en celdas (2–3 `accessibilityLabel` en ~2.800 líneas de celdas).

---

## Fase 0 — Instrumentación y línea base (0,5 día)

Objetivo: medir antes de optimizar.

1. **Contador de virtualización de filas — hecho.** `NotebookRowVirtualizationDebug` en [NotebookGridContainer.swift](../kmp/iosApp/App/NotebookGridContainer.swift) registra `onAppear`/`onDisappear` por fila y panel (fixed/trailing/scroll), y loggea cada 0,5 s `materialized=X totalRows=Y` en consola cuando `enabled = true`. Sintaxis verificada con `swiftc -parse`; **pendiente compilar el target completo y ejecutar en dispositivo/simulador real** (este entorno solo tiene Command Line Tools, sin Xcode.app, así que no se pudo lanzar la app ni Instruments desde aquí).
   - Procedimiento de uso documentado en `NotebookManualVerification.md` punto 9.
   - Si `materialized` crece hasta igualar `totalRows` y no baja al hacer scroll, la Fase 2.3 (ventana manual de filas) deja de ser opcional y pasa a alta prioridad.
2. **Medición con Instruments** (SwiftUI template) de las interacciones del checklist de `NotebookManualVerification.md` — scroll rápido, hover, colapsar categoría, resize de divisor, editar celda: **pendiente, requiere Xcode.app y dispositivo/simulador; a ejecutar por el dev antes de Fase 2.**
3. **Dataset de prueba**: clase con 35 alumnos y 25+ columnas en 3 categorías, en iPad real y Mac — crear manualmente en la app antes de medir.

Criterio de salida: tabla con nº de invalidaciones por interacción y confirmación/refutación de la virtualización (a rellenar por el dev con los datos de consola/Instruments).

---

## Fase 1 — Bugs y correcciones de fiabilidad (2–3 días)

Estado: 1.1–1.6 implementados y verificados con `swiftc -parse` en el worktree `notebook-premium-plan`; **pendiente compilar el target completo y probar en dispositivo real** (sin Xcode.app en este entorno). 1.7 queda pendiente de decisión de alcance (ver abajo).

### Hallazgo que corrige el diagnóstico original
Al implementar 1.1 se descubrió que `kmp/iosApp/App/IPadWorkspaceShell.swift` es **código muerto**: el `struct IPadWorkspaceShell` no se instancia en ningún sitio del proyecto (solo aparece en `project.pbxproj`). El root real de iPad/iPhone es `IOSRootView.swift`. Consecuencia verificada: los atajos del `CommandMenu("Cuaderno")` en `AppleAppCommands.swift` (añadir columna ⌘⇧C, buscar ⌘F, columnas ocultas ⇧⌘H, reordenar ⌥⌘R) están declarados y aparecen en la chuleta de atajos de iPad con teclado externo, pero **no tienen receptor vivo en iPad** — son no-ops. Solo `MacRootView.swift` los recibe. Esto es más amplio que el bug puntual de 1.1 y se ha dejado fuera de esta fase (ver tarea de fondo más abajo); 1.1 se resolvió cableando Undo/Redo directamente en el root vivo (`IOSRootView.swift`), no en el archivo muerto.

### 1.1 ⌘Z / Deshacer no funciona de forma fiable — hecho
- Síntoma real (revisado): en macOS existía un botón "Deshacer" con `.keyboardShortcut("z", .command)` dentro de un `Menu` de toolbar (`macNotebookOverflowMenu`), pero sin redo, sin integración con el menú Edición del sistema, y en riesgo de perder el atajo cuando el foco está en el campo de búsqueda de la toolbar.
- Fix aplicado: notificaciones `.appleAppUndoNotebookRequested`/`.appleAppRedoNotebookRequested` en `AppleAppCommands.swift` (⌘Z/⇧⌘Z, visibles en el menú "Cuaderno" de la barra de menús); receptores en `MacRootView.swift` (con banner si el Cuaderno no está activo) y en `IOSRootView.swift` (guardado silencioso si el módulo activo no es Cuaderno). Pila `redoStack` simétrica a `undoStack` en `NotebookModuleView`/`NotebookModuleSupportActions.swift`, capturando el valor "actual" de la celda antes de restaurar para poder deshacer el deshecho. Wiring de `canRedo`/`onRedo` añadido a `NotebookMacToolbarActions` y `WorkspaceLayoutState` en paralelo a los `canUndo`/`onUndo` ya existentes. Botón "Rehacer" añadido junto a "Deshacer" en el overflow de macOS (`MacRootView.swift`) y en el menú "Más" de iPad (`IOSRootView.swift`).
- Pendiente (fuera de esta fase): integración con `UndoManager` del entorno para que el menú Edición nativo del sistema (no un menú "Cuaderno" propio) muestre "Deshacer cambio" — requiere decidir si vale la pena por el beneficio marginal frente a la solución actual, que ya es descubrible y funcional.
- Archivos: `AppleAppCommands.swift`, `MacRootView.swift`, `IOSRootView.swift`, `IPadWorkspaceShell.swift` (solo la clase `WorkspaceLayoutState`, viva aunque el archivo tenga la View muerta), `NotebookMacToolbarBinding.swift`, `NotebookModuleToolbarState.swift`, `NotebookModuleSupportActions.swift`, `NotebookModuleView.swift`.

### 1.2 Feedback de guardado honesto — hecho parcialmente
- Hallazgo: `kmp/shared` (`NotebookSaveState`) no expone ningún canal de error/fallo, ni por celda ni global — solo `isDirty`/`isSaving`/`isSaved`. Añadir detección real de fallos de guardado requeriría tocar `kmp/shared/NotebookViewModel`/`NotebookSaveQueue`, fuera del alcance por defecto (`AGENTS.md`) sin petición explícita.
- Fix aplicado (sin tocar KMP): `markSaveInProgress` en `NotebookEditableTableCell.swift` ahora distingue guardado inmediato de guardado debounced. Para guardado inmediato (check, ordinal, asistencia, blur/navegación) salta directo a "Sincronizado" sin fase "Guardando" falsa, porque no hay ventana de espera real. Para guardado debounced (texto/numérico mientras se escribe) la fase "Guardando" dura 500 ms, coincidiendo con el debounce real de `NotebookViewModel.saveColumnGrade` en `kmp/shared` (antes eran 700 ms + 1,4 s sin relación con nada real).
- Pendiente (decisión del usuario): si se quiere detección real de fallo de guardado, hay que autorizar tocar `kmp/shared/NotebookSaveQueue.kt`/`NotebookViewModel.kt` para añadir un canal de resultado/error.
- Archivo: `NotebookEditableTableCell.swift`.

### 1.3 Drag numérico vs selección de texto (macOS) — hecho
- Fix: `simultaneousGesture(numericDragGesture)` ahora solo se compila con `#if canImport(UIKit)`, igual que el resto de código touch-only del mismo archivo. En macOS el campo numérico se comporta como un `TextField` normal (selección de texto con el ratón funciona).
- Archivo: `NotebookEditableTableCell.swift`.

### 1.4 Cursor de resize que se queda pegado (macOS) — hecho
- Fix: `NotebookResizeCursorModifier` guarda `@State private var isCursorPushed` y solo hace `push()`/`pop()` de forma balanceada; añadido `.onDisappear` que hace `pop()` si la vista desaparece con el cursor empujado.
- Archivo: `NotebookDataGrid.swift`.

### 1.5 N+1 en situaciones de aprendizaje — hecho
- Fix: `loadClassLearningSituations` usa `withTaskGroup` para pedir en paralelo `learningSituationClassLinks(id:)` de todas las situaciones, preservando el orden original y sin abortar el resto si una falla. No se tocó `KmpBridge.swift` (no existe método bridge filtrado por clase).
- Archivo: `NotebookModuleView.swift`.

### 1.6 Estado vacío que oculta la estructura — hecho
- Fix: `NotebookGridContainer`/`NotebookGridContent` reciben `hasUnfilteredRows: Bool` y un nuevo closure `filteredEmptyContent`. Si la clase tiene alumnado pero el filtro/búsqueda deja 0 filas, el grid conserva cabecera y carriles de categoría, y muestra una `NotebookStateCard` con botón "Limpiar filtros" (`clearNotebookFilters()`, nuevo helper en `NotebookModuleDataState.swift`) en el área central. Si la clase no tiene alumnado real, se mantiene el estado vacío de pantalla completa (texto actualizado para no sugerir "ajustar filtros" en ese caso).
- Archivos: `NotebookGridContainer.swift`, `NotebookGridContent.swift`, `NotebookModuleView.swift`, `NotebookModuleDataState.swift`.

### 1.7 Divergencia de menús triplicados — hecho (alcance acotado tras investigar)
- Diagnóstico original (incompleto): asumía triplicación dentro de `NotebookModuleView.swift` con literales ya divergentes en 3 copias del mismo archivo.
- Diagnóstico real tras investigar a fondo: la duplicación con **texto realmente divergente y visible simultáneamente** estaba acotada a **un solo archivo**, `NotebookModuleView.swift`, entre dos implementaciones ambas vivas:
  - `notebookFilterMenuContent(data:)` — usada por `NotebookCompactCommandBar` en modo `.inlineCompact` (iPhone/iPad compacto).
  - `.toolbarTitleMenu` — menú nativo del título de navegación, vivo en `.inlineCompact` **y** `.macShellOwned` (macOS + iPad regular), por lo que en `.inlineCompact` ambos son accesibles al mismo tiempo.
  - Divergencias confirmadas y corregidas: "Sin filtrar" vs "Sin filtrar (Ver todas)" para limpiar el filtro de situación de aprendizaje; "Grid"/`"rectangle.3.group"` vs `NotebookSurfaceMode.title`/`.systemImage` ("Rejilla"/`"tablecells"`) para el selector Grid/Plano, con icono de Plano también distinto (`rectangle.3.group` vs `square.grid.3x3.square`).
  - Otras piezas que parecían duplicadas resultaron ser código muerto (el bloque de toolbar `.shellOwned`/`.macWindowOwned`, nunca montado) o afordancias legítimamente distintas y no conflictivas: el selector rápido de grupo de `IOSRootView.swift` (`notebookGroupFilterMenu`, con texto ya idéntico) complementa al `toolbarTitleMenu` en iPad sin contradecirlo, y macOS no tenía (ni tiene) filtro de grupo/situación expuesto en su propio toolbar — un hueco funcional distinto a "duplicación", fuera del alcance de este fix de consistencia de texto.
- Fix aplicado: se añadieron `notebookClearGroupFilterTitle`/`notebookClearSituationFilterTitle` como fuente única de verdad en `NotebookModuleView.swift`, usadas por `notebookFilterMenuContent`, `.toolbarTitleMenu`, `notebookNavigationSubtitle` y `headerContextLine` (en `NotebookModuleToolbarState.swift`). El menú "Vista" de `notebookCommandMenuContent` pasa a iterar `NotebookSurfaceMode.allCases` con `.title`/`.systemImage` en vez de literales propios, preservando el `.disabled` de Plano en modo no-normal.
- Archivos: `NotebookModuleView.swift`, `NotebookModuleToolbarState.swift`.
- Pendiente (fuera de esta pasada, no crítico): exponer filtro de grupo/situación en el toolbar nativo de macOS (`MacRootView.swift`) si se decide que es una carencia real, y decidir si el archivo muerto `IPadWorkspaceShell.swift`/atajos rotos en iPad (ver tarea de fondo `task_3d14f1b3`) se limpian del todo.

---

## Fase 2 — Fluidez del grid (3–4 días)

### 2.1 Hover de fila sin invalidar los 3 paneles (macOS) — hecho
- Fix aplicado: `NotebookGridContainer` sustituye el `@State hoveredRowId` compartido por `@StateObject private var hoverModel = NotebookRowHoverModel()` (un `ObservableObject` con un único `@Published var hoveredRowId: AnyHashable?`). El contenedor nunca lee `hoverModel.hoveredRowId` en su propio `body` — solo pasa la referencia hacia abajo — así que un cambio de hover ya no invalida `NotebookGridContainer.body` ni reconstruye los 3 `rowStack`.
- La lógica de fondo/overlay/`.onHover` se movió a una vista hoja nueva, `NotebookHoverableRow`, que observa `hoverModel` con `@ObservedObject` y calcula `isHovered` comparando su propio `rowId`. Solo esa fila (y, como mucho, la fila que pierde el hover) se reevalúa por transición.
- Se sustituyó `withAnimation` (que forzaba una transacción de animación sobre todo lo que dependiera del `@State` del contenedor) por `.animation(.easeOut(duration: 0.12), value: isHovered)` local a la fila hoja.
- Archivo: `NotebookGridContainer.swift`. Verificado con `swiftc -parse`; **medición real en Instruments pendiente** (requiere Xcode.app/dispositivo, no disponible en este entorno).

### 2.2 Sincronización de scroll sin lag de frame — parcialmente hecho
- Fix aplicado (bajo riesgo, sin cambiar el modelo de interacción): los paneles fijos (izquierdo y Media) desactivan su propio rebote elástico (`UIScrollView.bounces = false` / `NSScrollView.verticalScrollElasticity = .none`) ya que solo deben reflejar el offset del panel central sincronizado; antes podían rebotar de forma independiente en un overscroll y desincronizarse visualmente durante ese instante.
- **No aplicado — requiere decisión de UX + medición en dispositivo**: el cambio arquitectónico mayor (dejar el panel central como único dueño del gesto, con `isScrollEnabled = false` en los paneles fijos) mejoraría la robustez (elimina cualquier posibilidad de que 3 reconocedores de gesto compitan) pero también **elimina la posibilidad de arrastrar verticalmente tocando directamente la columna de alumnado o la columna Media** — hoy sí se puede. Es un trade-off de producto, no un bug puro, y no se puede validar "se siente mejor/peor" sin dispositivo real. Revisado el código de sincronización (`NotebookScrollSyncCoordinator`, callbacks `scrollViewDidScroll`/`boundsDidChangeNotification`): ambos casos actualizan `contentOffset` de forma síncrona dentro del mismo callback, sin despacho asíncrono visible — no se encontró una causa de "lag de 1 frame" verificable por lectura de código; la sospecha original era una hipótesis, no un diagnóstico confirmado.
- Aceptación pendiente: medir con Instruments (grabación a 120 Hz) si existe desalineación real antes de decidir si vale la pena sacrificar la interacción directa con las columnas fijas.
- Archivo: `NotebookDataGrid.swift`.

### 2.3 Verificar/recuperar virtualización de filas — bloqueado en medición de Fase 0
- No se ha tocado código de virtualización en esta pasada: la instrumentación de la Fase 0 (`NotebookRowVirtualizationDebug`) sigue siendo el paso previo obligatorio. Sin poder ejecutar en un Mac con Xcode/dispositivo desde este entorno, no hay evidencia de que la virtualización esté realmente rota — solo la sospecha original. Implementar la ventana manual de filas sin esa evidencia sería optimizar a ciegas, justo lo que la skill `notebook-grid-performance` pide evitar.
- Acción: el dev debe correr el checklist punto 9 de `NotebookManualVerification.md` primero. Si `materialized` no se acota, retomar este punto con la ventana manual de filas ya descrita.

### 2.4 Trocear `NotebookModuleView`
- Continuar la partición ya empezada (`NotebookModuleToolbarState`, `NotebookGridLayoutModel`): mover a stores observables el estado caliente que aún vive en la View: `undoStack`, `todayAttendanceByStudentId`, `incidentCountByStudentId`, `riskLevelCache`, `rowReloadRevisions`, `seatPositions`. Regla: ningún estado que cambie durante scroll/edición debe invalidar el `body` raíz.
- Hacerlo en PRs pequeños (1 store por PR), sin cambiar comportamiento.
- Aceptación: editar una celda no re-evalúa `centerPanel` completo (verificable con `Self._printChanges()` temporal).

---

## Fase 3 — Funcionalidad de edición estilo hoja de cálculo (3–4 días)

### 3.1 Navegación completa por teclado
- Hoy: solo Return/Tab → "siguiente" en una dirección ([NotebookViewModifiers.swift:19-38](../kmp/iosApp/App/NotebookViewModifiers.swift)).
- Añadir en macOS + iPad con teclado:
  - Flechas ←→↑↓ mueven la selección de celda (sin entrar en edición).
  - Return: entra en edición; Return de nuevo: guarda y baja. Tab/⇧Tab: guarda y derecha/izquierda.
  - Esc: cancela edición y restaura draft original (hoy no existe cancelación).
  - Escribir directamente sobre celda seleccionada empieza edición reemplazando el valor (type-to-edit).
- Implementación: `onKeyPress` en el contenedor del grid usando `navigateFromFocused` ya existente + un `selectedCellCoordinate` en `NotebookGridLayoutModel`; los popover-keyboards táctiles quedan solo para touch.
- Aceptación: se puede rellenar una columna entera de 30 notas sin tocar el ratón/trackpad.

### 3.2 Edición numérica nativa en macOS
- Sustituir el botón-popover de teclado táctil (numeric010/time/distance/repetitions) por `TextField` directo con validación en macOS; mantener popovers en iOS/iPadOS touch. Stepper con ↑/↓ (+0,1/−0,1) como reemplazo del drag eliminado en 1.3.
- Aceptación: clic (o Return) → cursor en el campo → teclear "7,5" → Return guarda y avanza.

### 3.3 Selección de rango y relleno
- Hoy "Rellenar" muestra un toast "Selecciona un rango…" pero no hay selección de rango.
- MVP: ⇧clic (o arrastre en touch) extiende selección vertical dentro de una columna; acciones Copiar/Pegar/Borrar/Rellenar operan sobre el rango; pegar multilinea desde portapapeles (una nota por fila) — flujo típico "pego columna desde Numbers/Excel".
- Estado en `NotebookGridLayoutModel` (`selectedRange: ClosedRange<Int>?` + columnId); guardado reutiliza `saveColumnGrade` por fila + un solo `reloadNotebookRow` por alumno.
- Aceptación: pegar 30 valores desde Numbers rellena 30 celdas con undo agrupado (una entrada de undo para todo el pegado).

### 3.4 Export con formato
- `exportText(data:)` exporta texto plano vía ShareLink. Añadir export CSV real (separador `;`, decimales con coma, BOM UTF-8 para Excel) y en macOS `NSSavePanel` con nombre `Cuaderno-<clase>-<fecha>.csv`.
- Aceptación: el CSV abre correcto en Numbers y Excel con acentos y decimales.

---

## Fase 4 — Aspecto premium Apple-like (2–3 días)

Guía: `GUIA_DISENO_DESKTOP.md`, `docs/apple-ui-guidelines.md`, filosofía `jobs-design-philosophy` (rejilla 8pt, un foco por pantalla, quitar ruido).

### 4.1 Celdas
- Quitar `RoundedBorderTextFieldStyle` dentro de celdas (doble borde caja-en-caja, aspecto AppKit legacy): usar `.textFieldStyle(.plain)` con el fondo/borde que ya pinta la propia celda.
- Revisar jerarquía de rellenos: hoy cada celda tiene fill+borde 12pt propios → aspecto "muro de píldoras". Propuesta más nativa: celdas planas separadas por gridlines sutiles; el chip redondeado solo para la celda seleccionada/foco y estados (pendiente/error). Prototipar tras aprobación de diseño; medir con Test del Bizqueo.
- Unificar tipografía numérica: `monospacedDigit()` en TODA celda numérica y en Media (ya está en varias; auditar).

### 4.2 Micro-interacciones
- Selección de celda: transición de borde con `.animation(.snappy(duration: 0.15))` solo sobre `isSelected`.
- Guardado: reemplazar los 3 badges de estado por un único indicador discreto en la esquina (punto ámbar → check verde con `symbolEffect(.bounce)` una vez), y el estado global ya existente en la barra de estado.
- Colapso de categoría: mantener sin animación estructural (regla de la skill), pero animar el chevron/chip del folder (rotación 90°, 0,2 s) para dar feedback sin repintar el grid.

### 4.3 Materiales y profundidad (macOS 26 Liquid Glass)
- Mantener el grid denso FUERA de `glassEffect` (decisión ya tomada, correcta).
- Aplicar glass solo al chrome: barra de pestañas del cuaderno, inspector (ya usa `.ultraThinMaterial`) y folder lane. Reutilizar los roles de `MacLiquidGlassStyle.swift` para consistencia con Planner (trabajo reciente en `PlannerLiquidGlassControls.swift`).
- Sombra de zona fija: bajar aún más en macOS (0.035 ya es sutil; validar en dark mode que no desaparezca — usar `Color.primary.opacity` en vez de `Color.black` para que funcione en oscuro).

### 4.4 Toolbar y barra de estado
- macOS: la barra de estado (guardado/sync/nº alumnos) hoy solo existe en el modo iPad (`.status` placement en toolbar shellOwned). Añadirla en macOS como pie discreto del grid o `ToolbarItem` de ventana, una sola fuente (reutilizar el componente, no duplicar).
- Revisar con el checklist de `notebook-toolbar-ownership`: una sola toolbar activa, sin duplicados, acciones críticas accesibles.

### 4.5 Inspector
- Ancho fijo 360 en iPad: convertir a `inspector(isPresented:)` nativo de SwiftUI (iOS 17+/macOS 14+) donde el shell lo permita, con redimensionado nativo en macOS (`inspectorColumnWidth`).
- Aceptación fase 4: sesión de revisión visual con capturas antes/después en light/dark, iPad 11" y Mac 14"; pasa Test del Aire y del Bizqueo.

---

## Fase 5 — Accesibilidad (1–2 días)

- Celdas: `accessibilityLabel("\(alumno), \(columna)")` + `accessibilityValue(valor)` + `accessibilityHint` según tipo; agrupar fila con `accessibilityElement(children: .contain)` y label del alumno.
- Cabeceras: rasgo `.isHeader`.
- Orden de foco VoiceOver por fila (alumno → celdas → media).
- Dynamic Type: auditar los `font(.system(size: 13...))` fijos de celdas → migrar a `.footnote`/`.callout` con `minimumScaleFactor` donde el alto de fila lo limite.
- Aceptación: con VoiceOver se puede oír "María García, Examen tema 3, 7 coma 5" y editar una celda; con AX2 el grid sigue usable.

---

## Orden recomendado y estimación

| Orden | Fase | Días | Riesgo |
|---|---|---|---|
| 1 | F0 Instrumentación | 0,5 | Nulo |
| 2 | F1 Bugs (1.1–1.7) | 2–3 | Bajo |
| 3 | F2 Fluidez (2.1 → 2.2 → 2.4 → 2.3) | 3–4 | Medio |
| 4 | F3 Teclado/edición | 3–4 | Medio |
| 5 | F4 Premium visual | 2–3 | Bajo |
| 6 | F5 Accesibilidad | 1–2 | Bajo |

Reglas de entrega: 1 PR por ítem numerado (1.1, 2.1…), cada PR pasa el checklist de `NotebookManualVerification.md` en iPad y macOS, y se registra con `registrar-avance-app`. No mezclar rendimiento con rediseño visual en el mismo PR (regla de la skill `notebook-grid-performance`).
