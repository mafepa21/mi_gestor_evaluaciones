# Plan: Planner de 10 — intuitivo, práctico y premium (iPadOS + macOS)

Fecha: 2026-07-03. Ámbito: `kmp/iosApp/App/Planner*.swift`, `kmp/iosApp/MacApp/MacModuleStubs.swift` (MacPlannerView), `kmp/iosApp/AppleShared/PlannerLiquidGlassControls.swift`. Cambios en `kmp/shared/` solo donde se indica (periodos de evaluación, export).

Objetivo de producto: el Planner es la pantalla donde el docente **organiza las clases a futuro** y a la vez **justifica todo lo realizado**. Tiene que ser intuitivo, práctico en el día a día, aportar valor real y tener acabado premium.

## Diagnóstico resumido

La base funcional es buena: 4 secciones (Semana con grid miniatura + panel de detalle, Día, Secuencia tipo Gantt, Resumen con métricas y alertas), movimiento en cascada con deshacer, generación desde agenda, selección múltiple y diario integrado. Pero hay problemas estructurales, de interacción y de valor:

**Arquitectura**
- `PlannerWorkspaceIOS.swift` es una God File de ~5.900 líneas; `PlannerWorkspaceViewModel` tiene ~50 `@Published` en un único objeto: cualquier cambio (buscar, seleccionar, tick de guardado) invalida todas las vistas suscritas.
- La versión Mac vive en `MacModuleStubs.swift` ("stubs") y contiene **código muerto**: `plannerSidebar` y `plannerHeader` (con los chevrons de semana anterior/siguiente, "Deshacer movimiento", filtros y acciones) están definidos pero **no se renderizan** — el `body` solo monta `PlannerToolbar` (el de iOS) + contenido central. El `@State activeSection` local tampoco se usa (el switch lee `vm.activeSection`).
- Duplicaciones: `hasSessionPassed` copiado en iOS y Mac; vistas legacy aparentemente sin uso (`PlannerWeekBoard`, `PlannerSequenceView`, `PlannerSessionsList`, `PlannerScheduleBoard`) conviviendo con las versiones nuevas.

**Intuición / interacción**
- **Sin navegación de semana en macOS** (verificar en app): los controles flotantes de semana solo se montan en la rama iOS; el header Mac que los tenía es código muerto. En iPad, los controles de semana solo existen en la sección Semana: desde Día/Secuencia/Resumen no puedes cambiar de semana.
- Las celdas del grid miniatura son **rectángulos de color sin contenido**: no dicen qué grupo ni qué unidad; obligan a tap → scroll al panel de detalle inferior. En iPad 13" y Mac se desperdicia pantalla: el detalle debería ir en panel lateral, no debajo.
- **Sin drag & drop en el grid de iPad** para mover sesiones (la cascada existe en el modelo; `receiveCascadeDrop` en Mac no parece tener drop target conectado — verificar).
- El color de celda mezcla semánticas: verde = impartida, ámbar = franja sin sesión, azul = planificada; el color del grupo (identidad clave para el docente) no aparece en la miniatura.
- Botón "Observación" en Día hace exactamente lo mismo que "Abrir ficha".
- Sin atajos de teclado (⌘←/→ semana, ⌘T hoy, ⌘N nueva sesión) ni menú de comandos en Mac.

**Datos / corrección**
- Trimestres **hardcodeados** en `PlannerGanttTerm` (1º: S36–52, 2º: S1–14, 3º: S15–26) cuando ya existen `evaluationPeriods` en el ViewModel; año fallback 2026 y `scheduleStartDate = "2026-09-01"` fijos.
- La agrupación del Gantt por `normalized(title)` (título en minúsculas) es frágil: dos situaciones distintas con el mismo nombre se fusionan.
- El Gantt corta a `prefix(4)` sesiones por semana sin indicador de desbordamiento.
- La cobertura del Resumen calcula `available = max(visibleSlots.count, franjas del día)`: infla el denominador los días con menos franjas que el máximo semanal.

