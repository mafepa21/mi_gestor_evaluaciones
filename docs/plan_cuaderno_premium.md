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

### 1.1 ⌘Z / Deshacer no funciona en macOS
- Síntoma: `keyboardShortcut("z", .command)` vive en el menú overflow que solo se monta con `toolbarMode == .shellOwned || .macWindowOwned` ([NotebookModuleView.swift:1269-1283](../kmp/iosApp/App/NotebookModuleView.swift)). En macOS el modo es `.macShellOwned` → el atajo no existe.
- Fix: exponer `undoLastCellChange()` (ya existe en [NotebookModuleSupportActions.swift:133](../kmp/iosApp/App/NotebookModuleSupportActions.swift)) a través de `NotebookMacToolbarActions` y registrarlo en `AppleAppCommands`/menú Edición con ⌘Z. Añadir stack de redo (`redoStack: [NotebookCellUndoEntry]`) y ⇧⌘Z simétrico.
- Ideal macOS: registrar cada edición en el `UndoManager` del entorno (`@Environment(\.undoManager)`) para que Edición → Deshacer del menú del sistema funcione con nombre de acción ("Deshacer nota de María").
- Aceptación: ⌘Z/⇧⌘Z funcionan en macOS e iPad con teclado; el menú Edición del sistema muestra la acción.

### 1.2 Feedback de guardado honesto
- Síntoma: `markSaveInProgress()` ([NotebookEditableTableCell.swift:1515](../kmp/iosApp/App/NotebookEditableTableCell.swift)) simula el ciclo saving→saved con `Task.sleep`, ignorando el resultado real. Un guardado fallido muestra "Sincronizado".
- Fix: observar `notebookStore.notebookSplitSaveState` (ya existe; se usa en la barra de estado) filtrado por celda/fila, o hacer que `NotebookCellActions.saveColumnGrade*` devuelvan resultado y actualicen `saveFeedback`. Añadir estado `.error` con borde rojo + reintento en el toast.
- Aceptación: desconectar la persistencia (o forzar error en DEBUG) muestra estado de error, nunca "Sincronizado".

### 1.3 Drag numérico vs selección de texto (macOS)
- Síntoma: en celdas numéricas con `keyboardKind == .text`, `simultaneousGesture(numericDragGesture)` ([NotebookEditableTableCell.swift:846](../kmp/iosApp/App/NotebookEditableTableCell.swift)) convierte el arrastre de selección de texto en cambio de valor.
- Fix: compilar el gesto solo en iOS/iPadOS (`#if !os(macOS)`); en macOS ofrecer ↑/↓ (Fase 3.2) y scroll-wheel opcional.
- Aceptación: en macOS se puede seleccionar texto arrastrando sin alterar el valor.

### 1.4 Cursor de resize que se queda pegado (macOS)
- Síntoma: `NotebookResizeCursorModifier` hace `NSCursor.push()/pop()` desbalanceado si la vista desaparece con hover activo ([NotebookDataGrid.swift:202-216](../kmp/iosApp/App/NotebookDataGrid.swift)).
- Fix: guardar flag `didPush` en `@State` y hacer `pop()` en `onDisappear`; o migrar a `.pointerStyle(.frameResize(...))`/`.cursor` moderno si el target lo permite.
- Aceptación: alternar módulos/hojas con el puntero sobre el divisor nunca deja el cursor de resize activo.

### 1.5 N+1 en situaciones de aprendizaje
- Síntoma: `loadClassLearningSituations` ([NotebookModuleView.swift:617-636](../kmp/iosApp/App/NotebookModuleView.swift)) hace un await secuencial de `learningSituationClassLinks(id:)` por cada situación y silencia errores.
- Fix: paralelizar con `withThrowingTaskGroup` (sigue sin tocar KMP) y loggear el error una vez. Si existe un método bridge que filtre por clase, usarlo.
- Aceptación: con 20 situaciones, el filtro se puebla en una fracción del tiempo actual; sin freezes al entrar al Cuaderno.

### 1.6 Estado vacío que oculta la estructura
- Síntoma: si `rows.isEmpty` (búsqueda/filtro sin resultados), `NotebookGridContainer` sustituye TODO el grid (cabeceras incluidas) por el empty state ([NotebookGridContainer.swift:38-40](../kmp/iosApp/App/NotebookGridContainer.swift)).
- Fix: distinguir "clase sin alumnos" (empty state completo con CTA "Añadir alumnado") de "filtro sin resultados" (mantener cabeceras + mensaje inline con botón "Limpiar filtros").
- Aceptación: al buscar algo inexistente no desaparecen las columnas; hay salida de un toque.

