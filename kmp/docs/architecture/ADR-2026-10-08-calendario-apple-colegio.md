# ADR-2026-10-08: Copia de eventos a un calendario «Colegio» de Apple, solo desde el aparato donde se edita

## Estado

Aprobado

## Contexto

Los hitos del curso viven en la app (`calendar_events`). El profesorado quiere verlos también en el Calendario de Apple, en un calendario propio llamado «Colegio».

La app no usaba EventKit en ningún punto. Además, los eventos pueden entrar en un aparato por SyncLAN sin pasar por la función que guarda eventos del puente, así que una copia hecha "en todas partes" duplicaría los eventos.

## Decisión

- La copia es de un solo sentido: app → Calendario de Apple. Nunca se lee el calendario de Apple para cambiar la app.
- Solo se crean copias de los eventos que se crean en el aparato, desde `KmpBridge.plannerSaveCalendarEvent` y `plannerDeleteCalendarEvent`. Los eventos que llegan por SyncLAN no se copian.
- Una edición solo actualiza una copia que este aparato ya creó. Si no existe, no crea nada nuevo.
- El enlace entre cada evento de la app y su copia en Apple se guarda en `UserDefaults` de cada aparato (`appleCalendarMirror.eventMap`). No se toca SQLDelight.
- El calendario «Colegio» se busca por título antes de crearlo. Así iPad y Mac, con la misma cuenta de iCloud, usan el mismo calendario.
- Con la función desactivada, la app no toca el calendario de Apple. Las copias ya creadas no se borran.

## Consecuencias

- Un evento creado en el iPad y editado en el Mac no actualiza su copia en Apple. La copia queda como se creó.
- Si se pierde el enlace de `UserDefaults` (reinstalar o restaurar copia), al activar de nuevo la función se enlazan las copias con el mismo título y día. Un evento que haya cambiado de título o de día sí se duplica en «Colegio» y hay que borrar la copia antigua a mano.
- No hace falta cambio de esquema ni migración.
- Requiere el permiso de Calendario (`NSCalendarsFullAccessUsageDescription` en `project.yml`).
- No se ha probado con el permiso concedido en un aparato real. La compilación de macOS e iOS sí se ha ejecutado.