**Valor para justificar (el gap más grande)**
- La única "exportación" es texto plano al portapapeles. Para justificar lo realizado ante jefatura/inspección hace falta un **informe imprimible** (PDF) de semana/mes/trimestre con sesiones, objetivos, estado del diario y desviaciones plan-vs-real. Los datos ya existen (sesiones + diarios ricos); falta la salida.

**Premium**
- El sistema Liquid Glass (`plannerGlassPanel`) está bien montado, pero convive con `.thinMaterial` + borde manual en la mitad de las tarjetas → dos lenguajes visuales. Jerarquía tipográfica desigual, badges de estado con 3 estilos distintos, accesibilidad parcial (bien en grid, ausente en Gantt y Resumen).

---

## Fase 0 — Limpieza y línea base (1 día) — ✅ hecha (2026-07-03)

1. Capturas de referencia de las 4 secciones en iPad 13", iPhone-compact y Mac (claro/oscuro) para comparar el antes/después. **Pendiente del dev**: este entorno solo tiene Command Line Tools (sin Xcode.app ni simulador), no se puede lanzar la app.
2. **Código muerto eliminado** (verificado con grep repo-wide antes de borrar; todo recuperable en git history):
   - `PlannerWorkspaceIOS.swift` (5.919 → 4.965 líneas): `PlannerWeekBoard` + `PlannerWeekCellCard` + `PlannerWeekCompactEntryRow` + `PlannerWeekEntryCard` + `PlannerStatusPill` (el board antiguo pre-miniatura), `PlannerSequenceView` + `PlannerSequenceCard` (secuencia pre-Gantt), `PlannerSessionsList` + `PlannerAgendaSessionRow`, `PlannerScheduleBoard` + `PlannerForecastRowView`, y `hasSessionPassed`.
   - `MacModuleStubs.swift` (2.312 → 1.389 líneas): `plannerSidebar`, `plannerHeader`, `@State activeSection` + enum `MacPlannerSection`, `hasSessionPassed`, `openSelectedMacSession`, `weekEntries` + extensión `matchesSearch`, `MacPlannerSessionsTable`, cadena `MacPlannerWeekBoard`/`WeekCell`/`WeekEntryRow`/`SessionDragModifier` (el board Mac antiguo, tenía el drag & drop — referencia para Fase 3), `MacPlannerAgendaView`, `MacPlannerScheduleGenerationPreviewSheet`, `MacPlannerForecastHeaderRow`/`DataRow`.
   - Se conservan a propósito (huérfanos pero se recablean en Fase 1): `receiveCascadeDrop`/`commitCascadeDrop`/`undoCascadeMove` + alerta `pendingCascadeDrop`, `exportCurrentContext`, `copyFilteredWeek`, `moveFilteredSessions`, `openComposerForCurrentFilter` y sus alertas.
3. `hasSessionPassed` no había que unificarlo: estaba **muerto en ambos ficheros** (cero call sites) → eliminado.
4. Sospechosos **confirmados por inspección de código**:
   - **macOS no tiene navegación de semana**: los chevrons vivían en `plannerHeader`, que nunca se renderizaba. Tampoco hay export/mover/limpiar accesibles en Mac (vivían en el sidebar muerto). → Fase 1.1.
   - **El drop de cascada en Mac está desconectado**: `receiveCascadeDrop` no tiene ningún caller; el `draggable` y los drop targets vivían en el `MacPlannerWeekBoard` eliminado. En iPad el grid miniatura tampoco tiene drag & drop. → Fase 1.6 / Fase 3.3.

Sintaxis verificada con `swiftc -parse` en ambos ficheros y grep sin referencias residuales. **Pendiente del dev: compilar ambos targets en Xcode** (este entorno no puede).

## Fase 1 — Correcciones de fiabilidad (2 días) — ✅ hecha (2026-07-03)

