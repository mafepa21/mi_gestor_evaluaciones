# ADR-2026-10-22: Actas e Inclusión en SyncLAN con un solo código Kotlin

## Estado

Aprobado

## Contexto

La app Apple encolaba reuniones, acuerdos, medidas de apoyo, tutorías con familias y asignaturas. Ningún lado sabía aplicarlas. En el Mac, `SqlDelightSyncAdapter` las contaba como `ignored`. El iPad soltaba su cola porque `failed == 0`. En Apple caían en `default: continue`. El Mac tampoco las enviaba en la descarga. Los datos se perdían en silencio en los dos sentidos.

Además, el apply de cada entidad estaba escrito dos veces: en Swift (`KmpBridge+SyncLAN.swift`) y en Kotlin (`SqlDelightSyncAdapter`). Cada entidad nueva había que añadirla en los dos sitios, y nadie lo comprobaba.

## Decisión

- `SchoolRecordsSync` (`kmp/data/.../sync/`) es el único código que lee, envía, aplica y borra estas cinco entidades. Lo usan el helper del Mac (vía el adapter) y la app Apple (desde `applyPulledChanges`).
- Los payloads son los que ya mandaba la app Apple. Una clave ausente conserva el valor local. Así funcionan también los cambios de versiones anteriores.
- LWW real: si la fila local es igual o más nueva que el cambio, no se toca (cuenta como conflicto resuelto, no como fallo).
- La reunión se crea con `INSERT OR IGNORE` + `updateMeeting`, nunca con `REPLACE`: `REPLACE` borra la fila y, con ella, sus acuerdos (`ON DELETE CASCADE`).
- Tres consultas nuevas en `AppDatabase.sq` para crear con el id que llega. Sin cambios de tablas ni migración. El usuario autorizó tocar el archivo protegido.
- `SyncEntityCoverageTest` lee el código fuente y falla si la app encola una entidad que el Mac o Apple no saben aplicar. Ya encontró las categorías de columnas del Cuaderno, que el Mac no aplicaba.

## Consecuencias

- Las entidades nuevas de este tipo se añaden solo en Kotlin.
- Los datos creados antes de esta versión no viajan solos: hay que usar una vez «Igualar dispositivos».
- Los ids son autoincrementales en cada dispositivo. Si los dos crean registros a la vez sin conexión, pueden coincidir y el más nuevo pisa al otro. Pasa igual con las entidades que ya se sincronizaban; no se resuelve aquí.
- Quedan fuera, para otra fase: plan semanal del Planner, tareas y ajustes del Manual de Inclusión y las pruebas físicas de EF (9 tablas). Necesitan consultas nuevas.
- No se ha probado con un iPad físico.
