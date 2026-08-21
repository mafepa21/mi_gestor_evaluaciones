# ADR-2026-08-21: Contrato `session-plan-v2` para QUICK VIEW

## Estado

Aprobado

## Contexto

Las fichas de sesión importadas se almacenaban como un array de secciones (`developmentJson`),
lo que obligaba a la interfaz a reconstruir una línea temporal narrativa y no permitía unir
QUICK VIEW con una ficha operativa por `Activity ID`. El cambio necesita conservar las sesiones
ya guardadas y no requiere una tabla SQLDelight nueva.

## Decisión

`developmentJson` admite un objeto Codable versionado con `schema: "session-plan-v2"`.
El objeto conserva una proyección de secciones y actividades y añade identidad estable,
metadatos de sesión, preguntas guía y cierre. El decoder acepta tanto el array v1 como el objeto
v2; entradas corruptas se tratan como ausencia de contenido. El importador de formato C une
QUICK VIEW y ACTIVITY DETAILS por `Activity ID`, emite warnings ante desajustes y no duplica filas.

La persistencia permanece opaca en el campo existente y `learningSituationSessionPlanId` no cambia.

## Consecuencias

- Las sesiones legacy siguen abriéndose con filas sintéticas y detalle progresivo.
- Las sesiones reimportadas desde el documento nuevo muestran el mapa QUICK VIEW y una sola
  actividad seleccionada.
- La compatibilidad exige mantener el decoder dual y pruebas explícitas para v1, v2 y JSON corrupto.
- El formato C preserva los datos de la fila QUICK VIEW si falta o sobra una ficha de detalle,
  dejando el warning visible para revisión docente.
