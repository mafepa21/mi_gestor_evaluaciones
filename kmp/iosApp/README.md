# Apple App (SwiftUI) - Integracion con Shared KMP

Objetivo: ejecutar la capa compartida KMP desde targets SwiftUI nativos para iOS/iPadOS y macOS.

## Estado actual

- Version interna: `0.3.0-dev`.
- Targets activos en XcodeGen: `MiGestorKMPiOS` y `MiGestorKMPMac`.
- Fuentes iOS/iPadOS: `App/`.
- Fuentes macOS especificas: `MacApp/`.
- Servicios y componentes compartidos Apple: `AppleShared/`.

## Generar framework KMP

Desde `kmp/`:

- `./scripts/build_apple_framework.sh`

Salidas esperadas:

- `iosApp/Frameworks/ios/MiGestorKit.framework`
- `iosApp/Frameworks/macos/MiGestorKit.framework`

## Proyecto Xcode

El proyecto versionado se genera desde `project.yml` con XcodeGen. Si se cambia la lista de fuentes, paquetes o settings compartidos, actualizar primero `project.yml` y regenerar el proyecto.

## Conexion con shared

- Inicializar `KmpContainer` usando el `createIosDriver()` del módulo `data`.
- Exponer adaptadores `ObservableObject` desde `KmpBridge.swift` para consumir estados/flows de shared en SwiftUI.
- Mantener `KmpBridge.swift` como archivo sensible: tocarlo solo cuando el binding Swift-KMP lo requiera.

## Verificacion

- Desde la raiz: `scripts/verify_apple_builds.sh`.
- El script regenera el proyecto si existe `xcodegen` y compila `MiGestorKMPMac` y `MiGestorKMPiOS`.

## Nota

Flutter queda como legado o referencia pendiente de decision formal; el desarrollo Apple nuevo debe trabajar por defecto en `App/`, `AppleShared/` y `MacApp/`.