1. **Navegación de semana universal — hecho.** `weekNavigationCluster` (← Hoy → + "Deshacer movimiento" condicional) vive ahora en `PlannerToolbar` (`PlannerWorkspaceIOS.swift`), visible en las 4 secciones y en ambas plataformas. Atajos ⌘←/⌘→/⌘T y ⇧⌘Z para deshacer. `PlannerToolbar` acepta un `onUndoCascadeMove` opcional para que cada plataforma lo conecte a su propio feedback (banner/haptics); iOS y Mac lo conectan al coordinator de cascada (punto 6).
2. **Trimestres reales — hecho.** `PlannerGanttTerm` → `PlannerGanttRange` (`PlannerSequenceGanttView.swift`): el picker ahora lista "Periodo actual" + los `vm.evaluationPeriods` reales, y `PlannerGanttWeek` deriva el rango de semanas ISO (año+semana, no solo número) a partir de `startDateIso`/`endDateIso` del periodo, con fallback a ±6 semanas alrededor de hoy si no hay periodos. Nuevo tipo `PlannerCalendar` (en `PlannerWorkspaceIOS.swift`) centraliza "año/semana ISO actual" y "curso escolar por defecto (sept–jun)", eliminando todos los `2026`/`2027` hardcodeados del ViewModel (fallbacks de `KotlinInt`, `scheduleStartDate`/`scheduleEndDate`, `@Published var week/year` iniciales).
3. **Cobertura correcta — hecho.** En `PlannerSummaryStats` (`PlannerSummaryDashboard.swift`), `available` por día ahora son las franjas reales de la agenda docente ese día (0 si no imparte); solo cae al máximo de `visibleSlots` cuando no hay agenda configurada. `covered` se capa a `available` para no superar el 100%.
4. **Gantt honesto — hecho.** Las situaciones se agrupan por `sequenceVersionId` real cuando existe (fallback a título normalizado solo para sesiones sin secuencia vinculada); las semanas con más de 4 sesiones muestran un bloque "+N" con `Menu` que lista el resto (abre cada sesión).
5. **Botón "Observación" — eliminado.** Duplicaba exactamente "Abrir ficha" en `PlannerDaySessionRow`; una acción rápida real de observación llegará en Fase 4.
6. **Drag & drop de cascada conectado en ambas plataformas — hecho.** Nuevo `PlannerCascadeDropCoordinator` (`AppleShared/PlannerCascadeDropCoordinator.swift`, `ObservableObject` compartido) centraliza preview → confirmación si hay sesiones impartidas → commit → mensaje/haptics → deshacer, sustituyendo la lógica que antes solo existía (duplicada) en el Mac. `PlannerWeekMiniatureGrid` añade `.draggable`/`.dropDestination` por celda (solo si la celda tiene exactamente una sesión real, para no ser ambigua) con highlight visual al arrastrar por encima. iPad y Mac instancian el mismo coordinator y le pasan `vm`; Mac elimina su copia local (`receiveCascadeDrop`/`commitCascadeDrop`/`undoCascadeMove`/`MacPlannerPendingDrop`) en favor del coordinator — de paso adelanta parte de la deduplicación prevista para la Fase 2.

Aceptación: cambiar de semana desde cualquier sección y plataforma; trimestre 2º de un curso con periodos configurados muestra sus semanas reales; cobertura 100% cuando todas las franjas del día tienen sesión; arrastrar una sesión a otra celda mueve la cascada en iPad y Mac, con confirmación si toca sesiones impartidas.

Sintaxis verificada con `swiftc -parse` en todos los ficheros tocados. **Pendiente del dev: compilar ambos targets en Xcode y probar el drag & drop en dispositivo/simulador real** (este entorno no tiene Xcode.app).

## Fase 2 — Arquitectura para poder crecer (3 días) — ✅ hecha (2026-07-03)

