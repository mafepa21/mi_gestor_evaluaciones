# ADR-2026-07-30: Importaciones combinadas e idempotentes

## Estado

Aprobado

## Contexto

El horario de un docente puede proceder de varios documentos complementarios. Guardarlos de forma
secuencial impedía validar el conjunto antes de escribir y hacía posible conservar destinos
duplicados heredados. En Situaciones, importar dos veces el mismo documento de sesiones generaba
versiones distintas con el mismo contenido; el Gantt interpretaba las sesiones de la copia anterior
como calendario ajeno a la secuencia actual.

Además, el bundle de pruebas macOS utiliza la aplicación como host. Abrir el driver normal desde
XCTest expone la base real a migraciones o mecanismos de rescate ejecutados por una build de pruebas.

## Decisión

- La configuración inicial acepta un lote de uno a tres Excel y construye una única
  previsualización normalizada.
- La identidad de una franja importada se determina por día, intervalo, tipo y pares
  asignatura-grupo. Los duplicados exactos se unifican y los solapes de un mismo grupo bloquean el
  guardado.
- El guardado de franjas usa compensación: si falla, elimina las franjas creadas durante ese intento.
- Los destinos heredados repetidos solo se eliminan mediante una acción explícita en Ajustes.
- La identidad de una secuencia importada es `(situación, SHA-256)`. Si ya existe, se reutilizan su
  versión y sus planes.
- El Gantt considera equivalentes las versiones históricas con el mismo SHA-256 y proyecta sus
  sesiones sobre el plan más reciente.
- XCTest usa un driver y una ruta propios bajo `MiGestorTests`; producción conserva su driver y ruta.

## Consecuencias

- El docente puede revisar el horario completo antes de confirmarlo.
- Repetir una importación es idempotente y no multiplica secuencias.
- Los datos heredados se vuelven reparables sin una migración destructiva.
- No se eliminan versiones distintas ni se intenta adivinar si dos documentos con hashes diferentes
  representan la misma secuencia.
- El aislamiento de XCTest añade una base local efímera separada, pero evita cualquier impacto sobre
  datos reales.
