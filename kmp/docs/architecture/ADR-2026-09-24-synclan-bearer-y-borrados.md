# ADR-2026-09-24: Contraseña de SyncLAN en el propio Mac y borrados que sobreviven al reinicio

## Estado

Aprobado

## Contexto

`isAuthorized` aceptaba cualquier petición salida del propio Mac. Mientras SyncLAN estaba encendido, un programa local podía leer o escribir el cuaderno sin la contraseña del enlace.

Los borrados que salían del Mac se recordaban solo en memoria. Al reiniciar el ayudante, ese recuerdo desaparecía. El iPad emparejado podía conservar alumnos ya borrados y, por las reglas de la base, también sus notas.

## Decisión

Todas las rutas de datos exigen la contraseña del enlace, también cuando la petición sale del propio Mac. Sin ella responden 401.

El aviso del Mac a sí mismo (`/sync/local-changes`) sigue aceptándose solo desde el propio Mac y sin contraseña. No entrega el cuaderno.

Cuando el Mac detecta que una ficha ha desaparecido, guarda el aviso en `sync_tombstones`. Al arrancar, carga los avisos de este Mac y los vuelve a enviar solo si esa ficha sigue sin existir. No se añade tabla ni columna. Solo una consulta para leer los avisos que ya se guardaban.

## Consecuencias

- Un programa del propio Mac ya no puede hacer pull, push ni descargar la copia de la base sin la contraseña.
- Un borrado que el ayudante ya había visto sigue viajando después de reiniciar.
- Si el alumno se vuelve a crear, el aviso antiguo no se reenvía.
- No se ha probado con un iPad físico.
