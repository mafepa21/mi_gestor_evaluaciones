---
name: swiftui-native-feature
description: Implementa una feature nativa Apple en SwiftUI de forma idiomatica y compatible con la arquitectura SwiftUI + KMP del proyecto.
version: 1.0.0
---

# swiftui-native-feature

## Rol
Eres un especialista en APIs nativas Apple. Implementas UNA feature nativa
de forma idiomatica, sin romper la arquitectura SwiftUI+KMP existente.

## Features nativas disponibles en este proyecto
- **Keyboard shortcuts:** `.keyboardShortcut("n", modifiers: .command)`
- **Toolbar nativa macOS:** `.toolbar { ToolbarItem(placement: .primaryAction) { ... } }`
- **Drag & drop:** `.draggable()` / `.dropDestination(for:)` (iOS 16+/macOS 13+)
- **Menu bar macOS:** `MenuBarExtra` en `MiGestorKMPMacApp.swift`
- **Context menus:** `.contextMenu { Button(...) }`
- **Focus management:** `@FocusState` para navegacion teclado
- **Quick Look / ShareSheet:** `ShareLink` nativo (iOS 16+)
- **Spotlight:** `NSUserActivity` con `eligibleForSearch = true`

## Donde anadir cada cosa
| Feature | Archivo |
|---|---|
| Shortcuts macOS globales | `kmp/iosApp/MacApp/MacCommandCenterCoordinator.swift` |
| Registro de features Mac | `kmp/iosApp/MacApp/MacFeatureRegistry.swift` |
| Toolbar / menu macOS | `kmp/iosApp/MacApp/MacRootView.swift` |
| Toolbar iOS | View concreta con `.toolbar {}` |
| Shared iOS+macOS | `kmp/iosApp/AppleShared/` |

## Reglas
- Usar `#if os(macOS)` para codigo exclusivo Mac, no `UIDevice.current`.
- No duplicar logica ya existente en `MacCommandCenterCoordinator.swift`.
- No tocar `KmpBridge.swift`.
- Minimo iOS 16 / macOS 13 como target.

## Salida esperada
Codigo Swift de la feature + lista de shortcuts/capacidades anadidas + archivos modificados.
