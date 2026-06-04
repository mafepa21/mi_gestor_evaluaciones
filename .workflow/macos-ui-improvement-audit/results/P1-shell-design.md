# P1 Shell Design

## Scope

Files inspected: `MacRootView.swift`, `MacDashboardView.swift`, `MacAppStyle.swift`.

## Findings

1. Shell foundation is strong: `MacRootView` uses `NavigationSplitView` plus native `.inspector`, which is the right macOS pattern for a daily work app (`MacRootView.swift:83-95`).
2. Feature switching is abrupt. `featureContent(for:)` swaps entire module bodies without a contextual transition, while only transient banners are animated (`MacRootView.swift:86-104`). A subtle opacity or content transition on the detail root would reduce disorientation when jumping between dashboard, attendance, notebook, and rubrics.
3. The dashboard has a clear “Hoy” concept, but its title is visually modest and the hero competes with three right-column cards on wide screens (`MacDashboardView.swift:104-132`). This risks failing the “one dominant focus” rule on large displays.
4. The notebook toolbar is dense and mixes primary commands, search, status, navigation, inspector visibility, and advanced actions in one group (`MacRootView.swift:331-455`). It is functional but visually heavy for daily use.
5. `MacAppStyle` centralizes page/card tokens, but most macOS surfaces default to bordered cards. For dashboard and module pages, repeated border boxes can make the app feel more web-dashboard than native desktop.

## Recommended Improvements

- Add a small `MacFeatureContentTransition` pattern for module switches: fade only the detail content, not the whole split view, and avoid sliding large data grids.
- Make dashboard “Ahora” the clear visual anchor: slightly larger hero typography or stronger layout priority, while reducing the right column card emphasis.
- Split notebook toolbar into primary visible commands and compact “Más” groups by task: class/view, create/edit, inspect/search, secondary actions.
- Use borderless or lower-chrome sections for passive dashboard status cards; reserve bordered cards for interactive repeated items.

## Risk

Avoid broad root-shell redesign. The current native structure is correct; improvements should tune hierarchy and motion rather than replace the shell.
