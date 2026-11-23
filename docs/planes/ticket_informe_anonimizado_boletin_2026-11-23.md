# Ticket M: Informe anonimizado para comentarios del boletín

Aprobado por el docente el 2026-11-23. Maqueta aprobada: `docs/maquetas/informe-anonimizado-boletin/mockup/index.html`.

## Objetivo

En Informes aparece un tipo nuevo, «Base para boletín». Junta los datos de cada alumno del curso elegido, sin nombres, para pasárselo a una IA que redacte los comentarios del boletín.

## Qué incluye por alumno (dentro del trimestre elegido)

- Asistencia: porcentaje de presencia, faltas, retrasos y faltas justificadas.
- Notas: media y nota de cada columna evaluable, agrupadas por categoría.
- Autoevaluaciones: media de los ítems 1-4 y respuestas abiertas.
- Observaciones: notas de asistencia, incidencias y notas del diario de aula.
- Tendencia: sube, baja o estable cuando hay al menos 4 notas.

## Anonimizado

- Cada alumno pasa a ser «Alumno 01», «Alumno 02»… (orden estable, no alfabético).
- Si un texto nombra a un alumno del curso, el nombre se cambia por su código (o por «[nombre]» si la palabra la comparten varios).
- Se borran correos, teléfonos y fechas.
- No salen datos de inclusión ni de salud.
- La clave código → nombre solo se ve en la app; nunca va en lo que se copia o comparte.

## Salida

- Texto con instrucciones para la IA y una ficha por alumno.
- Botones Copiar, Compartir y Ver clave.
- Aviso de alumnos con pocos datos (menos de 3 notas o menos de 5 días de asistencia).

## Fuera de alcance

- Redactar los comentarios con la IA local dentro de la app.
- Volver a pegar los comentarios en la app usando la clave.

## Modelo de datos

Sin cambios de esquema. Solo lectura de: alumnado de la clase, asistencia, columnas y categorías del Cuaderno, notas, respuestas de instrumentos, incidencias y notas individuales del diario.

## Plan

1. Maqueta con estados (datos, cargando, sin alumnado, sin clase, error, clave) y revisión de diseño.
2. `BulletinBaseReport.swift`: anonimizado y texto, sin KMP (probado con XCTest).
3. `KmpBridge+BulletinBase.swift`: lectura de datos por grupo y periodo.
4. `BulletinBaseReportView.swift` + tipo `ReportKind.bulletinBase` en Informes de iPad (`RubricsReportsWorkspaceViews.swift`) y Mac (`MacModuleStubs.swift`).

## Criterios de aceptación

- El texto exportado no contiene ningún nombre ni apellido del curso.
- Cada alumno sale con su código y sus bloques de asistencia, notas, autoevaluación y observaciones.
- El trimestre elegido filtra los datos.
- La clave se ve en la app y no aparece en lo que se copia o comparte.

## Validación

- Compilar Mac e iPad.
- XCTest: `BulletinBaseReportTests` (anonimizado) y `BulletinBaseBridgeTests` (lectura real en la base de pruebas).
- Solo datos inventados.
