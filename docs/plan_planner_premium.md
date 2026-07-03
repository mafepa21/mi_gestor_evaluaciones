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

## Fase 3 — Semana de 10 (4–5 días, la fase de mayor impacto) — ✅ hecha (2026-07-03)

1. **Celdas con contenido — hecho.** `PlannerWeekMiniatureCell` (`PlannerWeekMiniatureGrid.swift`) ya no es un rectángulo mudo: fondo tintado con el **color del grupo** (`Color(hex: entry.classColorHex)`), abreviatura del grupo (iniciales derivadas de `className`) centrada, y un badge de estado en la esquina (check/borrador/reloj según `vm.sessionStateIcon`/`sessionStateTint`, o "+" para franjas de agenda sin sesión). En celdas con más de una entrada, en vez del rectángulo de color de la primera sesión se muestran hasta 3 puntos apilados (uno por color de grupo) + contador "+N" si hay más — el "apilado con contador" del plan.
2. **Layout adaptativo — hecho.** `PlannerWeekMiniatureLayout` decide entre `regularLayout` (grid a la izquierda + `PlannerWeekDetailPane` como panel lateral fijo de 400pt con su propio scroll, estilo inspector) y `compactLayout` (el flujo vertical de siempre, grid arriba + detalle debajo en un único scroll), usando el mismo patrón `isRegularWidth` (`horizontalSizeClass == .regular` en iOS, siempre `true` en Mac) ya usado en `IPadWorkspaceShell`. La API pública del componente no cambia, así que no hace falta tocar los dos call sites (iPad/Mac).
3. **Drag & drop pulido — parcial, por precaución.** Se añadió `.contextMenu` (long-press en iPad, click derecho en Mac — gratis con el mismo modificador) en celdas de una sola sesión: Abrir diario, Editar sesión, Marcar impartida (deshabilitado si ya está impartida), Copiar a la semana siguiente (nuevo `vm.copySessionToNextWeek(_:)`, que copia una sola sesión sin tocar el modo de selección múltiple). **No** se implementó arrastrar desde celdas multi-sesión (el plan lo pedía): intentar un `.draggable` por cada chip apilado dentro de un `Button` de ~44pt de celda es un patrón de gestos de alto riesgo (conflictos táctiles reales) que no puedo verificar sin dispositivo/simulador en este entorno — queda para cuando el dev pueda probarlo interactivamente.
4. **Crear en contexto — ya cumplía el criterio**, sin cambios: tocar una celda vacía selecciona la franja en el panel de detalle (ahora lateral en iPad apaisado/Mac) y su botón "Crear sesión" abre el composer prellenado con día/franja/grupo.
5. **Indicador de hoy — hecho.** Cuando la semana mostrada es la semana ISO actual: la cabecera del día de hoy muestra un punto de acento junto al nombre (y un borde de acento si no está seleccionado); la franja horaria cuyo rango contiene la hora actual se resalta en el eje de tiempo (texto y fondo en acento). Se descartó una línea continua de "ahora" superpuesta al grid: al ser una parrilla de franjas discretas (no un timeline continuo de minutos), resaltar la franja en curso comunica lo mismo sin inventar una posición en píxeles poco fiable; la línea de "ahora" de verdad llega en la Fase 4 (vista Día, que sí es un timeline continuo).

Aceptación: planificar una semana completa sin salir de la sección — cumplido (crear/editar/marcar impartida ahora también desde el menú contextual de la celda, sin pasar por el panel). El grupo de cada sesión se distingue de un vistazo sin tocar nada — cumplido (color + abreviatura). "Mover una sesión cuesta un gesto" — cumplido desde Fase 1 (drag & drop 1:1); el caso multi-sesión queda pendiente por el motivo de arriba.

Sintaxis verificada con `swiftc -parse` en todos los ficheros tocados; auditoría automatizada de accesos cross-file repetida tras los cambios, sin issues. **Pendiente del dev: compilar y probar en iPad (vertical/apaisado) y Mac, y confirmar visualmente el layout lateral, las abreviaturas de grupo y el indicador de hoy** (este entorno no tiene Xcode.app ni simulador).

## Fase 4 — Día como cabina de vuelo (2 días) — ✅ hecha (2026-07-03)

