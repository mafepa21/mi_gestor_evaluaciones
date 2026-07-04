# Arquitectura del Dashboard Docente — Cuaderno (iPadOS · macOS)

## 1. Jerarquía de datos

Orden de lectura descendente. Nivel 1 responde "¿qué requiere mi atención ahora?"; nada por debajo compite visualmente con él.

| Nivel | Bloque | Contenido | Justificación |
|---|---|---|---|
| 1 | **Hoy** | Próxima sesión (grupo, aula, hora, cuenta atrás), sesiones restantes del día | Decisión inmediata; el 80 % de las visitas al dashboard buscan esto |
| 2 | **Alertas** | Asistencia anómala (≥3 faltas consecutivas), evaluaciones sin cerrar con fecha límite < 7 días, alumnos sin calificar en la unidad activa | Accionable y con coste de ignorarlo; cada alerta enlaza a su resolución en 1 tap/clic |
| 3 | **KPIs** | Pendientes de corrección, alertas activas, sesiones de hoy, progreso de programación (% sesiones impartidas vs. planificadas) | Contexto cuantitativo; nunca más de 4 cifras |
| 4 | **Accesos rápidos** | Pasar lista (sesión en curso), evaluar con rúbrica, planner semanal, último grupo abierto | Verbos, no sustantivos: cada acceso inicia una tarea |
| 5 | **Insight proactivo** | Una única tarjeta (`DashboardProactiveInsightCard`): tendencia detectada o sugerencia de planificación | Opcional y descartable; jamás dos a la vez |

Reglas:
- Máximo 5 bloques visibles. Sin scroll para los niveles 1–3 en iPad apaisado y ventana macOS ≥ 1000 pt.
- Estado vacío por bloque con acción constructiva ("Sin alertas — revisa la evaluación de 2ºB"), nunca bloque oculto en silencio.
- Datos con antigüedad > 5 min se refrescan al `scenePhase == .active` / `NSWindow.didBecomeKey`.

## 2. Minimalismo funcional y UI premium

### Tipografía (San Francisco, solo Dynamic Type)
- Título de bloque: `.title3.weight(.semibold)`.
- Cifra de KPI: `.system(.largeTitle, design: .rounded).weight(.bold)` + `monospacedDigit()`.
- Etiqueta de KPI: `.footnote` en `.secondary`, mayúscula inicial únicamente.
- Cuerpo/alertas: `.body`; metadatos: `.caption` `.secondary`.
- Prohibido: tamaños fijos en puntos, más de 3 pesos por pantalla, itálicas.

### Espacio y capas
- Retícula de 8 pt. Padding interno de tarjeta: `EvaluationDesign.cardSpacing` (única fuente de verdad; no literales).
- Separación entre bloques ≥ 24 pt; el espacio en blanco jerarquiza, no los divisores (`Divider` prohibido entre bloques).
- Tarjetas: `appCardBackground` para contenido primario, `appMutedCardBackground` para secundario; radio continuo (`.rect(cornerRadius: 12, style: .continuous)`); sin sombras en macOS, sombra sutil única (y ≤ 2 pt) en iPadOS.

### Color y contraste
- Un solo color de acento (el del sistema/app). Color semántico solo en alertas: `.red` crítico, `.orange` aviso — nunca decorativo.
- Texto secundario siempre `Color.secondary`, jamás grises hardcodeados. Contraste mínimo 4.5:1; verificar en claro, oscuro y "Aumentar contraste".

### Omisión (qué se elimina)
- Sin saludos ("Hola, Mario"), sin fecha redundante con la barra del sistema, sin iconos decorativos junto a cifras.
- Sin gráficas en el dashboard: una cifra + tendencia (`▲ 3` en `.caption`) sustituye a cualquier sparkline.
- Sin botón "Ver todo" si la lista completa cabe; sin badges numéricos > 99 (mostrar "99+").
- Toda animación con `Motion`-token del plan de animaciones; respeta `accessibilityReduceMotion`.

## 3. Paridad y divergencia de plataformas

### Común (paridad)
- Mismo modelo de datos (`DashboardSnapshot`), misma jerarquía de bloques, mismos textos.
- Layout con `ViewThatFits` + breakpoints por ancho de contenido, no por plataforma: 1 columna < 600 pt, 2 columnas 600–999 pt, 3 columnas ≥ 1000 pt (`LazyVGrid` existente).

### iPadOS — optimizar el tacto
- Objetivo táctil mínimo 44×44 pt; tarjeta completa como área de toque, no solo su título.
- KPIs y accesos rápidos como tarjetas grandes; `contextMenu` con acciones secundarias (pull-to-refresh para recarga).
- Swipe en filas de alerta: resolver / posponer.
- Soporte de multitarea: en Split View compacto colapsa a 1 columna sin pérdida de bloques.
- Pointer effect (`.hoverEffect(.highlight)`) para trackpad/Pencil hover en M-series.

### macOS — optimizar puntero y teclado
- Densidad mayor: paddings ×0.75, filas de alerta compactas tipo lista, `controlSize(.small)` en controles secundarios.
- Hover revela acciones inline (resolver alerta, abrir grupo) que en iPad viven en swipe/contextMenu.
- Atajos: `⌘1` dashboard, `⌘R` refrescar, `⌘⇧L` pasar lista, `↑/↓ + ⏎` para navegar alertas; todos declarados en menú de app (descubribles).
- Clic derecho = mismo `contextMenu` que iPad. Doble clic en tarjeta de grupo abre su detalle en la ventana (no sheet).
- Sin gestos exclusivos: toda acción táctil de iPad tiene equivalente de menú o atajo en Mac, y viceversa.

### Divergencias explícitas prohibidas
- No duplicar vistas por plataforma salvo contenedor raíz (`MacRootView` ya existente); divergencia solo vía modificadores condicionales y tokens de densidad.
