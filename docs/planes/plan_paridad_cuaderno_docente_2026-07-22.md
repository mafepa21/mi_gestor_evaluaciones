# Plan — Paridad competitiva tras el análisis de "Mi Cuaderno Docente" (2026-07-22)

Origen: cuatro capturas públicas de la app **Mi Cuaderno Docente** (@tolobv, versión web/tablet) publicadas el 2026-07-21. Se analizaron cuatro pantallas —menú principal, horario de grupo, planificador mensual y "Balance de Aula Avanzado"— y se contrastaron con el estado real del código Apple (`kmp/iosApp/`).

Este plan cubre **los dos ítems ejecutables de forma inmediata** (F-1 y F-2), con diseño cerrado y verificación definida, más un backlog priorizado (B-1 a B-4) que requiere decisión de producto antes de convertirse en plan propio.

## Conclusión del análisis

En profundidad de evaluación (cuaderno, rúbricas, fórmulas, LOMLOE, IA Apple Foundation) estamos claramente por delante. Los huecos son de **gestión documental** (reuniones, tutorías con familias) y de **visualización de lo que ya calculamos**: tenemos analítica que el docente no ve donde la necesita.

## Reglas de trabajo

- Rama `feature/paridad-cuaderno-docente-1` desde `main`, y `-2` encadenada si F-1 y F-2 se separan en dos PR.
- Un commit atómico por ítem, formato `feat(<ámbito>): <descripción>` en español.
- Entrada en `docs/CHANGELOG.md` bajo `## Unreleased` → `### Added` por cada ítem, citando este fichero.
- **Regla de oro de `AGENTS.md`**: no tocar `KmpBridge.swift`, `kmp/shared/`, `kmp/data/`, `EvaluationDesign.swift` ni `desktopApp/`. F-1 y F-2 están diseñados para cumplirla: ambos consumen API pública ya existente. La única excepción propuesta (bug D-2) queda **fuera del plan** hasta autorización expresa.
- Verificación: `xcodebuild -project kmp/iosApp/MiGestorKMPiOS.xcodeproj -scheme MiGestorKMPMac build` (hay fallos de CI preexistentes ajenos, ver `apple-build-ci-chain-2026-07`; comparar contra el estado previo, no contra cero).

---

## F-1 · Heatmap de incidencias en Asistencia (reutilización pura)

### Diagnóstico

El heatmap **ya existe y ya se calcula**, pero está enterrado en Informes:

- Cálculo: `KmpBridge.buildIncidentHeatmapFacts` ([KmpBridge.swift:12517](../../kmp/iosApp/App/KmpBridge.swift:12517)), accesible desde fuera vía el método público `buildChartFacts(classId:request:)` ([KmpBridge.swift:12371](../../kmp/iosApp/App/KmpBridge.swift:12371)). Filas = semanas recientes (`S-1`…`S-n`, entre 2 y 6 según rango), columnas = día de la semana.
- Render: `AnalyticsHeatmapView` ([RubricsReportsWorkspaceViews.swift:1823](../../kmp/iosApp/App/RubricsReportsWorkspaceViews.swift:1823)), invocado en un único sitio ([:1682](../../kmp/iosApp/App/RubricsReportsWorkspaceViews.swift:1682)).
- Mientras tanto, `AttendanceWorkspaceView` (1101 líneas) solo expone `attendanceRate`, contadores del día y un "Histórico reciente" plano. El docente no tiene forma de ver *cuándo* se concentran las incidencias sin salir a Informes y saber que ese gráfico existe.

Es decir: no hay que construir analítica nueva, hay que **ponerla donde se usa**.

### Diseño

Añadir una tarjeta "Patrones de incidencias" a `monthlyHistoryContent` (modo Histórico), **sin crear una cuarta pestaña**: el modo Histórico ya es el sitio donde el docente mira hacia atrás, y `AttendanceBoardMode` se queda en tres opciones (Test de la Obviedad).