1. **Timeline vertical — hecho.** `PlannerDayView` reconstruida por completo: las filas se generan a partir de `vm.visibleSlots` (franjas reales del docente ese día), detectando huecos entre el fin de una franja y el inicio de la siguiente (`PlannerDayGapRow`, "Recreo HH:mm-HH:mm") y franjas libres tocables para crear sesión (`PlannerDayEmptySlotRow`, borde discontinuo). Un marcador "Ahora HH:mm" (`PlannerDayNowMarker`) se inserta en la posición cronológica correcta de la lista cuando el día mostrado es hoy, refrescado cada 60s con un `Timer.publish` (patrón ya usado en `LibraryAndPEWorkspaceViews.swift`). La sesión en curso (`isCurrent`) se muestra con más padding, sombra y hasta 4 líneas de objetivo en vez de 2. **Decisión de diseño:** no se dibuja una línea continua superpuesta con posición en píxeles — al ser una lista de filas discretas (no un canvas con eje de tiempo continuo), insertar el marcador como una fila más en el orden cronológico es más simple y fiable que calcular offsets verticales proporcionales al tiempo.
2. **Acciones rápidas — hecho, con un recorte deliberado.** "Abrir ficha" y "Marcar impartida" ya existían; se añadió "Nota rápida" (`PlannerQuickNoteSheet`, un `TextEditor` + Guardar — 2 gestos) que llama a un nuevo `vm.quickAddObservation(to:text:)` (`PlannerWorkspaceViewModel+DayBoard.swift`): carga el diario de la sesión si no era la seleccionada, añade el texto a `groupObservations` (respetando lo que ya hubiera) y guarda. Marcar impartida ahora ofrece "Deshacer" en un banner de 5s (`PlannerWorkspaceViewModel+BulkOperations.swift` generaliza `markCompleted` a `setSessionStatus(_:status:)`, capturando el estado previo antes de cambiarlo). **No implementado:** nota de voz — grabar audio, guardarlo como adjunto del diario y reproducirlo son flujos que dependen de permisos de micrófono y AVFoundation que no puedo verificar sin dispositivo/simulador; la vía existente (abrir la ficha completa, que sí tiene grabadora) sigue disponible para eso.
3. **Navegación de día — hecho.** Nuevo estado `dayViewSelectedDay` en el facade (con passthrough en `selectedDayForDayView`, que antes solo derivaba del día de hoy o de la sesión seleccionada) + `goToPreviousDayInDayView()`/`goToNextDayInDayView()`/`goToTodayInDayView()` que saltan de semana en los límites (viernes → siguiente lunes de la semana que viene, llamando a `vm.nextWeek()`). Botones ← Hoy → en la cabecera y gesto de swipe horizontal (`DragGesture` con `.simultaneousGesture`, umbral direccional `|Δx| > |Δy|×1.5` y `|Δx| > 60pt` para no robarle el scroll vertical al `ScrollView`) — **pendiente de ajuste fino en dispositivo real**, los umbrales son una primera aproximación razonable sin poder probarlos interactivamente.
4. **Resumen de cierre del día — hecho.** Tira con icono + "N de M impartidas" + "K diario(s) pendiente(s) de cerrar" (o "Todos los diarios están al día") y botón "Cerrar" que abre la primera sesión impartida sin diario cerrado.

Aceptación: durante una jornada, registrar lo esencial de cada sesión cuesta ≤2 gestos — cumplido (marcar impartida = 1 toque; nota rápida = escribir + guardar). El estado del día es visible sin scroll — cumplido (resumen de cierre justo bajo la cabecera). Sintaxis verificada con `swiftc -parse`; auditoría automatizada de accesos cross-file repetida sin issues nuevos.

**Pendiente del dev:** compilar y probar en dispositivo — en particular el umbral del swipe horizontal (puede sentirse demasiado sensible o poco sensible sin ajuste en vivo) y confirmar que el timer de 60s no consume batería de forma notable al dejar la app en Día mucho tiempo.

## Fase 5 — Secuencia con barras de verdad (2–3 días) — ✅ hecha (2026-07-03)

