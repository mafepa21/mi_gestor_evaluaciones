# Plan de corrección: fidelidad `session-plan-v2`

## Objetivo

Representar el DOCX de secuenciación 1:1 en la planificación, conservando la separación entre
actividad ejecutable, QUICK VIEW, ACTIVITY DETAILS y el contexto `PREPARES`/`CONSOLIDATES`.

## Alcance ejecutado

- Importador: unión por `Activity ID`, exclusión del ID como actividad, y lectura de campos de
  contexto desde QUICK VIEW y ACTIVITY DETAILS.
- Contrato v2: campos explícitos `prepares` y `consolidates`.
- Persistencia: reparación idempotente por SHA-256, con los mismos IDs y protección contra
  normalización incompleta durante sincronización metadata-first.
- Visualizador: normalización de legacy, contexto primario/secundario según ruta y apertura del
  DOCX original en macOS/iOS.
- Regresión: ningún título visible de actividad puede ser `LEGACY-*` o un ID `Wxx-L/S-xx`.

## Validación

- `MiGestorPlannerTests`: 81/81.
- Pruebas focalizadas de importación/proyección: 25/25.
- `./scripts/verify_apple_builds.sh`: macOS Native e iOS Simulator compilados.
- DOCX presente: SHA-256 `d0ee52ff904256208063f23efb84ea5fd881a754f09dc93ec6dcd9d280dab70a`.

## Pendiente externo

El binario DOCX disponible produce W01 LONG 4, W01 SHORT 3, W02 LONG 4 y W02 SHORT 3; por
tanto no permite certificar los conteos solicitados 6/4. Hace falta recibir el binario corregido
para cerrar esa comprobación, sin cambiar el formato del documento.
