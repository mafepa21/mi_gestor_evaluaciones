# ADR-2026-11-18: Portal del alumnado con cuenta propia

## Estado

Aprobado (fase 1). Contrato: `docs/planes/contrato_portal_v1_2026-11-18.md`. Ticket: `docs/planes/ticket_portal_alumnado_fase1_2026-11-18.md`.

## Contexto

Cada formulario web generaba un enlace nuevo por alumno que el docente mandaba por correo. Las entregas ya volvían solas por el buzón (ADR-2026-10-24), pero la ida seguía siendo un correo por formulario. Queríamos un sitio fijo donde el alumnado vea todo lo pendiente, sin que el servidor sepa quién es cada alumno ni pueda leer su contenido.

## Decisión

- Cada alumno tiene un `portalId` al azar y una llave `K_tablon` creadas en la app. El tablón (pendientes y ya enviados) viaja cifrado con ChaCha20-Poly1305 y `K_tablon`.
- Alta: un código de 10 caracteres (≈50 bits), de un uso y 7 días, por correo (solo Mac) o QR. Del código salen, con PBKDF2-HMAC-SHA256 (600 000 iteraciones) y HKDF, el `inviteId`, una prueba y la llave que abre `sobreAlta`. El servidor no conoce el código.
- Cuenta: usuario (mote) y contraseña. El navegador deriva con Argon2id (m=19 MiB, t=2) `claveAuth`, que el servidor guarda con `password_hash`, y `claveEnvoltura`, que nunca sale y abre `sobreCuenta`. El usuario llega al servidor solo como hash.
- Servidor: `buzon/portal.php` en el mismo alojamiento que el buzón, datos en `~/buzon-datos/portal/`, sin registros ni IPs, con esperas crecientes por usuario y dispositivo y sal falsa estable para usuarios que no existen.
- Reinvitar rota `K_tablon`. Si el alumno ya tiene cuenta, la rotación se difiere: se sigue publicando con la llave actual hasta que `estado` confirma que canjeó el código nuevo.
- La app publica el tablón al publicar un formulario y al importar entregas. El cruce `portalId` ↔ alumno solo existe en `Documentos/EntregasWeb/portal/alumnos.json` (no viaja por Sync LAN) y las llaves en el llavero.

## Alternativas descartadas

- Solo enlace o QR fijo: se pierde y no sirve en varios dispositivos.
- Entrar con la cuenta del centro (Google o Microsoft): el servidor sabría quién entra y depende del responsable informático del centro.
- Argon2id también para el código: CryptoKit no lo trae y no se quieren dependencias. Con 50 bits de entropía, PBKDF2 basta.

## Consecuencias

- Sin cambios en KMP ni SQLDelight.
- Solo publica el dispositivo que tiene las llaves en su llavero. Cambiar de equipo exige volver a invitar.
- El servidor ve cuántos tablones hay, su tamaño, cuándo cambian y cuáles se publican juntos. No ve de quién son.
- Rendija conocida: con muchos dispositivos distintos, un usuario real y uno inexistente no se bloquean igual, así que se puede llegar a confirmar que un mote existe. No da acceso a nada.
- La fase 2 («Mis notas», sección 11 del ticket) cabe en el mismo tablón v1.
- Puertas humanas: consulta al delegado de protección de datos, permitir `portal.php` en `buzon/.htaccess` del servidor y probar `probar-portal.sh` con PHP antes de abrirlo a alumnado real.