> **Desviación aplicada durante la implementación.** El plan decía "al final"; la tarjeta va **encima** de la rejilla. Al final quedaba inalcanzable en un grupo con 25 alumnos (habría que scrollear toda la rejilla mensual para descubrirla), y el orden agregado → detalle es el natural al entrar en el histórico. Además obligó a reestructurar el scroll: `monthlyHistoryContent` era un único `ScrollView([.horizontal, .vertical])`, lo que habría desplazado la tarjeta lateralmente al recorrer el mes; pasa a ser un scroll vertical externo con el scroll horizontal acotado a la rejilla.

La tarjeta contiene:
- Título + subtítulo tomados de `ChartFacts.subtitle`.
- `AnalyticsHeatmapView(cells:)` reutilizado tal cual.
- Las tres métricas de `ChartFacts.metrics` (Incidencias / Pico / Semanas) como fila superior.
- La línea de mayor concentración de `factLines` bajo el gráfico ("Mayor concentración: S-2 · V con 7 incidencias").
- Empty state: `emptyStateMessage` cuando `hasEnoughData == false`.

### Pasos

1. **D-1 (bloqueante, arreglar primero): las columnas del heatmap salen desordenadas.** `AnalyticsHeatmapView.columns` hace `Array(Set(cells.map(\.columnLabel))).sorted()` ([:1830](../../kmp/iosApp/App/RubricsReportsWorkspaceViews.swift:1830)), orden alfabético. Con etiquetas `L,M,X,J,V,S,D` eso se renderiza como **D, J, L, M, S, V, X**: un heatmap de días de la semana en orden alfabético es ilegible y hoy ya está así en Informes. Corrección: ordenar por el índice de aparición en `cells` en lugar de alfabéticamente (respeta el orden en que el productor los generó y no acopla la vista a un dominio concreto). Filas (`S-1`…`S-6`) siguen bien con `.sorted()` mientras haya < 10 semanas, que es el máximo actual (`weeksBack ≤ 6`).
2. Extraer la tarjeta a `AttendancePatternsCard` en `AttendanceWorkspaceView.swift` (o fichero hermano si el archivo crece demasiado).
3. Estado nuevo en `AttendanceWorkspaceView`: `@State var incidentHeatmapFacts: KmpBridge.ChartFacts?` + `@State var isLoadingHeatmap = false`.
4. Carga perezosa: solo al entrar en `boardMode == .history` y con `selectedClassId != nil`; cancelar y recargar al cambiar de clase (mismo patrón que `classSelectionTask`). Rango por defecto `.last30Days`.
5. Insertar la tarjeta en `monthlyHistoryContent` con el espaciado de tarjeta estándar del módulo.

### Verificación

- Con un grupo con incidencias registradas: el heatmap aparece en Histórico, columnas en orden **L M X J V S D**, y el pico coincide con el que muestra la misma tarjeta en Informes.
- Con un grupo sin incidencias: se ve el empty state, no una rejilla vacía.
- Cambiar de grupo recarga los datos sin quedarse con los del anterior.
- Regresión en Informes: el heatmap sigue funcionando y ahora también con los días ordenados.

### Hallazgos de la verificación en la app real (2026-07-22)

1. **Asistencia no es una vista compartida.** El plan asumía que bastaba con tocar `AttendanceWorkspaceView`. Falso: macOS usa `MacApp/MacAttendanceView.swift`, una implementación **completamente separada** (1244 líneas, su propio `mode`, su propio `historyContent`). La primera versión del cambio no aparecía en la app de Mac. La tarjeta está ahora duplicada en las dos vistas.
   **Consecuencia para F-2 y para el backlog: dar por hecho que un cambio en `App/` llega a macOS es incorrecto.** Comprobar siempre si existe un equivalente en `MacApp/`.
2. **`ChartFacts.hasEnoughData` no sirve para decidir el empty state del heatmap.** Vale `!cells.isEmpty`, y `buildIncidentHeatmapFacts` genera una celda por cada combinación semana × día aunque todas valgan 0. Un grupo sin ninguna incidencia pintaba la rejilla completa de ceros, "Se han revisado 0 incidencias" y la línea absurda "Mayor concentración: S-3 · L con 0 incidencias". El empty state se decide ahora mirando si hay algún valor > 0.
3. **Estado con datos verificado con incidencias temporales** (7 registros insertados en 3 ESO A y borrados después; la base quedó de nuevo en `count(*) = 0`). Totales, pico, rampa de color, orden de columnas y línea de mayor concentración: correctos.

