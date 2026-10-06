# Ámbito: Dashboard

## Estado actual

- Dashboard iOS/iPadOS en `kmp/iosApp/App/Dashboard*.swift`; el de Mac es aparte (`MacApp/MacDashboardView.swift`).
- Letra adaptable (Dynamic Type) con tope AX2 desde `codex/dashboard-dynamic-type`.

## Terreno de juego

- `DashboardView.swift` (grande: cambiar por secciones), `DashboardSharedBlocks.swift`, `DashboardClassroomView.swift`, `DashboardCompactHeroStrip.swift`, `DashboardTimeProgressBar.swift`, `DashboardTypeStyle.swift`.
- Compartido: `AppleShared/DashboardProactiveInsight.swift`, `AppleShared/DashboardRecommendations.swift`.

## Trampas

- Texto: usar `.dashboardFont(size:weight:design:)`, no `.font(.system(size:))`. Mínimo 11 pt.
- Iconos con caja cuadrada fija: `.dashboardIconFrame(_:)`, no `.frame(width:height:)`.
- Los skeletons de carga mantienen tamaño fijo a propósito: son decoración.
- `MacDashboardView.swift` no pasa por estos modificadores.
