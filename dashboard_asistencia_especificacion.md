# Especificación: Dashboard de Asistencia (iPadOS / macOS)

Pantalla objetivo: `AttendanceWorkspaceView` (compartida) + adaptaciones en `MacRootView`.
Referencia HIG: layout adaptativo, toolbar unificada, controles nativos por plataforma.

---

## 1. Jerarquía de Datos (Above the fold)

Orden vertical estricto, sin scroll para el nivel 1:

| Nivel | Contenido | Componente |
|---|---|---|
| 1 | **Sesión activa**: grupo + hora actual detectados por horario, fecha, botón primario "Pasar lista" | Header card fija |
| 1 | **Alertas críticas**: ausencias reiteradas (≥3 en 7 días), alumnos lesionados/exentos hoy | Badge row bajo el header |
| 2 | **Resumen del día**: presentes / ausentes / retrasos (contadores `overviewMiniStat`) | Stat strip horizontal |
| 3 | **Listado de alumnos** con estado editable | Roster (grid/table según plataforma) |
| 4 | Historial semanal y notas | Sección colapsada por defecto |

Reglas:
- Nunca mostrar el selector de clase como primer elemento: preseleccionar por horario; selector relegado a toolbar.
- Estados con color semántico + símbolo SF (no solo color): `checkmark.circle` presente, `xmark.circle` ausente, `clock` retraso, `cross.case` lesionado.

## 2. Arquitectura de Componentes

### Comunes (SwiftUI compartido)
- `AttendanceHeaderCard`: clase activa, fecha, CTA primario.
- `AttendanceStatBar`: 3–4 contadores tappables que filtran el roster.
- `StudentRosterCell`: avatar/iniciales, nombre, control de estado, indicador de nota/incidencia.
- `QuickActionsBar`: "Todos presentes" (`markAllPresent`), "Repetir patrón" (`repeatPattern`).

### iPadOS (táctil)
- **Layout**: `NavigationSplitView` — sidebar de clases (columna 1), roster (detalle).
- **Roster**: `LazyVGrid` adaptativo (`minimum: 160`), celdas grandes; objetivo táctil ≥ 44×44 pt.
- **Cambio de estado**: tap = ciclo Presente→Ausente→Retraso; long-press = menú contextual (lesionado, nota, incidencia).
- **Swipe** en celda: derecha = presente, izquierda = ausente.
- **Toolbar**: `DatePicker` compacto + selector de clase como `Menu`.
- Soporte Apple Pencil hover: preview del menú de estados.

### macOS (puntero/teclado)
- **Layout**: 3 columnas — sidebar de clases, `Table` central, inspector opcional (historial/notas del alumno seleccionado).
- **Roster**: `Table` con columnas Nombre / Estado (segmented o popup) / Nota / Racha; ordenable por columna.
- **Teclado**: navegación con ↑↓; teclas `P`/`A`/`R`/`L` cambian estado de la fila seleccionada y avanzan a la siguiente; `⌘⏎` guarda y cierra; `⌘⇧P` todos presentes.
- **Menú contextual** (clic derecho): estados + incidencia + nota.
- **Toolbar** nativa: date navigator (`chevron.left/right` + hoy), buscador (`⌘F`) que filtra la tabla.
- Densidad: filas 28–32 pt, sin celdas tipo tarjeta.

## 3. Flujo de Acción: pasar lista

Objetivo: ≤ 15 s por grupo de 30 alumnos.

1. **Entrada**: al abrir en horario lectivo, la clase actual ya está seleccionada y el roster cargado (cero taps de configuración).
2. **Default optimista**: todos inician como "Presente" (estado provisional, no persistido). El profesor solo marca excepciones.
3. **Marcado por excepción**:
   - iPad: tap/swipe solo sobre ausentes y retrasos.
   - Mac: teclas `A`/`R` sobre filas navegadas con ↑↓.
4. **Confirmación**: botón "Confirmar asistencia" persiste el lote (`updateAttendance` en batch); haptic (iPad) / sonido sutil (Mac); el header pasa a estado "Lista pasada ✓" con hora.
5. **Atajos de repetición**: "Repetir patrón" aplica la última sesión del mismo grupo; útil en ausencias prolongadas.
6. **Deshacer**: `⌘Z` / botón Undo durante 30 s tras confirmar.

Métrica de éxito: taps por sesión = nº de excepciones + 1 (confirmar).
