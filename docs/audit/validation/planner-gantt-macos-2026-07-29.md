# Evidencia de validación: Planificador y Gantt macOS

Fecha: 2026-07-29  
Plataforma de aceptación: macOS

## Pruebas automatizadas

Target: `MiGestorPlannerTests`

- `PlannerGanttProjectionTests`: 6 pruebas ejecutadas, 0 fallos.
- Cobertura funcional: estados diferenciados, secuencia sin agendar, cancelaciones como atención,
  métricas compacta/estándar, cruce de año ISO y ventana móvil de 13 semanas.
- Resultado: `** TEST SUCCEEDED **`.
- Resultado local: `/tmp/migestor-planner-tests/Logs/Test/`.

## Compilación

Comando:

```sh
./scripts/verify_apple_builds.sh
```

Resultado:

- macOS: compilado correctamente.
- iOS Simulator: compilado correctamente como garantía de compatibilidad de vistas compartidas.
- XcodeGen: proyecto regenerado correctamente.

La primera ejecución aislada no pudo resolver paquetes por bloqueo de red del sandbox. Se repitió
con acceso autorizado a GitHub y terminó en verde; no fue un fallo de código.

## QA visual

Se abrió la build macOS generada para iniciar la revisión. La automatización no pudo inspeccionar,
redimensionar ni capturar la ventana porque el proceso no tenía:

- acceso de Accesibilidad para `osascript`;
- permiso de grabación de pantalla para `screencapture`.

Por tanto quedan pendientes de comprobación manual y de captura:

- anchos de 900, 1200 y 1600 pt;
- modo claro y oscuro;
- densidades compacta y estándar;
- datos reales con grupos retrasados, cancelaciones y sesiones sin ubicar;
- navegación repetida Cuaderno ↔ Planificador ↔ Asistencia ↔ Situaciones.

No se adjuntan capturas falsas ni capturas de otra plataforma.