1. **`MacPlannerView` extraído — hecho.** `MacModuleStubs.swift` (2.312 → 962 líneas) queda solo con `MacReportsView`; `MacPlannerView` y sus tipos privados viven en `MacApp/MacPlannerView.swift` (382 líneas), registrado únicamente en el target Mac (no compila en iOS).

2. **`PlannerWorkspaceIOS.swift` (5.080 líneas) troceado por responsabilidad** en 14 ficheros nuevos, verificado con una prueba de reconstrucción byte a byte (concatenar todos los rangos extraídos en el orden original reproduce el fichero original al carácter) antes de aplicar ningún fix, para garantizar que el troceo en sí no perdió ni duplicó una sola línea:
   - `PlannerModels.swift` (548 líneas): todos los tipos/modelos + los 5 sub-stores internos del ViewModel (`PlannerCalendarStore`, `PlannerSessionStore`, `PlannerScheduleStore`, `PlannerJournalStore`, `PlannerComposerStore`) + `PlannerAudioRecorder`, ahora `PlannerWeekBoardStore` (ver punto 3).
   - `PlannerWorkspaceViewModel.swift` (343 líneas): la clase con sus propiedades almacenadas, lifecycle (`bind`/`reloadAll`/`reload*Only`), navegación de semana, selección y contexto externo.
   - 7 extensiones de la misma clase en ficheros separados (`+Presentation`, `+CascadeMove`, `+Journal`, `+BulkOperations`, `+Composer`, `+Schedule`, `+WeekBoard`, `+Sequences`), cada una 51–367 líneas, agrupadas por dominio.
   - Vistas: `PlannerDayView.swift`, `PlannerJournalDetailPane.swift` (1.177 líneas, la mayor del reparto), `PlannerSessionComposerSheet.swift`, `PlannerSessionDetailSheet.swift`; `PlannerWorkspaceIOS.swift` queda con la vista raíz + `PlannerToolbar` + tiras de progreso (484 líneas).
   - **Bugs de compilación reales que solo aparecen al partir un fichero en varios** (no los detecta `swiftc -parse`, que no resuelve tipos): varios `private let`/`private var`/`private func` de la clase (stores, `bridge`, `autosaveTask`, `reloadWeekSessions`, `rebuildVisiblePlannerStructure`, etc.) se llamaban desde una extensión ahora en *otro* fichero — en Swift `private` es de ámbito de fichero, no de tipo, así que hubo que relajarlos a `internal` donde había uso cruzado (confirmado con un script que compara declaración vs. uso en todo el árbol) dejando `private` donde el uso seguía siendo interno a su propio fichero. Mismo problema con `private extension String { var nilIfBlank }` (patrón repetido en 5+ sitios de la app): 7 ficheros nuevos usaban `.nilIfBlank` sin tener su propia copia de la extensión — se replicó el mismo patrón `private extension` ya usado en el resto del código en cada uno de los 7, en vez de crear una versión `internal` compartida (para no arriesgar colisiones con las copias `private` que ya existen en `KmpBridge.swift`, `IPadWorkspaceShell.swift`, etc., fuera del alcance de esta fase). También `PlannerInstrumentCompactPicker` (usado desde `PlannerSessionComposerSheet.swift` pero declarado `private` en `PlannerJournalDetailPane.swift`) pasó a `internal`.

3. **`PlannerWeekBoardStore` — hecho**, resolviendo el problema real de invalidación (no solo el paliativo de "render model Equatable" que proponía la alternativa mínima). `week`, `year`, `visibleSlots`, `timeSlots`, `holidayDays` y `weekRenderModel` se movieron de `PlannerWorkspaceViewModel` a un `ObservableObject` propio (`PlannerModels.swift`); el facade expone los mismos nombres como propiedades computadas que delegan en el store (cero cambios en los ~110 sitios que ya leían `vm.week`/`vm.weekRenderModel`/etc. en el resto de la app) y reenvía el `objectWillChange` del store al suyo propio vía Combine para que la vista raíz siga reaccionando. `PlannerWeekMiniatureGrid`, `PlannerWeekMiniatureLayout` y `PlannerWeekDetailPane` dejan de declarar `@ObservedObject var vm: PlannerWorkspaceViewModel` y pasan a `@ObservedObject var weekBoard: PlannerWeekBoardStore` + `let vm: PlannerWorkspaceViewModel` (referencia no observada, solo para llamar métodos/helpers). Resultado real: escribir en el buscador (`vm.searchText`, que vive en el facade, no en `weekBoard`) ya **no** dispara el `objectWillChange` que esas tres vistas observan.

