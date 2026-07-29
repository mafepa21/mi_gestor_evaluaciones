# Resumen

Rediseña el Gantt del Planificador macOS como una superficie de seguimiento fiable y accionable,
incluyendo secuencias sin agendar, estados reales y ubicación de pendientes mediante el composer.
Completa la intervención con toolbar contextual, avisos de horario y estados vacíos accionables en
Situaciones y Asistencia.

## Alcance

- Planificador y Gantt compartido con aceptación principal en macOS.
- Shell, Situaciones y Asistencia macOS.
- Método de lectura aditivo en `KmpBridge`.
- Configuración y pruebas unitarias macOS del Planificador.

## Archivos o módulos afectados

- `kmp/iosApp/App/`: modelos, view model, Gantt, Día, Situaciones y bridge.
- `kmp/iosApp/MacApp/`: shell, toolbar, Planificador y Asistencia.
- `kmp/iosApp/PlannerTests/` y configuración XcodeGen.
- Changelog, roadmap, plan y evidencia de validación.

## Cambios realizados

- Carga cancelable y completa de secuencias, con errores explícitos.
- Estados tipados y filtro de atención.
- Carril fijo, timeline única, densidades y periodo contextual.
- Acción `Ubicar (n)` que conserva el identificador del plan.
- Toolbar contextual y controles duplicados ocultos solo en Mac.
- Estados vacíos y acciones de recuperación coherentes.
- Seis pruebas unitarias de proyección y estado.

## Qué no se ha tocado

- KMP/shared, SQLDelight, repositorios y migraciones.
- Diseño interno del Cuaderno.
- UX específica de iPhone.
- Drag & drop o edición directa en el Gantt.

## Riesgos

- La composición con datos reales debe validarse visualmente en los tres anchos y ambos modos de
  apariencia; el entorno no concedió permisos para automatizar esa captura.
- El método nuevo del bridge es solo de lectura y reutiliza el contrato KMP existente.

## Casos probados

- [x] 6 pruebas de `PlannerGanttProjectionTests`, 0 fallos.
- [x] `./scripts/verify_apple_builds.sh`: macOS correcto.
- [x] `./scripts/verify_apple_builds.sh`: iOS Simulator correcto.
- [ ] QA visual/capturas a 900, 1200 y 1600 pt en claro/oscuro.
- [ ] Navegación manual repetida entre los cuatro módulos con datos docentes reales.

## Documentación

- `docs/CHANGELOG.md`
- `docs/ROADMAP.md`
- `plan_correccion_bugs_gantt_macos_2026-07-29.md`
- `docs/audit/validation/planner-gantt-macos-2026-07-29.md`

## Evidencias

Los resultados reproducibles de pruebas y build están documentados en la hoja de validación. No
hay capturas visuales porque macOS rechazó los permisos de Accesibilidad y grabación de pantalla.
