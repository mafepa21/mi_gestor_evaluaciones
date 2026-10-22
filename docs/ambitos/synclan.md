# Ámbito: Sync LAN (iPad ↔ Mac)

## Estado actual

- Fase 1 de «siempre al día» (`codex/synclan-inmediato-f1`): envío garantizado al pasar a segundo plano en iPad, aviso «Poniéndose al día…» / «Sin conexión» en el indicador y recarga automática de las pantallas que cargan sus propios datos.
- Fase 2 (`codex/synclan-inmediato-f2`): reuniones, acuerdos, medidas, tutorías y asignaturas viajan con `SchoolRecordsSync`; categorías del Cuaderno en el Mac; mover/copiar sesiones del Planner encola; aviso «Datos distintos» en el icono.
- Fase 3 (`codex/synclan-inmediato-f3`): helper del Mac vivo con la app cerrada y al iniciar sesión (`MacSyncBackgroundService`, agente `SMAppService`); `BGAppRefreshTask` en iPad (`LanSyncBackgroundRefresh`).
- Pendiente Fase 2b: plan semanal, tareas/ajustes de Inclusión y pruebas físicas de EF.

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
- El helper puede estar vivo sin la app (soltado al cerrar o arrancado por el agente al iniciar sesión). Cualquier cosa que sustituya la base en el arranque debe ir después de `terminateLeftoverHelpersBeforeOpeningDatabase()` en `MiGestorKMPMacApp.init`. Un flujo nuevo que sustituya la base con la app abierta debe parar el helper antes (`commandCenter.stop()`), o al cerrar seguirá vivo.
- El agente (`RunAtLoad`) arranca al registrarse: solo se registra al cerrar la app con el helper vivo, para no tener dos helpers peleando por el puerto 8765.
- El handler de `willTerminateNotification` tiene que ser síncrono: una `Task` lanzada ahí puede no ejecutarse nunca.
- iPad: el bridge vive en `AppleAppRootView`; `LanSyncBackgroundRefresh.bridge` es débil y es nil en un arranque en frío para la tarea de fondo. Las claves `UIBackgroundModes` y `BGTaskSchedulerPermittedIdentifiers` viven en `Config/iOS-Info.plist` (generado por xcodegen desde `project.yml`).
- El POST `/sync/local-changes` solo se acepta desde loopback (decisión de seguridad, no tocar).
