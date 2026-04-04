# iOS App (SwiftUI) - Integración con Shared KMP

Objetivo: ejecutar la capa compartida KMP desde una app SwiftUI en macOS (simulador iOS).

## 1) Generar framework KMP

Desde `kmp/`:

- `./scripts/build_ios_framework.sh` (actualmente deja un mensaje porque este milestone está en modo desktop-first)

Cuando se reactiven targets iOS, la salida esperada será:

- `shared/build/bin/iosSimulatorArm64/debugFramework/shared.framework`

## 2) Crear app en Xcode

1. Crear proyecto iOS (`MiGestorKMPiOS`) con SwiftUI.
2. Añadir `shared.framework` en "Frameworks, Libraries, and Embedded Content".
3. En Build Settings, habilitar búsqueda del framework si no lo detecta automáticamente.

## 3) Conectar capa shared

- Inicializar `KmpContainer` usando el `createIosDriver()` del módulo `data`.
- Exponer adaptadores `ObservableObject` para consumir estados/flows de shared en SwiftUI.

## 4) Ejecución

- Ejecutar en simulador iPhone (Apple Silicon: arm64 simulator).
- Validar flujo mínimo: crear clase/alumno/evaluación/nota y leer cuaderno.

## Nota

El bootstrap visual inicial está en `SwiftUiBootstrap.swift` y sirve como punto de arranque para conectar ViewModels compartidos.
