# ADR-2026-10-08: Calendario «Colegio» en dos sentidos, con el enlace guardado en la base de datos

## Estado

Aprobado. Sustituye en parte a `ADR-2026-10-08-calendario-apple-colegio.md`.

## Contexto

La versión anterior copiaba eventos de la app a «Colegio», pero no leía lo que se creaba en Calendario de Apple. Un evento creado en «Colegio» desde la app de Calendario no aparecía en la app.

El enlace entre un evento de la app y su copia en Apple vivía en `UserDefaults`, por aparato. Por eso no se podía editar desde otro aparato.

La tabla `calendar_events` ya tiene `external_provider` y `external_id`, y el modelo `CalendarEvent` ya los expone. Sincronizan entre aparatos con SyncLAN.

## Decisión

- La fuente de los eventos de «Colegio» es la cuenta de Calendario de Apple que tiene el aparato, leída con EventKit. No se usa el enlace público `webcal`: es de solo lectura y cualquiera con él ve el calendario.
- Se importan solo los eventos del curso 2026-2027 (del 1 de septiembre de 2026 al 30 de junio de 2027, hora local).
- El enlace se guarda en `calendar_events` con `external_provider = "apple_calendar"` y `external_id` = identificador externo del evento en iCloud (`calendarItemExternalIdentifier`). Es estable entre aparatos, a diferencia de `eventIdentifier`.
- Los eventos enlazados se reconcilian según la regla siguiente. Para cada evento enlazado:
  - Si el contenido es igual en la app y en «Colegio», no se hace nada.
  - Si cambió en los dos lados, gana el cambio más reciente.
  - Si el evento ya no está en «Colegio» y cae dentro del curso, se borra en la app.
  - Si dos eventos de la app apuntan al mismo evento de «Colegio», se quita el segundo.
- La reconciliación se ejecuta al volver a la app, al cambiar algo en Calendario de Apple y al activar la función.
- La lógica de qué hacer es una función pura (`AppleCalendarReconciler`), sin EventKit ni base de datos, y tiene pruebas unitarias.
- Las escrituras que trae la reconciliación no pasan por la cola de SyncLAN. Cada aparato lee «Colegio» por su cuenta; así no hay choques de identificadores locales.
- El botón «Día no lectivo» del planificador no se copia a «Colegio». Sus copias antiguas se borran al migrar.
- Los enlaces de la versión anterior (UserDefaults) se pasan a la base de datos en la primera ejecución, sin cambio de esquema.

## Consecuencias

- Un evento editado en un aparato se actualiza en «Colegio» aunque se haya creado en el otro. El límite de la versión anterior desaparece.
- Un evento borrado en «Colegio» desaparece de la app, pero solo si cae dentro del curso.
- Si un evento cambia a la vez en los dos lados, gana el último que se modificó. El otro cambio se pierde sin aviso.
- El identificador externo depende de iCloud. Con otra cuenta que no sea CalDAV, el enlace podría no ser estable. Eso no está probado.
- No hay cambio de esquema SQLDelight. `kmp/data` y `kmp/shared` no se tocan.
- Falta una prueba manual con el permiso de Calendario concedido en un aparato real.
