# Plan técnico de animaciones — Cuaderno

Paridad iPadOS ↔ macOS. Todos los valores respetan `accessibilityReduceMotion` (fallback: `.opacity` con `easeInOut 0.15s`).

---

## 1. Rúbricas (apertura/cierre de celda expandible)

**Framework:** SwiftUI (`withAnimation` + `matchedGeometryEffect` para la celda que se expande a detalle).

| Fase | Curva | Valores |
|---|---|---|
| Abrir | `.spring` | `response: 0.38, dampingFraction: 0.82` |
| Cerrar | `.spring` | `response: 0.30, dampingFraction: 0.90` |
| Contenido interno (fade-in escalonado) | `.easeOut` | `duration: 0.20, delay: 0.05 × índice` (máx. 3 niveles) |

**iPadOS (táctil):**
- Gesto de cierre interactivo: `DragGesture` mapeado a progreso; al soltar, `spring(response: 0.30)` desde la velocidad del gesto (`initialVelocity`).
- Escala inicial de la celda al tocar: `scaleEffect(0.97)` con `easeOut 0.10s` (feedback de pulsación).

**macOS (puntero):**
- Sin scale de pulsación; en su lugar `hover`: fondo `easeInOut 0.12s`.
- Expansión con `NSCursor.pointingHand` en cabecera; sin gesto interactivo de cierre (clic en chevron).
- Chevron: rotación 90° con la misma spring de apertura, sincronizada.

---

## 2. Menús (contextuales y popovers de acción)

**Framework:** SwiftUI nativo (`Menu`, `contextMenu`) — **no animar manualmente**: el sistema aporta la animación correcta por plataforma. Solo se parametrizan menús custom (popover de calificación rápida).

Popover custom de calificación:

| Fase | Curva | Valores |
|---|---|---|
| Abrir | `.spring` | `response: 0.28, dampingFraction: 0.78` + `scaleEffect` desde `0.92`, ancla en el origen (`anchor` según arrowEdge) |
| Cerrar | `.easeIn` | `duration: 0.15`, `opacity` + `scale → 0.96` |

**iPadOS (táctil):**
- Presentación como `popover` (se adapta a sheet en compact: dejar la transición de sheet del sistema, no sobrescribir).
- Aparición anclada al dedo: `anchor: .bottom` si el toque está en mitad inferior.

**macOS (puntero):**
- Abrir más rápido: `response: 0.22` (expectativa de inmediatez con puntero).
- Cierre al perder foco (`onExitCommand` / clic fuera): fade puro `easeOut 0.12s`, sin scale.
- Ítems con highlight de hover instantáneo (0 ms entrada, `easeOut 0.10s` salida), estándar AppKit.

---

## 3. Inspector lateral

**Framework:** SwiftUI. En macOS usar `.inspector(isPresented:)` (animación del sistema). En iPadOS, panel custom con `offset` + `frame` animados.

iPadOS (panel custom, ancho 320 pt):

| Fase | Curva | Valores |
|---|---|---|
| Abrir | `.spring` | `response: 0.42, dampingFraction: 0.86` — desliza desde trailing (`offset x: 320 → 0`) |
| Cerrar | `.spring` | `response: 0.35, dampingFraction: 0.92` |
| Contenido principal | misma spring, animando `padding(.trailing)` para reflow simultáneo (nunca dos animaciones separadas) |
| Dimming (solo compact/overlay) | `easeInOut 0.25s`, opacidad `0 → 0.2` |

**iPadOS (táctil):**
- Cierre por swipe: `DragGesture` interactivo con `rubber-banding` (resistencia 0.55 si arrastra en dirección de apertura estando abierto).
- Umbral de cierre: 35 % del ancho **o** velocidad > 300 pt/s.

**macOS (puntero):**
- `.inspector` nativo: no fijar timing propio; solo `withAnimation(nil)` prohibido — dejar el default de AppKit (~0.25 s ease-in-out) para coherencia con Finder/Xcode.
- Toggle vía toolbar y `⌥⌘I`; el contenido del inspector hace fade-in `easeOut 0.18s` tras completarse el slide (evita text-jitter durante el resize).
- Divisor redimensionable sin animación (seguimiento directo del puntero).

---

## Reglas transversales

- Una sola `withAnimation` por transacción; nunca springs anidadas con timings distintos sobre la misma vista.
- Gestos interactivos (solo iPadOS) transfieren velocidad al spring de salida.
- `reduceMotion`: sustituir desplazamientos por cross-fade `0.15s`; conservar cambios de layout sin animar.