### 1.7 Divergencia de menús triplicados
- Síntoma: filtros/pestañas/vista implementados 3 veces (barra compacta, overflow, `toolbarTitleMenu`) con literales distintos ("Sin filtrar" vs "Sin filtrar (Ver todas)").
- Fix: extraer `NotebookFilterMenu`, `NotebookTabsMenu`, `NotebookViewMenu` como Views reutilizables en `NotebookTopBar.swift` o archivo nuevo `NotebookSharedMenus.swift`, parametrizadas por callbacks ya existentes. Sin cambiar ownership (ver skill `notebook-toolbar-ownership`).
- Aceptación: un único punto de verdad por menú; textos idénticos en iPad y macOS.

---

## Fase 2 — Fluidez del grid (3–4 días)

### 2.1 Hover de fila sin invalidar los 3 paneles (macOS) — impacto alto
- Síntoma: `@State hoveredRowId` en `NotebookGridContainer` + `withAnimation` en cada `onHover` ([NotebookGridContainer.swift:35,86-91](../kmp/iosApp/App/NotebookGridContainer.swift)) invalida los tres `rowStack` completos por cada fila que cruza el puntero.
- Fix (siguiendo la skill: reducir alcance de invalidación):
  - Mover el hover a una subview por fila (`NotebookHoverableRow`) con su propio `@State private var isHovered`, de modo que solo la fila afectada repinte su background. Para mantener el hover coherente entre paneles, publicar el id en un `ObservableObject` ligero (`NotebookRowHoverModel`) observado solo por esas subviews, no por el contenedor.
  - Quitar `withAnimation`: usar `.animation(.easeOut(duration: 0.12), value: isHovered)` local o ninguna animación (nativo Apple: el hover de NSTableView no anima).
- Aceptación: en Instruments, mover el ratón por 40 filas no re-evalúa `rowStack`; solo 2 filas (la que entra y la que sale) × 3 paneles.

### 2.2 Sincronización de scroll sin lag de frame
- Síntoma: paneles sincronizados por delegado (`scrollViewDidScroll` → `setContentOffset` en los otros) ([NotebookDataGrid.swift:86-148](../kmp/iosApp/App/NotebookDataGrid.swift)); en flicks rápidos la zona fija va 1 frame por detrás; en macOS elástico/momentum pueden divergir.
- Fix recomendado (iOS/iPadOS): dejar UN solo `UIScrollView` vertical dueño del gesto (el central) y desactivar `isScrollEnabled` en los laterales, moviéndolos solo por sync (elimina gestos en conflicto). En macOS, replicar bounds directamente en `reflectScrolledClipView` ya es síncrono; verificar que el elástico (`elasticity`) esté desactivado en los paneles esclavos para que no reboten por su cuenta.
- Alternativa mayor (evaluar solo si 2.3 falla): un único scroll vertical que contenga una fila compuesta [fija | centro | Media], con scroll horizontal solo en el segmento central. Cambia la arquitectura; requiere validar el checklist completo de alineación.
- Aceptación: checklist punto 5 de `NotebookManualVerification.md` sin jumps con 40 alumnos; grabación a 120 Hz sin desalineación visible.

### 2.3 Verificar/recuperar virtualización de filas
- Según resultado de Fase 0: si `LazyVStack` no virtualiza dentro del scroll hosteado, la opción quirúrgica es exponer el viewport al `LazyVStack` envolviendo el contenido hosteado en un `ScrollView` SwiftUI interno desactivado de gesto… (frágil). La opción robusta y nativa: sustituir los `rowStack` por `List`/`NSTableView` no es viable sin romper la alineación de 3 paneles. Camino recomendado: ventana manual de filas (render solo `visibleRange ± buffer` calculado desde el offset que ya recibe `NotebookScrollSyncCoordinator`, con spacers arriba/abajo de altura `rowHeight × count`). La altura de fila ya es fija y estable, lo que hace este cálculo trivial y sin saltos.
- Aceptación: con 40 alumnos, ≤ ~20 filas materializadas por panel; memoria y tiempo de aparición de clase reducidos; scroll sin huecos blancos.

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
