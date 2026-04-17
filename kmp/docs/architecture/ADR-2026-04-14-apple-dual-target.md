# ADR-2026-04-14: Contenedor Apple dual para iOS y macOS

## Estado
Aprobado

## Contexto
La base actual mezcla:

- una app iOS/iPad nativa en `kmp/iosApp`
- una app desktop Compose en `kmp/desktopApp`
- lógica compartida en `kmp/shared` y `kmp/data`

La migración a macOS nativo necesita reducir duplicación Apple y evitar que SwiftUI dependa de detalles internos de Kotlin.

## Decisión

- `kmp/iosApp` pasa a ser el contenedor Apple con dos targets: iOS y macOS.
- `MiGestorKit` se exporta para `iosArm64`, `iosSimulatorArm64`, `macosArm64` y `macosX64`.
- `KmpBridge` queda como bridge Apple compartido y se inicializa mediante `AppleBridgeBootstrap`.
- La UI macOS se construye en SwiftUI nativo dentro de `kmp/iosApp/MacApp`.
- Las reglas, persistencia y sync siguen viviendo en `kmp/shared` y `kmp/data`.

## Consecuencias

- La shell macOS puede crecer por verticales sin depender de Compose Desktop.
- El proyecto Apple comparte bridge, build script y framework path.
- Las funcionalidades desktop-only se migran explícitamente a servicios Apple/KMP, no a vistas Compose incrustadas.
