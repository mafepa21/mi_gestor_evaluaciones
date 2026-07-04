# Blueprint: Refactorización pantalla Asistencia (macOS)

Archivos objetivo: `MacAttendanceView.swift`, `MacRootView.swift`, `MacAttendanceDayRow.swift`.
Evidencia (capturas): título "Asistencia" y tarjeta "Presentes" recortados bajo el sidebar en modo Día; toolbar con 6 controles simultáneos; alumnos presentes ocupan el 100% del roster.

---

## 1. Resolución de Layout

**Causa**: el contenido usa `padding(MacAppStyle.pagePadding)` fijo dentro de `HSplitView`, pero el sidebar colapsable se superpone (overlay) en lugar de comprimir; el `frame(minWidth: 640)` fuerza clipping por la izquierda.

**Estructura corregida**:
```
NavigationSplitView (no HSplitView + sidebar overlay)
└── Detail
    └── VStack
        ├── header               .padding(.horizontal, pagePadding)
        ├── controlStrip          ídem
        └── content              .frame(maxWidth: .infinity)
```
- Sustituir la superposición del sidebar por `NavigationSplitView(columnVisibility:)`: el detalle se recomprime, nunca queda debajo.
- `safeAreaPadding(.leading)` en el pane principal; eliminar `minWidth: 640` rígido → `layoutPriority(1)` + `minWidth: 520`.
- Métricas: `ScrollView(.horizontal)` con `scrollClipDisabled(false)` para que las cards se compriman con `ViewThatFits` en vez de recortarse.
- Inspector: mantener `maxWidth: 430`, pero colapsarlo automáticamente bajo 1100 pt de ancho de ventana (`onGeometryChange`).

## 2. Flujo One-tap

**Toolbar reducida a 3 elementos visibles** (el resto migra a `Menu` "Acciones"):

| Posición | Control | Justificación |
|---|---|---|
| 1 | Segmented Día/Historial/Cursos | cambio de modo |
| 2 | Date stepper `‹ Hoy ›` | un clic por día; clic en "Hoy" resetea |
| 3 | **CTA "Pasar lista"** prominente | acción primaria única |

- "Pasar lista" = `markAllPresent()` con default optimista: un solo clic cierra la sesión estándar (30 presentes).
- Selector de curso, sesión y filtros → toolbar de ventana (`.toolbar`), no en el cuerpo.
- Atajos ya implementados (mantener): ↑↓ navega, `P/A/R/J/M/E` marca y avanza, `⌘⇧P` todos presentes.
- Coste objetivo: **taps = excepciones + 1**.

## 3. UI por Excepción

**Panel "Excepciones de hoy"** sustituye al roster completo como vista por defecto del modo Día:

- **Visible**: solo alumnos con estado ≠ PRESENTE (ausentes, retrasos, justificadas, sin material, lesión) e incidencias abiertas, con `student.fullName` completo, hora del registro y motivo.
- **Oculto**: presentes colapsados en una única fila-resumen: `"✓ 27 presentes"` — expandible con disclosure (`chevron`) para acceso puntual.
- Orden del panel: Ausencias (rojo) → Retrasos (ámbar) → Incidencias (naranja) → resto.
- Cada fila de excepción: swipe/hover actions "Justificar", "Nota", "Incidencia".
- Fila de alerta reutiliza `criticalAlerts` existente (≥3 ausencias/7 días, lesión activa) fijada arriba, nunca scrolleable.
- Estado vacío: `"Todos presentes"` con checkmark grande — cero excepciones = cero ruido.

## 4. Core Animation & State

**Principio**: el dato viejo nunca desaparece antes de llegar el nuevo (sin spinners de página completa).

| Transición | Parámetros |
|---|---|
| Cambio de estado en fila | `.spring(response: 0.28, dampingFraction: 0.86)` sobre el pill de estado |
| Recarga de roster (cambio fecha/curso) | crossfade `.opacity` 0.18 s `easeOut` + `redacted(reason: .placeholder)` solo si > 300 ms |
| Contadores métricas | `contentTransition(.numericText())` — nada de reconstruir la card |
| Aparición/cierre inspector | ya cubierto por `uiFeatureFlags.inspectorAnimation` — reutilizar |
| Fila de alertas | `.transition(.move(edge: .top).combined(with: .opacity))`, `animation(.snappy(duration: 0.22))` |

**Estado**:
- `isLoading` deja de ocultar contenido: pasa a indicador de 2 pt bajo el control strip (`ProgressView.linear`).
- Escrituras ya optimistas (`applyLocalAttendanceStatus` + rollback) — extender el mismo patrón a `repeatPattern()` (hoy recarga completa).
- Debounce de `reloadClassOverviews` (500 ms, ya existe) — subir a cancelación por `task(id:)` para evitar refrescos apilados.
- Regla dura: ninguna interacción del profesor debe esperar un round-trip para reflejarse en pantalla.
