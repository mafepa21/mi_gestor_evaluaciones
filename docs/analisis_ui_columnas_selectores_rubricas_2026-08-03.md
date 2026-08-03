# Análisis UI — Menú de columna, selectores de celda y rúbricas

Fecha: 2026-08-03
Rama: `claude/ui-analysis-menu-columna-selectores-rubricas-44877`
Propósito: material de referencia para pedir mejoras de diseño (Claude Design). Solo análisis, sin cambios de código.

---

## 0. Sistema de diseño base

Hay dos familias de estilo conviviendo en la app:

- **`EvaluationDesign.swift`**: sistema "editorial", pensado para portadas — tipografía muy gruesa (`.black`, `.bold`), radios grandes, chips, avatares, fondos con gradiente y blur. Está bloqueado por auditorías de UI en curso.
- **`RubricsStyle.swift` / `NotebookGridStyle`**: capa más pequeña y densa, pensada para trabajo de tabla (radios más chicos, colores de nota reutilizados del grid).

El propio código documenta por qué existen ambos: Rúbricas necesitaba algo más denso que `EvaluationDesign` pero no podía tocar ese archivo. Es una pista clara para el diseñador: **conviven al menos 3 lenguajes visuales** (editorial, denso/tabular, y glassmorphism en la evaluación masiva de rúbricas).

---

## 1. Menú de creación de columna nueva
Archivo: `kmp/iosApp/App/AddColumnSheet.swift` (1798 líneas)

### Cómo funciona hoy

- Es un sheet de una sola pantalla con scroll, no un asistente por pasos.
- Primero eliges el **tipo de columna** en tarjetas (`ColumnBlueprintCard`): Nota numérica, Rúbrica, Lista de control, Observación, Participación, y en "Más opciones" (colapsado): Fórmula, Evidencia, Síntesis con IA.
- Hay **plantillas por materia**: chips que aplican de un golpe tipo + nombre + peso + categoría.
- Eliges dónde va la columna (categoría existente o nueva).
- Luego aparece la configuración específica del tipo elegido: para rúbrica, buscador y lista de rúbricas agrupadas; para checklist, una vista previa; para fórmula, un teclado propio con validación en vivo y ejemplo con datos reales; para síntesis IA, tarjetas de opción (fuente, longitud, modo) más una vista previa de texto.
- Al final, un pie fijo con el botón de guardar y el estado ("Lista para crear" o el motivo por el que no se puede).

### Lo que un diseñador probablemente querría revisar

- Muchas secciones compiten a la vez en una sola pantalla (tipo, plantillas, categoría, configuración) — no hay pasos, todo se ve junto.
- Hay una tarjeta duplicada ("Pruebas físicas") que aparece dos veces en el mismo sheet.
- El campo de "Peso" es un cuadro de texto simple, mucho más pobre visualmente que el resto del sheet (que usa tarjetas y chips).
- Hay un interruptor (toggle) que nunca se puede apagar — confuso, mejor sería un texto informativo.
- Acordeones dentro de acordeones (rúbrica dentro de "más opciones" dentro de secciones colapsables) — difícil saber qué nivel se está expandiendo.
- Pocas variaciones de tamaño de letra: casi todo el sheet usa 2-3 tamaños, sin mucha jerarquía visual clara.

---

## 2. Selectores dentro de las celdas del cuaderno
Archivos: `NotebookEditableTableCell.swift`, `NotebookModuleGridCells.swift`, `NotebookDynamicCellsRow.swift`, `NotebookModuleCellActions.swift`, `NotebookDataGrid.swift`

### Cómo funciona hoy

Cada tipo de dato tiene su propio editor dentro de la celda:

- **Nota numérica**: en Mac se edita escribiendo directo; en iPad/iPhone se abre un teclado numérico propio en una ventana flotante (popover). Además se puede **arrastrar el dedo hacia arriba o abajo** sobre la celda para subir o bajar la nota de 0.1 en 0.1, con vibración al llegar a los extremos (0 o 10).
- **Checklist**: un botón que alterna entre marcado y sin marcar. El más simple y directo de todos.
- **Rúbrica**: la celda solo muestra la nota ya calculada; al tocarla se abre la evaluación completa. Mantener presionado da un menú con "Evaluar alumno" o "Evaluar grupo".
- **Fórmula**: celda de solo lectura en cursiva; si hay error, aparece un aviso naranja.
- **Participación / niveles (A/B/C/D, etc.)**: botón que abre una ventana flotante con la lista de opciones.
- **Asistencia**: un modo rápido (un toque cambia entre Presente/Ausente/Retraso) o un selector completo con 7 estados, cada uno con su color.
- **Texto libre / síntesis con IA**: campo de texto directo; si el texto no cabe, un botón abre una ventana con el texto completo.