Aceptación: ningún fichero Planner > 1.500 líneas (máximo real: 1.177, `PlannerJournalDetailPane.swift`) — cumplido. Escribir en el buscador no invalida el grid semanal — cumplido por construcción (el store que el grid observa no incluye `searchText`); **pendiente del dev confirmar con `Self._printChanges` en Xcode**, ya que este entorno no puede compilar ni ejecutar la app (solo Command Line Tools, sin simulador). Sintaxis verificada con `swiftc -parse` en los ~20 ficheros tocados/creados; auditoría automatizada de accesos cross-file (declaración vs. uso) sin issues pendientes.

## Fase 3 — Semana de 10 (4–5 días, la fase de mayor impacto)

1. **Celdas con contenido.** Sustituir el rectángulo mudo por una mini-tarjeta: banda o fondo con el **color del grupo**, abreviatura del grupo, y estado como pequeño indicador (punto/check), con variante según densidad y tamaño. En celdas multi-sesión, apilado con contador.
2. **Layout adaptativo.** En regular-width (iPad apaisado, Mac): grid a la izquierda + panel de detalle **lateral** persistente (el actual pane inferior pasa a columna derecha, estilo inspector). En compact se mantiene el flujo vertical actual.
3. **Drag & drop — mecanismo base ya en Fase 1** (`PlannerCascadeDropCoordinator`); aquí toca pulirlo: permitir arrastrar desde celdas con varias sesiones (hoy solo funciona 1:1), long-press/click derecho como menú contextual (abrir diario, editar, marcar impartida, duplicar, mover a la semana siguiente) y mejorar la animación del glass durante el arrastre.
4. **Crear en contexto.** Tap en celda vacía con franja → composer prellenado con día/franja/grupo (ya existe el hook, pulirlo a un solo tap desde el panel lateral).
5. **Indicador de hoy**: columna del día actual resaltada; línea de "ahora" si la semana es la actual.

Aceptación: planificar una semana completa sin salir de la sección; mover una sesión cuesta un gesto; el grupo de cada sesión se distingue de un vistazo sin tocar nada.

## Fase 4 — Día como cabina de vuelo (2 días)

1. Timeline vertical con huecos y recreos reales (a partir de `TimeSlotConfig`), indicador "ahora" en vivo, tarjeta de sesión actual expandida.
2. Acciones rápidas por sesión: marcar impartida, nota de voz / observación rápida (el recorder ya existe), abrir diario. Deshacer al marcar impartida por error.
3. Navegación de día (← hoy →) y swipe horizontal entre días.
4. Resumen de cierre del día: "3 de 5 impartidas, 2 diarios pendientes" con CTA para cerrarlos.

Aceptación: durante una jornada, registrar lo esencial de cada sesión cuesta ≤2 gestos; el estado del día es visible sin scroll.

## Fase 5 — Secuencia con barras de verdad (2–3 días)

1. Sustituir los cuadraditos 18×18 por **barras continuas por situación/grupo** (inicio→fin), con segmentos coloreados por estado y sesiones como marcas dentro de la barra; hover/tap muestra popover con detalle.
2. Cabecera con meses además de "S.36"; sombreado de vacaciones/festivos (ya hay `holidays` en el modelo semanal).
3. Sesiones "sin ubicar" de la secuencia arrastrables al timeline (asignar semana) o botón "Ubicar" que abre el composer con la situación preseleccionada.
4. Fila de resumen por grupo: % de la programación impartida vs punto del curso ("vas 2 sesiones por detrás del plan").

