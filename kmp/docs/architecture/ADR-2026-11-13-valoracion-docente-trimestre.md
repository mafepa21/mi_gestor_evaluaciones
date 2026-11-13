# ADR-2026-11-13: Valoración del docente por alumno y trimestre

## Estado

Aprobado

## Contexto

El Comentario LOMLOE se redacta con IA local a partir de cifras y recuentos. Hay trimestres en los que el docente no ha dejado anotaciones durante las clases, y no tenía dónde escribir su valoración cualitativa antes de la evaluación para que la IA la usara (issue #407, parte B).

## Decisión

- Tabla nueva `student_term_teacher_notes` en la migración 49 (esquema 50), solo aditiva. DDL idéntico en `49.sqm` y `AppDatabase.sq`.
- Clave natural `(student_id, class_id, term_key)`, sin id autoincremental. Hay una sola valoración por casilla y la clave es la misma en todos los dispositivos, así que SyncLAN no tiene ids que reconciliar.
- `term_key` es estable (`T1`, `T2`, `T3`) y se deriva de la etiqueta visible con `TeacherTermNoteKeys.fromLabel`. Cambiar la redacción de la etiqueta no pierde datos.
- Cuelga del grupo, y por tanto del curso escolar: se archiva y se borra con él. No es un dato del alumno global.
- `PRAGMA foreign_keys` está apagado en producción: `deleteClass` y `deleteStudent` borran las valoraciones de forma explícita, y la tabla está en `DatabaseWipe` (categorías de cursos y de alumnado).
- Vaciar el texto guarda la fila vacía, no la borra. Así el vaciado también viaja por SyncLAN con la regla normal de "gana lo más nuevo".
- SyncLAN: entidad `student_term_teacher_notes` en `SchoolRecordsSync`. El id del cambio es `alumno|grupo|trimestre`. No se exige que el alumno y el grupo existan al aplicar: en Apple estas entidades se aplican antes que los grupos del mismo lote, y saltarlas sería perder texto escrito por el docente.
- El texto se guarda saneado (sin espacios sobrantes, tope de 2.000 caracteres). Al prompt de la IA entran como mucho 900, colocados al principio para que un recorte por tamaño no se los lleve.
- Privacidad: la valoración es una nota interna. El prompt pide reformularla y no copiarla literal. La redacción por reglas (sin Apple Intelligence) no la incorpora al texto y avisa de que hay que integrarla a mano.
- El modelo y las claves viven en `kmp/shared/domain/Models.kt`, tocado con permiso expreso del usuario, junto a `StudentTutoringSession`, que sigue el mismo patrón.

## Alternativas descartadas

- Reutilizar una columna de texto del Cuaderno: depende de que exista la columna en cada grupo y pestaña, no distingue trimestres y mezclaría una nota privada con celdas que se exportan.
- Guardarla en `UserDefaults` o en un fichero: no entraría en copias de seguridad ni en SyncLAN.
- Id autoincremental como en las tutorías: dos dispositivos podrían crear dos filas para la misma casilla y habría que reconciliarlas.
- Enlazar con `planner_evaluation_periods`: esos periodos cuelgan del horario docente y pueden no existir; la pantalla de Informes ya trabaja con tres trimestres fijos.

## Consecuencias

- El Mac y el iPad deben actualizarse a la vez: con esquemas distintos SyncLAN responde `schema_mismatch`.
- Una copia de seguridad v50 no se restaura en una app anterior (el control existente lo bloquea).
- Una valoración que llegue por sync antes que su grupo queda guardada sin grupo visible hasta que este llegue. Si el grupo no llega nunca, la fila no se muestra en ninguna pantalla.
- La parte A del issue #407 (evidencia por criterio, competencias reales, textos del Cuaderno) queda para otro PR y reutiliza el campo `teacherNote` del contexto.
