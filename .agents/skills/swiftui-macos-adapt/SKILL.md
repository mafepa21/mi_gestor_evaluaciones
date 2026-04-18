---
name: swiftui-macos-adapt
description: Adapta una View existente al layout y convenciones de macOS sin duplicar codigo innecesario ni rehacer la navegacion completa.
version: 1.0.0
---

# swiftui-macos-adapt

## Rol
Adaptas UNA View de iOS para que funcione correctamente en ventana ancha macOS,
respetando las convenciones HIG Mac sin duplicar codigo innecesariamente.

## Patrones de adaptacion para este proyecto
- **Sidebar:** `NavigationSplitView` con `sidebar` / `detail` / `content`
- **Inspector panel:** `.inspector(isPresented:) { ... }` (macOS 14+)
- **Ventana ancha:** sustituir `VStack` principal por `HStack` con panel lateral fijo
- **Tamano minimo ventana:** `.frame(minWidth: 900, minHeight: 600)` en `MacRootView`
- **Density:** en macOS usar `.controlSize(.regular)`, en iOS `.controlSize(.large)`
- **Hover states:** `.onHover { isHovered in ... }` solo con `#if os(macOS)`

## Condicionales de plataforma correctos
```swift
// Correcto
#if os(macOS)
    MacSpecificView()
#else
    IOSSpecificView()
#endif

// Tambien correcto para tamanos
@Environment(\.horizontalSizeClass) var sizeClass
```

## Archivos de referencia
- Layout macOS raiz: `kmp/iosApp/MacApp/MacRootView.swift`
- Sesion Mac: `kmp/iosApp/MacApp/MacAppSessionController.swift`
- Compatibilidad: `kmp/iosApp/AppleShared/AppleViewCompatibility.swift`

## Limites
- No rehagas la navegacion completa - adapta solo la View pedida.
- No toques `KmpBridge.swift`.
- No alteres `EvaluationDesign.swift`.

## Salida esperada
Diff de la View adaptada + captura mental del layout resultante en <=3 lineas.
