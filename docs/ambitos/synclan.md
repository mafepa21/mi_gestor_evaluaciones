# Ámbito: Sync LAN (iPad ↔ Mac)

## Estado actual

- Fase 1 de «siempre al día» (`codex/synclan-inmediato-f1`): envío garantizado al pasar a segundo plano en iPad, aviso «Poniéndose al día…» / «Sin conexión» en el indicador y recarga automática de las pantallas que cargan sus propios datos.
- Pendiente Fase 2: auditoría de rutas de escritura sin `enqueueLocalChange` y entidades que el Mac no sabe aplicar. Pendiente Fase 3: helper vivo con la app del Mac cerrada y refresco en segundo plano en iPad.

## Terreno de juego

- Apple: `kmp/iosApp/App/Bridge/KmpBridge+SyncLAN.swift` (ciclo de vida, `syncNow`, aplicar cambios, `LanSyncRefreshPlan`), `LanSyncClient.swift`, `AppleShared/SyncEventListener.swift`, `App/SyncStatusBadge.swift`, `App/LanSyncReloadModifier.swift`.
- Mac helper: `kmp/commandCenterHelper/`, `kmp/data/src/desktopMain/.../sync/LocalSyncServer.kt`, `MacApp/MacCommandCenterCoordinator.swift`.
- Kotlin: `kmp/data/src/commonMain/kotlin/com/migestor/data/sync/SqlDelightSyncAdapter.kt` (lo que el Mac exporta y aplica).
- Tests: `kmp/iosApp/PlannerTests/PlannerMonthGridTests.swift` (refresco y badge), `kmp/data/src/desktopTest/.../sync/`.

## Trampas

- La cola del iPad (`pendingOutboundChanges`) solo se llena con `enqueueLocalChange`: una escritura nueva que no lo llame nunca viaja.
- `SqlDelightSyncAdapter` cuenta como `ignored` (no `failed`) cualquier entidad que no conoce, y el iPad suelta la cola si `failed == 0`. Hoy pasa con `meetings`, `meeting_agreements`, `student_support_measures`, `student_tutoring_sessions`, `planner_week_plan` y `subject`: se pierden en silencio (Fase 2).
- Las pantallas que cargan en `.task` no observan el bridge: para que se recarguen con la sync hay que añadir `.reloadOnLanSync(.pantalla) { … }` y, si muestran entidades nuevas, ampliar `LanSyncRefreshPlan.affects`.
- `syncNow` vuelve al instante si ya hay una sync en vuelo (marca otra pasada); quien necesite el resultado debe usar `waitForSyncToFinish`.
- El indicador interpreta `syncStatusMessage` por texto (`SyncCatchUpCopy`): un mensaje nuevo de fallo silencioso debe contener «sin conexión» o se verá como «al día».
- `syncNow` tiene varias salidas tempranas sin publicar nada: no dejar mensajes de estado que solo se limpien desde dentro de `syncNow`.
- El helper del Mac se para con `willTerminateNotification`: con la app del Mac cerrada no se recibe nada del iPad.
- El POST `/sync/local-changes` solo se acepta desde loopback (decisión de seguridad, no tocar).