Todas las celdas comparten señales visuales pequeñas en las esquinas: candado (bloqueada), tachado (no cuenta para la media), punto ámbar (guardando) o verde (guardado).

### Lo que un diseñador probablemente querría revisar

- Se puede editar la nota numérica de dos formas distintas (arrastrando o abriendo el teclado) pero no hay ninguna pista visual de que el arrastre existe hasta que ya se está haciendo.
- Todas las celdas tienen la misma altura fija y pequeña (44 puntos), lo que puede apretar mucho los botones pequeños (generar texto, expandir) en columnas angostas.
- El selector de asistencia, con 7 opciones, se ve como una simple lista de texto — mucho más pobre que la celda cerrada, que sí usa colores.
- La opción de "evaluar grupo" en rúbricas solo se llega manteniendo presionado — poco visible, sobre todo en iPad sin ratón.
- Si una celda tiene varias señales a la vez (bloqueada + no cuenta + guardando), los iconos pequeños en la esquina pueden solaparse.

---

## 3. Diseño de las rúbricas
Archivos: `RubricsBuilderScreen.swift`, `RubricEvaluationView.swift`, `RubricBulkEvaluationSheet.swift`, `RubricsStyle.swift`, `AssignRubricToTabView.swift`, `StudentRubricInstrumentContent.swift`

### Cómo se construye una rúbrica

- Un editor con nombre grande arriba, clase y situación de aprendizaje asociadas, y 3 chips de plantilla rápida (Estándar / Binario / Numérico).
- Una tabla hecha a medida: columna de criterios a la izquierda, una columna por cada nivel de logro. Cada nivel tiene nombre, puntos (con un control de +/-) y botón de eliminar. Cada criterio tiene descripción, un control deslizante (slider) de peso, y por cada nivel un campo de texto para describir ese nivel.
- Se ve más "cruda" que el resto de la app: casi sin tarjetas, con líneas finas de borde, tipografía genérica.

### Cómo se ve al evaluar (uno por uno)

- Cabecera con un **anillo de progreso** dibujado a mano que muestra la nota actual en el centro.
- Debajo, cada criterio con sus niveles como píldoras (botones redondeados). Al elegir un nivel, la píldora se colorea.
- Un botón "i" aparte muestra la descripción completa de cada nivel.

### Cómo se ve al evaluar en grupo (varios alumnos a la vez)

- Una tabla grande: alumnos en filas, criterios en columnas. Cada celda tiene botones compactos de nivel (con atajos de teclado 1-5).
- Fila de cada alumno con avatar circular, punto de color (lesionado/pendiente/completo) y menú de acciones.
- Usa un estilo "vidrio esmerilado" (glassmorphism) que no aparece en ninguna otra pantalla de rúbricas.

### Lo que un diseñador probablemente querría revisar

- Conviven tres estilos visuales distintos en el mismo módulo: el editor (crudo), la evaluación individual (editorial, con anillo y píldoras) y la evaluación en grupo (vidrio esmerilado). Se sienten como tres apps distintas.
- El editor de rúbricas es la pantalla menos pulida de las tres, y es justo la que usan los profesores para crear el instrumento — probablemente merece subir de nivel visual.
- El control de puntos por nivel permite cualquier número del 0 al 20 sin avisar si eso rompe la coherencia con otros niveles de la misma rúbrica.
- En la evaluación en grupo, los nombres de nivel se cortan a 9 letras — nombres largos ("Excelente", "En proceso") casi siempre saldrán truncados.
- Hay tres formas distintas de ver la descripción completa de un nivel según la pantalla (mantener el ratón encima, botón "i", mantener presionado) — inconsistente entre evaluación individual y en grupo.

---

## Resumen para Claude Design

Los tres puntos en común más importantes para llevar a una conversación de diseño:

1. **Conviven varios lenguajes visuales** (editorial grueso, tabular denso, vidrio esmerilado) sin una decisión unificada — el propio código lo documenta como deuda pendiente.
2. **El menú de columna y el editor de rúbricas son las pantallas menos pulidas**, con controles nativos genéricos (TextField, Slider, Stepper) al lado de pantallas mucho más trabajadas (evaluación de rúbrica, grid).
3. **Hay funciones importantes escondidas detrás de gestos poco descubribles** (mantener presionado para evaluar en grupo, arrastrar para cambiar nota, hover para ver descripción) sin pistas visuales permanentes.
