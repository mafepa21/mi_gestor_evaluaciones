# Plan de corrección: bloqueo de navegación y reinicio tras borrado (2026-07-25)

## Contexto

Reporte del usuario sobre la app macOS en ejecución (captura adjunta): al entrar en Ajustes →
Zona de Riesgo, el resto de la navegación deja de funcionar (la barra lateral principal
"Hoy/Cursos/Cuaderno/.../Sync LAN/Ajustes" cambia de selección — en la captura "Sync LAN" está
resaltado — pero el panel de detalle se queda congelado mostrando "Zona de Riesgo"). Además,
"Borrar todos los datos" no parece borrar nada, y pide reiniciar la app a mano.

## Bug 1 — Navegación bloqueada al entrar en Zona de Riesgo (macOS)

**Causa**: `MacSettingsView.swift` (macOS, `kmp/iosApp/MacApp/MacSettingsView.swift`) renderiza
su contenido de detalle en un `HStack { List(...) ; Divider() ; ScrollView { detailViewForRoute
(...) } }`, **sin ningún `NavigationStack`**. `DataSecuritySettingsView.swift`
(`AppleShared/`, compartido con iOS) navega a `SettingsDangerZoneView` con
`NavigationLink { SettingsDangerZoneView(...) } label: { ... }` — esa API necesita un
`NavigationStack` ancestro para funcionar con una identidad de navegación propia.

En iOS/iPad (`SettingsWorkspaceView.swift`) sí hay `NavigationStack` (`iphoneLayout`) o
`NavigationSplitView` (`ipadLayout`), así que ahí el push funciona con normalidad. En macOS, al
faltar el `NavigationStack`, SwiftUI resuelve el push contra un contexto de navegación implícito
ligado a la ventana en vez de al árbol de vistas de `MacSettingsView` — por eso el título
"Zona de Riesgo" sí se pinta (algo está renderizando `.navigationTitle`), pero cuando
`MacRootView` cambia `selectedFeature` (y por tanto recrea el subárbol completo vía `.id
(selectedFeature)`), el push huérfano sobrevive y sigue tapando el panel de detalle.

**Fix**: envolver el contenido de detalle de `MacSettingsView` en su propio `NavigationStack`,
para que el push de `SettingsDangerZoneView` quede ligado a la identidad de esa vista concreta
y se destruya limpiamente cuando `MacRootView` la reemplaza por otra `feature`.

## Bug 2 — El borrado no parece surtir efecto sin reinicio manual

**No es un bug de borrado en sí**: `wipeAllData()` (`SettingsDangerZoneView.swift`) sí borra el
archivo SQLite (+ `-wal`/`-shm`), la carpeta de backups y los adjuntos del disco de inmediato.
Lo que ocurre es que el proceso en ejecución sigue teniendo abierta la conexión SQLite anterior
y el estado en memoria (`KmpBridge` con sus `@Published`), así que la UI sigue mostrando datos
"vivos" hasta que se reinicia el proceso — de ahí que el usuario vea que "no se borra nada". El
propio código ya lo anticipaba (`needsRestart` + `RestartRequiredOverlay`, que bloquea la UI con
un aviso de reinicio manual), pero el usuario pide que el reinicio sea automático.

**Fix (solo macOS — ver limitación)**: tras completar `wipeAllData()`, relanzar
automáticamente la app (`NSWorkspace.openApplication` con una nueva instancia + `NSApp.
terminate`) con un pequeño retardo para que el usuario vea el aviso antes del relanzamiento.
`RestartRequiredOverlay` cambia su copy en macOS a "Reiniciando…" con `ProgressView`.

**Limitación explícita, no evitable**: iOS/iPadOS no permite que una app se autorelance a sí
misma (sandboxing de Apple, ninguna API pública lo permite; es motivo de rechazo en App Review).
En iOS se mantiene el aviso actual de reinicio manual, sin cambios de comportamiento — solo
cambia en macOS, que es la plataforma donde ocurrió el reporte.

## Archivos que se van a tocar

- `kmp/iosApp/MacApp/MacSettingsView.swift` (Bug 1)
- `kmp/iosApp/AppleShared/SettingsDangerZoneView.swift` (Bug 2, relanzamiento macOS)
- `kmp/iosApp/AppleShared/AppleAppRootView.swift` (Bug 2, copy del overlay)
- `docs/CHANGELOG.md`

## Orden de trabajo y commits

1. `fix(macos): reiniciar la navegación de Ajustes en un NavigationStack propio` (Bug 1)
2. `feat(macos): reiniciar la app automáticamente tras borrar todos los datos` (Bug 2)

## Verificación exigida

- Build real macOS (`xcodebuild -scheme MiGestorKMPMac build`).
- No se prueba interactivamente en esta tarea (sin sesión de simulador/macOS abierta): el
  bug de navegación se corrige por causa raíz identificada en el código (ausencia de
  `NavigationStack`), pero no se ha podido reproducir clic a clic ni confirmar visualmente tras
  el fix. Pendiente de que el usuario confirme en su próxima sesión con la app.
