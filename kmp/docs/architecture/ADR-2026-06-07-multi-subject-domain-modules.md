# ADR 2026-06-07 - Modulos de dominio multi-asignatura

## Estado

Aceptada.

## Contexto

La app contiene un core docente general y un vertical de Educacion Fisica avanzado. El dominio KMP ya expone `Subject` y `SchoolClass.subjectId`, pero la persistencia de `classes` no guardaba aun la relacion con asignatura.

## Decision

Reposicionar la superficie Apple como app docente modular multi-asignatura:

- El core docente permanece como navegacion principal.
- Los modulos EF se renombran como modulos de dominio y se muestran mediante perfil docente.
- `classes` persiste metadata academica nullable, incluido `subject_id`.
- `PhysicalTest*` no se renombra ni se elimina; se introduce una capa `AssessmentMeasurement*` para futuras mediciones generales.

## Consecuencias

- La migracion es compatible con datos existentes porque todos los campos nuevos son nullable.
- EF conserva su funcionalidad y pasa a ser un vertical opcional.
- Las futuras plantillas por materia pueden crecer sobre el Cuaderno sin duplicar la logica de evaluacion.
