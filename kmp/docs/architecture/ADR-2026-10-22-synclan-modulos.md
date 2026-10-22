# ADR-2026-10-22: Plan semanal, Manual de Inclusión y pruebas físicas en SyncLAN

## Estado

Aprobado

## Contexto

Tras la fase 2 (`ADR-2026-10-22-synclan-actas-inclusion.md`) quedaban sin sincronizar el plan semanal del Planner, las tareas y la fecha de evaluación inicial del Manual de Inclusión y las pruebas físicas de EF (9 tablas).

Tres problemas propios:

- Las tareas del manual las genera cada dispositivo por su cuenta (`generateForClass`): sus ids autoincrementales no coinciden.
- En el iPad casi ninguna de estas escrituras pasa por `enqueueLocalChange`; algunas las hace Kotlin solo.
- La fecha de evaluación inicial no guarda cuándo cambió.

## Decisión

- `ModuleRecordsSync` (`kmp/data/.../sync/`), con el mismo reparto que `SchoolRecordsSync`: lo usan el helper del Mac (vía el adapter) y Apple.
- Claves naturales: plan semanal `grupo|año|semana`; tarea `t|alumno|curso|plantilla` o `f|alumno|curso|fechaDeAlta`; ajuste `grupo|curso`; enlace EF `asignación|prueba`. Las pruebas físicas ya usan UUID de texto.
- LWW con la fecha de cada fila. Las tareas se crean con `insertTemplateIfAbsent`/`insertFreeTask` y luego se fijan fecha y estado con la hora del cambio, para quedar fechadas igual en los dos lados.
- La fecha de evaluación inicial se fecha en memoria al detectar un cambio. Un valor con fecha 0 (primera lectura tras arrancar) solo rellena huecos.
- En el iPad (`#if os(iOS)`) se llama a `ModuleRecordsSync.collect` antes de cada envío (como mucho cada 3 s, siempre al irse y al despertar en segundo plano). El cursor y las claves vivas se guardan en `UserDefaults`. Así se envían también los datos que ya había antes de esta versión. El Mac no lo necesita: lo recoge su helper.
- Las escrituras de Inclusión y EF del bridge llaman a `triggerAutoSyncSoon()`.
- 3 consultas de solo lectura nuevas en `AppDatabase.sq`, autorizadas por el usuario. Sin cambios de tablas.

## Consecuencias

- `SyncEntityCoverageTest` ya no tiene entidades pendientes.
- Las tareas del manual se reenvían una vez entre dispositivos (cada uno las generó con su hora); el LWW las deja iguales.
- Las pruebas físicas no tienen borrado en la app; si se añade, hay que sincronizarlo.
- Recoger de la base en el iPad recorre varias tablas (los resultados de EF pueden ser miles): se limita a una vez cada 3 s.
- No se ha probado con un iPad físico.