### Coste estimado

Medio día. Es el mejor ratio impacto/coste de todo el análisis. (Real: algo más, por la duplicación iOS/macOS no prevista.)

---

## F-2 · Rejilla semanal de horario + exportación a PDF

### Diagnóstico

Más grave de lo que sugería la captura. No es que falte el PDF: **no tenemos vista de rejilla**. `TeacherScheduleSettingsPanel` muestra las franjas como **lista lineal** ordenada por `(dayOfWeek, startTime)` — `slotsCard` ([TeacherScheduleSettingsView.swift:750](../../kmp/iosApp/App/TeacherScheduleSettingsView.swift:750)) y `slotRow` ([:1048](../../kmp/iosApp/App/TeacherScheduleSettingsView.swift:1048)). Un horario es un objeto bidimensional; presentarlo como lista obliga al docente a reconstruir mentalmente la semana.

Y confirmado por búsqueda: no hay ninguna ruta de PDF ni de impresión en las 2289 líneas del fichero.

### Diseño

Dos entregables sobre el mismo componente:

**a) `ScheduleWeekGridView`** — nuevo fichero en `AppleShared/`, sin estado propio, entrada `[TeacherScheduleSlot]` + nombres de grupo + `activeWeekdays`:
- Columnas = días lectivos activos (respeta `vm.activeWeekdays`, no fuerza L-V).
- Filas = franjas horarias distintas derivadas de los `startTime`/`endTime` presentes, ordenadas.
- Celda ocupada: materia (dominante) + grupo + unidad en secundario. Celda vacía: hueco sobrio, sin CTA (a diferencia del competidor: aquí el alta ya vive en el editor de arriba; añadir un "+ Asignar" en cada hueco es ruido).
- Solapes en la misma franja: apilados dentro de la celda, no ocultos.

Se inserta en `slotsCard` **encima** de la lista existente. La lista se conserva porque es donde viven Editar/Duplicar/Borrar; la rejilla es lectura.

**b) `ScheduleGridPDFRenderer`** — `PlannerReportPDFRenderer` ([PlannerReportPDFRenderer.swift](../../kmp/iosApp/App/PlannerReportPDFRenderer.swift)) **no sirve aquí**: pagina un `NSAttributedString` con `CTFramesetter`, es texto corrido y no sabe dibujar una tabla. Para una rejilla, el camino Apple correcto es `ImageRenderer` sobre la propia `ScheduleWeekGridView` volcando su `CGContext` en un contexto PDF — así el PDF es literalmente lo que se ve en pantalla y no hay dos maquetaciones que mantener sincronizadas.
- A4 apaisado (842 × 595), márgenes 48, escala ajustada al ancho de la rejilla.
- Cabecera: nombre de agenda + grupo en foco (o "Todos") + fecha de generación.
- Salida a fichero temporal + `ShareLink`, reutilizando el patrón de `writeToTemporaryFile` ([:57](../../kmp/iosApp/App/PlannerReportPDFRenderer.swift:57)) y el flujo de un clic que ya usa el informe de Planner.

Botón "Exportar horario" en la cabecera de `slotsCard`, junto a "Importar horario".

### Verificación

- Horario con franjas en 5 días y solapes: la rejilla los muestra todos, sin recortes, a 900 pt de ancho (mínimo de ventana macOS, ver `plan_auditoria_layout_2026-07-15.md`).
- Con `activeWeekdays` reducido a L-J, la rejilla muestra 4 columnas.
- PDF generado: se abre, cabe en una página A4 apaisada para un horario típico de 6-7 franjas, y coincide celda a celda con la pantalla.
- Sin franjas: la rejilla no se dibuja y el botón de exportar queda deshabilitado.

### Coste estimado

Un día. La rejilla es la mitad del trabajo; el PDF sale casi gratis una vez existe la vista.

