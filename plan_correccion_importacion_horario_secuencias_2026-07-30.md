# Plan de corrección: importación de horario y secuencias

Fecha: 2026-07-30
Issue: #179

## Diagnóstico

- Los horarios complementarios de etapas distintas son válidos, pero el flujo anterior solo
  permitía seleccionar un archivo cada vez.
- Datos heredados podían contener varias franjas con el mismo grupo, día y rango horario.
- Importar de nuevo el mismo documento de sesiones creaba una versión adicional aunque su
  SHA-256 fuera idéntico.
- El Gantt cargaba la última versión teórica y recuperaba las sesiones de la copia anterior como
  filas de calendario, produciendo una situación visualmente duplicada.

## Corrección

1. Combinar hasta tres Excel en una previsualización única.
2. Unificar bloques idénticos y resolver todos los solapes antes de escribir.
3. Revertir las franjas creadas si una importación no termina.
4. Detectar y reparar explícitamente franjas duplicadas heredadas.
5. Reutilizar versiones y planes cuando el SHA-256 del documento ya existe.
6. Consolidar en el Gantt versiones heredadas con el mismo SHA-256.
7. Aislar la base de datos del host de XCTest.

## Límites

- No se modifica el esquema SQLDelight ni se añade migración.
- No se elimina automáticamente ninguna versión histórica.
- No se cambia la experiencia específica de iPhone.
- La edición temporal de sesiones sigue pasando por el composer.

## Verificación

- `./scripts/verify_apple_builds.sh`: macOS e iOS Simulator compilados correctamente.
- `MiGestorPlannerTests`: 12 pruebas, 0 fallos.
- La base de producción mantuvo la misma huella, versión y recuentos después de repetir XCTest;
  el host utilizó `MiGestorTests/planner_tests.db`.
