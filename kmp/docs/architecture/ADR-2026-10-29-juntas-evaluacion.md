# ADR-2026-10-29: Juntas de evaluación

## Estado

Aprobado

## Contexto

El tutor prepara la junta de evaluación pasando a papel la Media, las faltas, la inclusión y las incidencias de cada alumno, y redacta el acta después. La app ya tiene esos datos, pero no las notas de las otras materias, ni un sitio para acuerdos por alumno: las reuniones (`meetings`) solo guardan acuerdos generales.

## Decisión

- Módulo nuevo «Juntas» en la sección Evaluación (iPad, Mac e iPhone). Maqueta aprobada: `docs/maquetas/junta_evaluacion_2026-10-28.html`.
- Dos tablas nuevas en la migración 47 (esquema 48), solo aditiva: `evaluation_sessions` y `evaluation_session_students`. DDL idéntico en `47.sqm` y `EvaluationSession.sq`.
- Las suspensas de otras materias se apuntan a mano (0…15). La app solo calcula las de la materia propia (Media < 5, sin redondear, como `countApproved`).
- Una junta por evaluación y grupo (índice único `class_id, evaluation_kind`). Evaluaciones: inicial, 1ª, 2ª, 3ª y final.
- Al cerrar se congelan en una transacción la Media, las faltas, el nivel de medida (solo III/IV) y el nº de incidencias; el acta lee lo congelado. Reabrir conserva lo congelado y lo sobrescribe al volver a cerrar.
- Privacidad: nunca se copian `measure_type` ni `follow_up_notes`; el acta solo lleva el nivel.
- `PRAGMA foreign_keys` está apagado en producción: se leen las filas con `INNER JOIN students`, y `deleteSession`, `deleteClass` y `deleteStudent` borran de forma explícita. Las tablas están en `DatabaseWipe`.
- Ids de texto (UUID) y columnas `device_id`, `sync_version`, `updated_at_epoch_ms`, como los torneos, para poder añadir SyncLAN después.
- Modelos y casos de uso en el paquete propio `com.migestor.shared.evaluationsession`; no se toca `kmp/shared/domain/`.

## Alternativas descartadas

- Importar el Excel de notas del centro: más completo, pero depende del formato de Educamos y multiplica el trabajo. Se puede añadir después.
- Reutilizar `meetings` con un tipo nuevo: obligaría a tocar `MeetingType` en `domain` y no tiene filas por alumno.
- Guardar `academic_year_id` en la junta: ya pertenece al curso a través del grupo; duplicarlo permitiría que no coincidan.

## Consecuencias

- El Mac y el iPad deben actualizarse a la vez: con esquemas distintos SyncLAN responde `schema_mismatch`.
- Una copia de seguridad v48 no se restaura en una app anterior (el control existente lo bloquea).
- Sin SyncLAN en esta versión: la junta vive en el dispositivo donde se crea.
