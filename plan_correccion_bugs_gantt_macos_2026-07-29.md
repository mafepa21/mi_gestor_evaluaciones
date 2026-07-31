# Plan de corrección: excelencia macOS y Gantt

## Objetivo

Convertir el Gantt del Planificador en una superficie fiable de seguimiento y corregir problemas
de jerarquía, estados vacíos y duplicación de controles en las pantallas principales de macOS.

## Alcance ejecutado

- Carga completa y cancelable de situaciones, últimas secuencias, planes y sesiones.
- Estados tipados y conteos independientes para seguimiento y atención.
- Gantt con carril fijo, proyección temporal única, dos densidades y periodo contextual.
- Ubicación de pendientes mediante el composer existente, sin drag & drop.
- Toolbar contextual y eliminación de controles duplicados en Día para macOS.
- Avisos de horario inválido o solapado.
- Estados vacíos accionables en Situaciones y Asistencia.
- Inspector de shell limitado a módulos con contenido real.
- Target macOS de pruebas de proyección y estados del Gantt.

## Fuera de alcance

- Rediseño del Cuaderno.
- UX específica de iPhone.
- Cambios KMP, SQLDelight o migraciones.
- Edición temporal directa en el Gantt.

## Criterios de aceptación

- [x] El Gantt incluye secuencias sin sesiones agendadas.
- [x] Los estados y conteos no dependen de textos de presentación.
- [x] Los errores de lectura no se presentan como estados vacíos.
- [x] La acción de ubicar conserva el plan de sesión.
- [x] macOS e iOS Simulator compilan tras regenerar el proyecto.
- [x] Las pruebas macOS del Gantt pasan.
- [ ] QA visual manual en 900, 1200 y 1600 pt, claro/oscuro y ambas densidades.

La última comprobación requiere permisos de Accesibilidad y grabación de pantalla que no estaban
disponibles para el proceso de Codex durante esta intervención.
