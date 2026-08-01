# ADR-2026-08-01: Mac como centro de Entregas web

## Estado

Aprobado

## Contexto

Las Entregas web necesitan conservar material privado que no debe viajar por SyncLAN:
la clave privada de cada formulario, la relación entre alias y alumnado, el mapa de
ítems y el ledger de importación. El flujo anterior dependía del formulario más
reciente y no podía gestionar de forma segura varios grupos ni un lote mixto.

Además, publicar, revisar conflictos e importar respuestas son tareas de gestión de
archivos y de coordinación que encajan mejor en el escritorio del docente. El iPad
debe seguir siendo una superficie de consulta y evaluación, no replicar las tablas
privadas ni convertirse en otra autoridad de claves.

## Decisión

- El Mac es el centro de publicación, bandeja global, resolución de alias y carga de
  archivos `.mgsub`.
- Cada formulario se identifica por `formInstanceId`; la bandeja consulta todos los
  formularios y el importador resuelve cada archivo de forma independiente.
- El manifiesto público se guarda en `Documents/EntregasWeb/<formInstanceId>` junto
  con una hoja privada de enlaces. La clave privada vive en el llavero del Mac.
- La importación escribe las respuestas exclusivamente mediante `saveResponses`, con
  una llamada por alumno y entrega, y registra cada resultado en el ledger de su
  formulario.
- Las tablas privadas `web_*` no se añaden al transporte SyncLAN. El iPad muestra el
  estado operativo y recibe las respuestas ya escritas en el Cuaderno mediante la
  sincronización existente.
- La caducidad solo describe cuándo la web deja de aceptar nuevas entregas. Un
  archivo válido recibido antes puede importarse después; una tarea revocada o
  caducada permanece visible para trazabilidad.
- La revocación desde la bandeja marca el formulario como `revoked` en el Mac y
  conserva claves, alias, ledger y respuestas. No se presenta como un bloqueo
  remoto inmediato: el manifiesto público está firmado y ya desplegado fuera de
  la app. Para detener nuevas respuestas en la web hay que retirar/republicar el
  manifiesto o añadir en el futuro un registro de revocación consultable.
- El reparto de enlaces se realiza desde el Mac usando la hoja privada y los
  correos actuales del alumnado. La app prepara mensajes individuales en Mail;
  no envía credenciales ni direcciones por SyncLAN.

## Consecuencias

- La gestión multi-grupo queda reunida en una sola bandeja con filtros, búsqueda,
  estados y actividad de importación.
- Un lote mixto puede continuar con los archivos válidos y aislar desconocidos,
  inválidos, duplicados, conflictos y ya importados.
- El iPad no necesita transportar secretos ni conocer las correspondencias privadas.
- Si el docente publica desde otro Mac, ese dispositivo no podrá resolver el lote
  hasta disponer del formulario, sus claves y sus mapas privados; es una propiedad
  deliberada de privacidad, no un fallback automático.
- Revocar es seguro para el historial local, pero requiere una operación adicional
  sobre el despliegue público si la intención es impedir el acceso web en ese mismo
  momento.
- Los correos pueden cambiar después de publicar: el reparto lee el correo vigente
  de la ficha, pero nunca modifica la hoja privada ni cambia el alias del enlace.
- El transporte futuro de los archivos originales o una copia privada entre Macs
  queda fuera de esta decisión.
