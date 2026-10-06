# Ámbito: Dashboard

## Estado actual

- Despacho en 3 franjas: AHORA, ATENCIÓN y CONTEXTO (plegado). Modo Clase aparte. iPad, iPhone y Mac comparten vistas.
- Mejoras HIG pendientes (auditoría 2026-10-06): no atenuar el texto con error de carga, cabecera compacta en iPhone, explicar el botón principal desactivado, bordes más visibles en iOS <26, severidad visible en Atención, trait del banner de error.

## Terreno de juego

- `kmp/iosApp/App/Dashboard*.swift` (`DashboardView`, `DashboardDispatchView`, `DashboardHeaderView`, `DashboardInspectorContent`, `DashboardPresentation`, `DashboardStateViews`, `DashboardStyle`, `DashboardClassroomView`, `DashboardTimeProgressBar`, `DashboardSharedBlocks`).
- Mac: `kmp/iosApp/MacApp/MacDashboardView.swift`.
- Maqueta: `docs/mockups/dashboard/mockup/index.html`.

## Trampas

- Tokens visuales en `DashboardStyle.swift`; no meter colores ni opacidades sueltas en las vistas.
- Números grandes con `@ScaledMetric`, no `.font(.system(size:))` fijo. Mínimo 11 pt.
- Tope de Dynamic Type en `DashboardView.body`; en tamaños de accesibilidad la vista pasa a una columna.
- `xcodebuild` reescribe `*.xcscheme`: restaurar antes de commitear.