1. **Barras continuas — hecho.** Nuevo `PlannerGanttContinuousBar` sustituye los cuadraditos sueltos de `PlannerGanttTimelineCells`: para cada fila (situación agregada y cada grupo) se calcula el **rango real de semanas** (desde la primera a la última semana con una sesión asignada) y ese tramo se pinta como una franja continua de color — verde si esa semana tiene una sesión impartida/cerrada, acento si planificada, ámbar si hay una "pendiente de ubicar" — con las sesiones como marcas de 18×18 dentro de cada franja semanal (o un contador tocable si hay varias esa semana). El detalle al tocar usa `Menu` (mismo patrón ya probado en el bloque de desbordamiento existente) en vez de `.popover`, que no había manera de verificar en ambas plataformas sin dispositivo.
2. **Cabecera con meses + sombreado — hecho.** Fila de meses (`monthHeader`) sobre la fila de semanas, agrupando semanas consecutivas del mismo mes (nuevo `PlannerGanttWeek.monthTitle`, derivado de la fecha real del lunes de esa semana ISO — nuevo `mondayDate`). El sombreado de "vacaciones" **no usa** `weekBoard.holidayDays` (eso son festivos sueltos dentro de una semana concreta, no aplican a un timeline de varios meses): se calculan como las semanas visibles que **no caen dentro de ningún periodo de evaluación configurado** — un dato real ya existente (`vm.evaluationPeriods`), no una suposición. Si el docente no tiene periodos configurados, no se sombrea nada (no hay con qué comparar).
3. **Botón "Ubicar" — hecho, sin el arrastre.** Cada fila de grupo con sesiones "pendiente de ubicar" (ya existían en el modelo pero **no se mostraban en ningún sitio** — `PlannerGanttTimelineCells.rowsForWeek` las descartaba por completo al no tener `planningSession`) muestra ahora un badge "N sin ubicar" con un `Menu` que lista cada una; tocarla abre el composer con `learningSituationSessionPlanId`, objetivo y título de unidad prellenados, y selecciona el grupo correcto antes de abrir. **No implementado:** arrastrar la sesión sin ubicar directamente a una celda del timeline para asignarle semana — el composer igualmente necesita día/franja después de soltar, así que la ganancia frente al botón es menor que en el drag & drop de Semana, y no puedo validar un nuevo tipo de drop target sin dispositivo.
4. **Resumen de ritmo por grupo — hecho.** Bajo el nombre de cada grupo, si la situación tiene al menos una sesión asignada: "Vas N sesiones por delante/detrás" o "Al día con el plan", calculado como sesiones completadas − sesiones esperadas a estas alturas (proporcional a cuántas semanas del tramo real de la situación ya han pasado). Si la situación no ha empezado o terminó hace más de 4 semanas, no se muestra (para no dar un ritmo sin sentido fuera de su ventana activa); en su lugar se mantiene el contador de planificadas de siempre.

Aceptación: de un vistazo se ve qué situaciones van adelantadas/atrasadas por grupo — cumplido (etiqueta de ritmo bajo cada grupo). Ubicar una sesión pendiente cuesta un gesto — cumplido vía el botón/menú "Ubicar" (arrastrar queda pendiente, ver arriba).

Sintaxis verificada con `swiftc -parse`; auditoría automatizada de accesos cross-file repetida sin issues nuevos. **Pendiente del dev:** compilar y confirmar visualmente las franjas continuas, el sombreado de vacaciones (con periodos de evaluación reales configurados) y que el `Menu` de detalle se sienta bien tanto en iPad (tap) como en Mac (click).

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
| 3 Semana | 4–5 | ⭐ uso diario ✅ (drag multi-sesión pendiente) |
| 4 Día | 2 | uso diario ✅ (nota de voz pendiente) |
| 5 Secuencia | 2–3 | planificación a futuro ✅ (drag pendiente) |
| 6 Justificación | 3 | ⭐ valor docente |
| 7 Mac | 2–3 | premium Mac |
| 8 Pulido | 2 | premium global |

Total ≈ 21–24 días. Si hay que priorizar: 0 → 1 → 3 → 6 dan el 80% del salto percibido (fiabilidad + semana usable + PDF justificativo); 2 puede intercalarse antes de 3 si el rendimiento ya duele.

Al cierre de cada fase: `registrar-avance-app` (changelog + memoria de desarrollo), captura comparativa y build en ambos targets.
