# ADR-2026-08-09: Endurecimiento del pairing SyncLAN

## Estado

Aprobado

## Contexto

El helper Command Center ya ofrece SyncLAN mediante HTTPS, certificado fijado por
fingerprint y token posterior al pairing. Sin embargo, el PIN no caducaba, los
intentos no estaban limitados y los logs de diagnóstico incluían el PIN recibido y
esperado, identificadores de dispositivo y direcciones remotas. Además, los cuerpos
de varias rutas se leían completos sin un límite previo.

El PIN debe seguir visible en el Mac y formar parte del QR: ese es el canal de
presencia física que permite vincular el iPad. No se puede retirar de ese flujo sin
rediseñar el producto.

## Decisión

- Generar el PIN de seis dígitos con `SecureRandom`, darle una vigencia de diez
  minutos y rotarlo al caducar, tras un pairing correcto y al desvincular.
- Permitir cinco fallos por dirección de origen dentro de 60 segundos y bloquear
  ese origen durante 60 segundos. Acotar el registro a 256 orígenes para que el
  propio limitador no se convierta en una vía de agotamiento de memoria.
- Responder con errores JSON estables (`invalid_pin`,
  `pairing_temporarily_unavailable`) y registrar únicamente el resultado genérico,
  sin PIN, token, `deviceId` ni dirección remota.
- Limitar el handshake a 16 KiB, los lotes de cambios a 2 MiB y cada documento a
  25 MiB, comprobando tanto `Content-Length` como el stream real.
- Mantener sin cambios HTTPS, certificate pinning, el bearer token y la restricción
  loopback de `POST /sync/local-changes`.
- Mantener el PIN en el payload mostrado como QR y en la línea estructurada de
  stdout `State: running|...|pin=...` del helper. Esa línea no es un log de red: es
  el IPC local que consume `MacCommandCenterCoordinator` para actualizar la UI. No
  se publica por Bonjour ni se incluye en logs de handshake.

## Consecuencias

- Un PIN observado deja de ser reutilizable indefinidamente y un origen no puede
  probar combinaciones sin pausa.
- La rotación puede invalidar un QR que lleve diez minutos abierto; el monitor del
  helper publica el nuevo estado para que la UI lo regenere.
- El límite es deliberadamente local por origen: evita bloquear toda el aula por
  los fallos de un único equipo. Una red capaz de rotar muchas IP sigue siendo un
  riesgo residual, mitigado por la presencia física, la vigencia corta y el espacio
  acotado de estados.
- El canal stdout debe tratarse como IPC sensible: no debe redirigirse a telemetría
  o soporte sin redacción. Sustituirlo por XPC autenticado queda fuera de este cambio.
