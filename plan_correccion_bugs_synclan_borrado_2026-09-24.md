# Plan: contraseña de SyncLAN, borrados que sobreviven al reinicio y baja por curso

Fecha: 2026-09-24
Rama: `codex/fix-synclan-auth-tombstones-delete`
Base: `develop`

## Qué se arregla

1. Mientras SyncLAN está encendido, un programa del propio Mac podía leer y escribir el cuaderno sin la contraseña del enlace.
2. Al reiniciar el ayudante, los avisos de borrado se perdían. El iPad podía conservar alumnos y, con ellos, sus notas.
3. Borrar a un alumno indicando un curso borraba la ficha entera y arrastraba los datos de los otros cursos.

## Qué se hace

- Las rutas de datos piden la contraseña también si la petición sale del propio Mac. Sin ella responden 401.
- El aviso interno del Mac a sí mismo sigue aceptándose solo en local y sin contraseña. No entrega el cuaderno.
- El Mac guarda cada borrado propio en `sync_tombstones` y, al arrancar, lo vuelve a enviar solo si esa ficha sigue sin existir.
- Con un curso, el alumno solo se da de baja de ese curso. La ficha entera se borra solo con una orden explícita.

## Qué no se toca

- Emparejamiento, pantallas y el puente Swift.
- Los botones que ya piden borrar la ficha en todos los cursos.
- `main`.

## Cómo se comprueba

- Prueba HTTP: desde el propio Mac, sin contraseña, lectura y escritura responden 401. Con contraseña, la lectura responde 200.
- Prueba de reinicio: un alumno borrado sigue saliendo como borrado en un adaptador nuevo.
- Prueba de baja: el alumno desaparece de un curso y sigue en el otro. Sin orden explícita, la ficha no se borra.
