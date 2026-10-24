# Ámbito: Sync LAN (iPad ↔ Mac)

## Estado actual

- Fase 1 de «siempre al día» (`codex/synclan-inmediato-f1`): envío garantizado al pasar a segundo plano en iPad, aviso «Poniéndose al día…» / «Sin conexión» en el indicador y recarga automática de las pantallas que cargan sus propios datos.
- Fase 2 (`codex/synclan-inmediato-f2`): reuniones, acuerdos, medidas, tutorías y asignaturas viajan con `SchoolRecordsSync`; categorías del Cuaderno en el Mac; mover/copiar sesiones del Planner encola; aviso «Datos distintos» en el icono.
- Fase 3 (`codex/synclan-inmediato-f3`): helper del Mac vivo con la app cerrada y al iniciar sesión (`MacSyncBackgroundService`, agente `SMAppService`); `BGAppRefreshTask` en iPad (`LanSyncBackgroundRefresh`).
- Fase 2b (`codex/synclan-inmediato-f2b`): plan semanal, Manual de Inclusión y pruebas físicas de EF con `ModuleRecordsSync` (claves naturales; el iPad los recoge de la base antes de cada envío).

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
- `ModuleRecordsSync` identifica plan semanal, tareas y ajustes de Inclusión por clave natural, no por id: no cambiar las claves (`weekPlanKey`, `inclusionTaskKey`, `groupSettingKey`) sin migrar las claves vivas guardadas en `UserDefaults` (`sync.module-records.live-keys`).
- En el iPad, Inclusión y EF no encolan: se recogen de la base en `enqueueModuleRecordChanges` (`#if os(iOS)`). Una escritura nueva en esos módulos solo necesita `triggerAutoSyncSoon()`.
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
- `URLSession.AsyncBytes.lines` (y cualquier `AsyncLineSequence`) **se salta las líneas vacías**: no usar la línea vacía como fin de aviso SSE. El helper manda cada aviso en una línea `data:`; `SyncEventLineParser` la procesa al llegar. Si algún día un aviso ocupa varias líneas `data:`, hay que leer los bytes a mano.
- El helper reemite su estado `running` cada vez que caduca el PIN (10 min). El coordinador solo avisa al bridge si cambia `host:port` (`lastAnnouncedEndpoint`); cualquier otra cosa cortaba el canal y recargaba la base.
- En el Mac nunca hay descarga completa (`shouldForceFullPull = false`): la app y el helper comparten la base.
- Diagnóstico rápido: `/usr/bin/log show --last 2h --predicate 'subsystem == "com.migestor.app"'` (líneas «Sync LAN … ms») y `lsof -nP -iTCP:8765` (conexiones del iPad y del Mac al helper).
- Topología: el iPad siempre se conecta al Mac (helper); el Mac nunca llama al iPad. Por esa conexión (push/pull + SSE) viajan los cambios en los dos sentidos: robustecer la conexión del iPad robustece ambos sentidos.
- La app iOS necesita `NSLocalNetworkUsageDescription` y `NSBonjourServices` (`_migestor-sync._tcp`) en `Config/iOS-Info.plist` (desde `project.yml`): sin ellas iOS bloquea Bonjour en silencio y el iPad no reencuentra al Mac.
- En macOS el helper se anuncia con `dns-sd -R` (`NativeDnsSdAdvertiser`), que resuelve como `<nombre-del-Mac>.local`. Un helper matado con `-9` deja su `dns-sd` vivo: se limpia con `pkill` antes de registrar. JmDNS queda solo como respaldo fuera de macOS.
- Estado «iPad conectado» en el Mac: el helper emite `State: peer|online=0/1` según haya una conexión SSE no-loopback.
- El POST `/sync/local-changes` solo se acepta desde loopback (decisión de seguridad, no tocar).
