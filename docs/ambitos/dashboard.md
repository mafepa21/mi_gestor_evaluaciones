# Ámbito: Dashboard

## Estado actual

- Despacho en 3 franjas: AHORA, ATENCIÓN y CONTEXTO (plegado). Modo Clase aparte. iPad, iPhone y Mac comparten vistas.
- Mejoras HIG de la auditoría 2026-10-06 cerradas (`codex/ui-legible`): contenido sin atenuar con error de carga, cabecera `title2` en iPhone, motivo visible del botón principal desactivado, borde opaco del cristal en iOS/macOS <26, prioridad escrita en Atención y banner de error como cabecera/resumen para VoiceOver.

## Terreno de juego

- `kmp/iosApp/App/Dashboard*.swift` (`DashboardView`, `DashboardDispatchView`, `DashboardHeaderView`, `DashboardInspectorContent`, `DashboardPresentation`, `DashboardStateViews`, `DashboardStyle`, `DashboardClassroomView`, `DashboardTimeProgressBar`, `DashboardSharedBlocks`).
- Mac: `kmp/iosApp/MacApp/MacDashboardView.swift`.
- Maqueta: `docs/mockups/dashboard/mockup/index.html`.

## Trampas

- Bordes y separadores: `DashboardStyle.separator`, nunca `Color.primary.opacity(<0.1)`. Con contraste alto, `strongSeparator`; cristal antiguo (<26), `legacyControlBorder`; esqueleto, `skeletonFill`; hover Mac, `hoverFill`. En `Dashboard*` no queda ningún `.primary.opacity`: no reintroducirlo.
- Texto blanco sobre acento: fondo `DashboardStyle.accentBadgeFill`, no `DashboardStyle.accent` (en oscuro solo llega a 3,6:1).
- Con error de carga no se baja la opacidad ni la saturación del contenido: el aviso de error ya avisa y la severidad de Atención debe seguir en color.
- La barra real de iPhone/iPad es `IOSContextualToolbar` en `IOSRootView.swift` (y la fila `IOSGlobalContextRow`). `AppWorkspaceShell` en `IPadWorkspaceShell.swift` no es la raíz en iOS: su «Acción principal» no se ve.
- Modo, snapshot y estado de sync llegan a la barra por `WorkspaceLayoutState.configureDashboardToolbar`; si se añade un dato nuevo, meterlo también en `toolbarStateKey` o no se refresca.
- El modo se comparte por `@AppStorage("dashboard_mode_preference")` entre la vista y las barras.

- Tokens visuales en `DashboardStyle.swift`; no meter colores ni opacidades sueltas en las vistas.
- Números grandes con `@ScaledMetric`, no `.font(.system(size:))` fijo. Mínimo 11 pt.
- Prioridad en Atención: `DashboardAttentionItem.priority` (3 alta, 2 media) sale de `priorityRank`. Solo la alta tiene línea propia con icono; el texto va en primario (rojo pequeño no llega a 4,5:1). Todo origen nuevo de la cola debe pasar `priority`.
- Si el botón principal de AHORA se desactiva, el motivo va escrito debajo (`DashboardNowCard.primaryDisabledReason`), no solo en VoiceOver.
- Tope de Dynamic Type en `DashboardView.body`; en tamaños de accesibilidad la vista pasa a una columna.
- `xcodebuild` reescribe `*.xcscheme`: restaurar antes de commitear.
