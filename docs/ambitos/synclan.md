# Ámbito: Sync LAN (iPad ↔ Mac)

## Estado actual

- Fase 1 de «siempre al día» (`codex/synclan-inmediato-f1`): envío garantizado al pasar a segundo plano en iPad, aviso «Poniéndose al día…» / «Sin conexión» en el indicador y recarga automática de las pantallas que cargan sus propios datos.
- Fase 2 (`codex/synclan-inmediato-f2`): reuniones, acuerdos, medidas, tutorías y asignaturas viajan con `SchoolRecordsSync`; categorías del Cuaderno en el Mac; mover/copiar sesiones del Planner encola; aviso «Datos distintos» en el icono.
- Pendiente Fase 2b: plan semanal, tareas/ajustes de Inclusión y pruebas físicas de EF. Pendiente Fase 3: helper vivo con la app del Mac cerrada y refresco en segundo plano en iPad.

## Terreno de juego

- Apple: `kmp/iosApp/App/Bridge/KmpBridge+SyncLAN.swift` (ciclo de vida, `syncNow`, aplicar cambios, `LanSyncRefreshPlan`), `LanSyncClient.swift`, `AppleShared/SyncEventListener.swift`, `App/SyncStatusBadge.swift`, `App/LanSyncReloadModifier.swift`.
- Mac helper: `kmp/commandCenterHelper/`, `kmp/data/src/desktopMain/.../sync/LocalSyncServer.kt`, `MacApp/MacCommandCenterCoordinator.swift`.
- Kotlin: `kmp/data/src/commonMain/kotlin/com/migestor/data/sync/SqlDelightSyncAdapter.kt` (lo que el Mac exporta y aplica) y `SchoolRecordsSync.kt` (actas e Inclusión, compartido con Apple).
- Tests: `kmp/iosApp/PlannerTests/PlannerMonthGridTests.swift` (refresco y badge), `kmp/data/src/desktopTest/.../sync/` (`SchoolRecordsSyncTest`, `SyncEntityCoverageTest`).

## Trampas

- La cola del iPad (`pendingOutboundChanges`) solo se llena con `enqueueLocalChange`: una escritura nueva que no lo llame nunca viaja.
- `SqlDelightSyncAdapter` cuenta como `ignored` (no `failed`) cualquier entidad que no conoce, y el iPad suelta la cola si `failed == 0`: una entidad nueva sin apply se pierde en silencio. `SyncEntityCoverageTest` lo vigila leyendo el código; `planner_week_plan` está en su lista de pendientes.
- Entidades nuevas de actas/Inclusión: añadirlas solo en `SchoolRecordsSync` (lo usan el Mac y Apple). Nada de `REPLACE` en tablas con hijas en cascada (reuniones).
- Operaciones en bloque de Kotlin (`doCopySessions`, `shiftSelectedSessions`, `commitCascadeMove`, `restoreCascadeMove`) no pasan por el encolado: el wrapper Swift debe llamar a `enqueueRelocatedPlanningSessions`. Desplazar y sustituir borran sesiones y crean otras con id nuevo.
- `:shared:test` pide el SDK de Android; si no está, usar `:shared:desktopTest`.
- No enlazar `kmp/iosApp/Frameworks` con un symlink al checkout principal: Xcode regenera el framework KMP en el pre-build y escribiría en el otro checkout.
- Las pantallas que cargan en `.task` no observan el bridge: para que se recarguen con la sync hay que añadir `.reloadOnLanSync(.pantalla) { … }` y, si muestran entidades nuevas, ampliar `LanSyncRefreshPlan.affects`.
- `syncNow` vuelve al instante si ya hay una sync en vuelo (marca otra pasada); quien necesite el resultado debe usar `waitForSyncToFinish`.
- El indicador interpreta `syncStatusMessage` por texto (`SyncCatchUpCopy`): un mensaje nuevo de fallo silencioso debe contener «sin conexión» o se verá como «al día». La divergencia llega aparte (`DashboardBridgeStore.syncDivergence`).
- `syncNow` tiene varias salidas tempranas sin publicar nada: no dejar mensajes de estado que solo se limpien desde dentro de `syncNow`.
- El helper del Mac se para con `willTerminateNotification`: con la app del Mac cerrada no se recibe nada del iPad.
- El POST `/sync/local-changes` solo se acepta desde loopback (decisión de seguridad, no tocar).
