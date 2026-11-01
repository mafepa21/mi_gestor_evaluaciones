# ADR-2026-10-22: SyncLAN con las apps cerradas

## Estado

Aprobado (el usuario dio su OK expreso para añadir un proceso al iniciar sesión en el Mac)

## Contexto

El helper del Mac (`MiGestorCommandCenter`) es un proceso propio que lee y escribe la misma base que la app. Era hijo de la app y moría con ella. Con el Mac cerrado, lo que se editaba en el iPad se quedaba en su cola. Si después se editaba en el Mac, los dos dispositivos acababan con datos distintos.

En el iPad, iOS congela la app en segundo plano y no deja una conexión abierta.

## Decisión

**Mac**

- Al cerrar la app, si hay un iPad enlazado y el ajuste está activo, el helper no se termina. Se suelta: sus pipes se cierran y la JVM ignora el SIGPIPE (comprobado).
- No se queda vivo si hay una restauración o un borrado pendientes de reinicio, ni con una adopción preparada (`pending_adopt.json`): recibiría cambios en una base que el próximo arranque sustituye.
- Agente de `launchd` (`SMAppService.agent`, `Contents/Library/LaunchAgents/com.migestor.mac.sync-helper.plist`) con `RunAtLoad` y sin `KeepAlive`. Sin `--db-path` el helper usa la misma base que la app.
- El agente solo se registra al cerrar la app con el helper vivo: registrarlo lo arranca al momento, y con la app abierta dos helpers se pelearían por el puerto. El del agente no consigue el puerto y termina; queda listo para el próximo inicio de sesión. Se retira al desvincular o al apagar el ajuste.
- Al abrir la app, `MiGestorKMPMacApp.init` cierra cualquier helper que quede vivo antes de crear el bridge y abrir la base. Después la app arranca el suyo como siempre.
- El cierre de `willTerminate` se hace en el acto (`MainActor.assumeIsolated`), no en una `Task` que podía no llegar a correr.

**iPad**

- `BGAppRefreshTask` (`com.migestor.ios.sync-refresh`, `UIBackgroundModes: fetch`): un envío y una descarga cortos cuando iOS despierte la app. Se reprograma cada vez (mínimo 15 min).
- Si iOS arranca la app en frío para la tarea, no se abre la base por detrás: el bridge vive en la vista raíz. Se espera al siguiente despertar.

## Consecuencias

- Con el Mac encendido y la sesión iniciada, el iPad siempre tiene con quién sincronizar, aunque la app del Mac esté cerrada.
- Hay un proceso más en el Mac mientras haya un iPad enlazado. macOS lo muestra en Ajustes del Sistema › Ítems de inicio.
- Abrir la app cierra el helper de fondo: el iPad pierde la conexión un momento y se reconecta con el de la app.
- En el iPad no se puede garantizar la inmediatez con la app cerrada: lo decide iOS. La garantía real sigue siendo el envío al irse a segundo plano y ponerse al día al volver.
- `SMAppService` exige una app firmada. En builds sin firma el registro falla y se muestra el motivo; el helper vivo al cerrar sí funciona.
- No se ha probado con un iPad físico ni reiniciando el Mac.
