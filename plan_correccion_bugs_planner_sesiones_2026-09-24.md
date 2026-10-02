# Plan: una sola tabla de sesiones del planificador

Fecha: 2026-09-24

## Qué se arregla

1. Copiar `planned_session` a `planner_session` cuando la hora encaja en una franja. Lo que no encaja se queda en la tabla vieja.
2. Guardar por id y, si la sesión es nueva, por hueco de fecha, grupo y periodo.
3. Pasar `PENDING` a `PLANNED` y dejar ese valor por defecto.
4. La cascada no mueve sesiones impartidas ni canceladas, salvo confirmación.

## Fuera

No se borra la tabla vieja. No se sube a `main`.