---

## Defectos detectados de paso

- **D-1** — Columnas del heatmap en orden alfabético. Incluido en F-1 (fichero permitido).
- **D-3** — **Las filas del heatmap no son semanas lectivas, sino ventanas móviles de 7 días contadas desde hoy.** `weeksDifference` sale de `dateComponents([.weekOfYear], from: date, to: Date())` ([KmpBridge.swift:12532](../../kmp/iosApp/App/KmpBridge.swift:12532)), que cuenta semanas transcurridas, no límites de semana natural. Comprobado con datos: incidencias del **viernes 17-jul** y del **lunes 20-jul** —semanas escolares distintas— cayeron ambas en la fila `S-3`. Para un docente que lee `S-3` como "esta semana", el reparto es engañoso justo en el eje que da sentido al gráfico. Se suma que el etiquetado `S-1`…`S-3` va de más antigua a más reciente, lo que se lee al revés de lo que sugiere el nombre. Ambos están en `KmpBridge.swift`: **requieren autorización explícita**.
- **D-2** — `buildIncidentHeatmapFacts` itera `for weekday in 2...8` ([KmpBridge.swift:12529](../../kmp/iosApp/App/KmpBridge.swift:12529)), pero `Calendar.component(.weekday)` devuelve 1…7. Consecuencias: la columna "D" **nunca puede tener valor** (weekday 8 no existe) y el domingo real (weekday 1) no se cuenta en ninguna columna. Es cosmético en un contexto escolar —nadie registra incidencias en domingo— pero deja una columna muerta permanente en el gráfico. **Está en `KmpBridge.swift`: requiere autorización explícita para tocarlo.** Si no se autoriza, F-1 sigue siendo válido; simplemente se ve una columna "D" siempre vacía.

---

## Backlog priorizado (requiere decisión de producto)

- **B-1 · Registro de tutorías con familias.** Hoy "Tutoría" existe solo como *tipo de tramo horario* ([ScheduleExcelImportService.swift:311](../../kmp/iosApp/AppleShared/ScheduleExcelImportService.swift:311)) y como medida de apoyo (`partTutoriasPersonalizadas`). No hay registro de entrevistas: fecha, asistentes, temas, acuerdos, seguimiento. Encaja colgando de `StudentProfilesWorkspaceView` y enlaza natural con las medidas de apoyo existentes. Alto valor documental y legal. **Requiere tabla nueva en `kmp/data/` → migración SQLDelight.**
- **B-2 · Reuniones y actas.** Inexistente: cero coincidencias de "reunión/acta/claustro" en todo el código Apple. Módulo autónomo (acta, asistentes, acuerdos con responsable y fecha límite, exportable a PDF con el renderer de texto que ya tenemos). También requiere esquema nuevo.
- **B-3 · Checklists de estrategias didácticas y de evaluación por semana en Planner.** El competidor asocia a cada semana un banco cerrado de técnicas (evocación, codificación dual, ejemplos múltiples…) y de instrumentos de evaluación. Barato sobre `PlannerWeekDetailPane`, muy visible, y aporta una identidad pedagógica explícita que hoy no tenemos. Sin esquema nuevo si se guarda como metadatos de la semana.
- **B-4 · Recomendaciones accionables en el dashboard.** Hoy decimos "alumnado en riesgo"; falta el "qué hacer". Se puede derivar de los patrones que F-1 pone a la vista.
  **Restricción de honestidad**: el competidor muestra un "Algoritmo de Proyección Estocástica" con una predicción de `75,0 %`. Un decimal sobre datos de un aula es precisión falsa y no lo replicamos. Si hacemos proyección, va con rango y con el método declarado, o no va.

## Descartado explícitamente

- **Menú principal de 8 tarjetas como navegación raíz.** Nuestro `WorkspaceSidebar` + workspaces es mejor en iPad/Mac; un grid de tarjetas sería un retroceso.
- **"Áreas de Primaria personalizadas"** como alta suelta: ya cubierto por la gestión de asignaturas y criterios existente.
- **Predicción con precisión falsa** (ver B-4).
