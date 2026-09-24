# ADR-2026-09-24: Sesiones, franja y diario en SyncLAN

## Estado

Aprobado

## Contexto

Al sincronizar, el Mac enviaba la sesión sin los instrumentos enlazados ni la franja. El otro aparato guardaba esos huecos vacíos y pisaba lo que ya tenía.

El diario de la sesión no entraba en el sync incremental. Una nota rápida sí se encolaba, pero el otro aparato no sabía aplicarla.

El escritorio además escribía parte de las sesiones en `planned_session`. El iPad solo lee `planner_session`. Por eso no se veían igual.

## Decisión

El mensaje de `planning_session` incluye siempre instrumentos, franja, horas y el enlace a la situación de aprendizaje. Si un mensaje viejo llega sin esos campos, se conserva lo que ya hay. Si el campo viene vacío a propósito, sí se borra.

El diario viaja como `session_journal`, identificado por la sesión y no por el id local del diario. Incluye texto, notas, tareas, enlaces y la ruta de las fotos. No se copian los archivos. Un mensaje sin el campo `status` se ignora.

Las sesiones nuevas que salen de guardar una unidad, o de copiar y mover en el escritorio, se escriben en `planner_session`. La tabla `planned_session` no se borra. La migración 44 copia lo que encaja en una franja y deja de usarlo como almacén vivo.

La huella de «Igualar dispositivos» tiene en cuenta instrumentos, franja y diario.

No se abre el aviso interno del Mac fuera del propio Mac. No se cambia el emparejamiento.

## Consecuencias

- Un sync nuevo ya no deja la sesión sin instrumentos ni sin hora.
- El diario escrito en un aparato puede aparecer en el otro en el siguiente sync.
- Una sesión generada en el escritorio puede verse en el iPad.
- Al actualizar, las filas viejas de `planned_session` cuya hora encaja en una franja pasan a `planner_session`. Si ese hueco ya tenía texto, se conserva. Si la hora no encaja, la fila se queda en la tabla vieja y no se muestra.
- El estado vacío o `PENDING` pasa a `PLANNED`. Las sesiones nuevas nacen en `PLANNED`.
- Guardar una sesión con id solo toca esa fila. Una sesión nueva, si el hueco existe, actualiza esa fila.
- Arrastrar en cascada no mueve una sesión impartida ni cancelada, salvo que se confirme el aviso.
- No se ha probado con un iPad físico.
