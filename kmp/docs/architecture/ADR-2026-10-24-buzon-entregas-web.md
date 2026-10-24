# ADR-2026-10-24: Buzón de entregas web en el servidor de la web

## Estado

Aprobado

## Contexto

Las entregas web llegaban como fichero `.mgsub` que el alumnado mandaba por correo y el docente importaba a mano. Era lento y se perdían entregas. Queríamos que llegaran solas a la app, sin perder la privacidad: el servidor no debe poder leer respuestas ni saber de quién son.

## Decisión

- Un buzón en PHP (`buzon/buzon.php`, repo `entregas-alumnado`) en el mismo alojamiento que la web (alwaysdata). Los datos viven fuera de la web pública (`~/buzon-datos`, permisos 700/600).
- El servidor solo guarda el sobre ya cifrado (X25519 + ChaCha20) y huellas SHA-256. Nunca ve claves en claro, nombres ni IPs.
- Tres claves, todas creadas por la app:
  - **cuenta**: una por dispositivo, en el llavero. El servidor guarda solo su huella (`cuenta.hash`), que se instala a mano una vez. Sirve para registrar formularios.
  - **depósito**: una por formulario, en el enlace del alumno (`b=`). Solo permite dejar sobres.
  - **lectura**: una por formulario, en el llavero. Recoge y borra.
- El manifiesto firmado lleva `inbox`; la web solo acepta un buzón del mismo origen y por HTTPS. Si el envío falla, ofrece el correo como siempre.
- Si el registro en el buzón falla al publicar, no se publica: un enlace a un buzón que no conoce el formulario dejaría al alumnado con un error.
- La app recoge al abrir «Entregas web» (o la inscripción de un torneo), importa con el mismo `WebSubmissionImportService` y borra del servidor solo lo ya importado. Lo que no se puede asignar se queda en el buzón.
- Coevaluación: cada evaluación se guarda en `Documentos/EntregasWeb/<formulario>/coevaluaciones.json` (local, no viaja por Sync LAN) y la celda se recalcula con todas, porque por el buzón llegan en tandas.
- `purgar.php` borra a diario los formularios caducados hace más de 7 días. La caducidad máxima es de un año.
- La web marca `index.html`, `sw.js` y los manifiestos como `no-cache` para que el móvil no use código viejo.

## Alternativas descartadas

- Servicio externo (Firebase, formularios de terceros): saca datos del centro a otro proveedor.
- Sin buzón, solo correo: funciona, pero obliga a importar a mano.

## Consecuencias

- Las respuestas solo se recogen en el dispositivo que publicó: la clave de lectura y la privada están en su llavero.
- Cambiar de dispositivo exige activar el envío directo de nuevo e instalar su huella en el servidor.
- Sin cambios en KMP ni SQLDelight.
- Hay que mantener desactivado el registro de visitas del sitio (guarda IPs) y la tarea diaria de limpieza.
