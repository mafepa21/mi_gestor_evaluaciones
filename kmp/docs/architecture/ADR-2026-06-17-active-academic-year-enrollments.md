# ADR-2026-06-17: Curso escolar activo y matriculas de alumnado

## Estado

Aprobado

## Contexto

La app ya tenia `academic_years` y `classes.academic_year_id`, pero la experiencia diaria seguia operando sobre una lista global de grupos y la relacion alumno-grupo vivia en `class_students`. Eso mezclaba cursos, dificultaba archivar historico y obligaba a tratar la promocion de alumnado como copia visual en lugar de como matricula nueva.

## Decision

`AcademicYear` es el concepto canonico de curso escolar. Solo un curso puede estar activo mediante `academic_years.is_active`, y las listas operativas de grupos se filtran por ese curso activo.

El alumno mantiene identidad global en `students`. La pertenencia de un alumno a un grupo y curso se modela como `student_enrollments`, con estado, estado de promocion y `previous_enrollment_id` para enlazar historico. `class_students` queda como compatibilidad temporal de escritura y fallback de lectura durante la transicion.

## Consecuencias

- Crear un curso nuevo no duplica alumnos; crea grupos y matriculas nuevas.
- Las notas, asistencia, celdas de Cuaderno, rubricas e informes siguen vinculados a `class_id`, y el curso se resuelve por `classes.academic_year_id`.
- Las migraciones deben crear un curso activo por defecto y asignar grupos antiguos a ese curso.
- Las pantallas Apple pueden cambiar de curso activo sin introducir una carpeta visual paralela.