Aceptación: de un vistazo se ve qué situaciones van adelantadas/atrasadas por grupo; ubicar una sesión pendiente cuesta un gesto.

## Fase 6 — Resumen + justificación documental (3 días) ⭐ mayor valor añadido

1. **Informe PDF** (ImageRenderer o vista de impresión): informe semanal/mensual/por evaluación con sesiones planificadas vs impartidas, objetivos, estado de diarios, incidencias y firma/fecha. Plantilla sobria imprimible pensada para jefatura/inspección. Compartir vía ShareLink/Guardar.
2. **Plan vs real**: métrica de desviación (sesiones movidas, canceladas, no impartidas) por semana y por grupo — es la narrativa que justifica el trabajo.
3. Alertas accionables: cada alerta del Resumen navega a resolverla (diarios pendientes → lista con acceso directo; días sin sesiones → Semana en ese día).
4. Rango del Resumen conmutable: semana / mes / evaluación (hoy solo semana).

Aceptación: un docente genera en <30 s un PDF de su evaluación que puede entregar tal cual; cada alerta se resuelve desde la propia alerta.

## Fase 7 — Mac de primera clase (2–3 días)

1. Toolbar nativa de macOS (navegación de semana, picker de sección como `ToolbarItem`, búsqueda con ⌘F) en lugar del `PlannerToolbar` de iOS; menú de comandos (Archivo → Nueva sesión ⌘N; Vista → Semana/Día/Secuencia/Resumen ⌘1–4; Edición → Deshacer movimiento con `UndoManager`).
2. Hover states en celdas y filas; doble click abre ficha; click derecho = menú contextual de Fase 3.
3. Detalle de sesión como **inspector lateral** (no sheet modal) para poder ver grid y ficha a la vez.

Aceptación: el Planner en Mac se maneja 100% con teclado+ratón sin sheets bloqueantes; ⌘1–4 cambia de sección.

## Fase 8 — Pulido premium y accesibilidad (2 días)

1. Unificar todas las tarjetas sobre `plannerGlassPanel` (roles hero/content/control) eliminando los `.thinMaterial` + borde manual sueltos; una sola escala tipográfica y un solo estilo de badge de estado (cápsula con icono).
2. Animaciones coherentes (un spring compartido), transición suave grid↔detalle, `contentTransition(.numericText())` en métricas.
3. Accesibilidad: labels/valores en Gantt, Resumen y controles flotantes; Dynamic Type sin roturas en el grid (densidad automática); contraste AA de los colores de estado en oscuro.
4. Auditoría rápida con `swiftui-polish` y capturas del después vs la línea base de Fase 0.

Aceptación: VoiceOver puede leer estado de cualquier celda/barra; cero materiales "sueltos" fuera del sistema glass.

---

## Orden y esfuerzo

| Fase | Días | Impacto |
|---|---|---|
| 0 Limpieza | 1 | Base sana ✅ |
| 1 Fiabilidad | 2 | Bugs visibles ✅ |
| 2 Arquitectura | 3 | Velocidad futura ✅ |
| 3 Semana | 4–5 | ⭐ uso diario |
| 4 Día | 2 | uso diario |
| 5 Secuencia | 2–3 | planificación a futuro |
| 6 Justificación | 3 | ⭐ valor docente |
| 7 Mac | 2–3 | premium Mac |
| 8 Pulido | 2 | premium global |

Total ≈ 21–24 días. Si hay que priorizar: 0 → 1 → 3 → 6 dan el 80% del salto percibido (fiabilidad + semana usable + PDF justificativo); 2 puede intercalarse antes de 3 si el rendimiento ya duele.

Al cierre de cada fase: `registrar-avance-app` (changelog + memoria de desarrollo), captura comparativa y build en ambos targets.
