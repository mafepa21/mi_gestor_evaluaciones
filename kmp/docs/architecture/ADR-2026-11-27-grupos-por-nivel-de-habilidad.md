# ADR-2026-11-27 · Grupos por nivel de habilidad y marcas Fuerte / Necesita apoyo

Estado: aceptado (ticket L aprobado en sesión el 2026-11-27; maqueta `docs/maquetas/grupos_nivel_habilidad_2026-11-27.html`).

## Contexto

«Agrupar automáticamente» solo repartía por la media del Cuaderno. El docente de EF quería marcar a mano quién es fuerte y quién necesita apoyo, y repartir por la nota de las rúbricas de técnica, comportamiento y liderazgo. Las rúbricas no tienen un campo «qué mide».

## Decisión

1. Tabla nueva `student_group_marks` (migración 52, solo aditiva) con clave natural `(student_id, class_id)` y campos de sync. La marca es por grupo-clase: un alumno puede ser fuerte en EF de 1º A y no en otro grupo.
2. Quitar la marca guarda `NONE` en vez de borrar: viaja por Sync LAN como un cambio más (LWW por `updated_at`, empate por `deviceId`), sin tombstones.
3. Sync LAN por `SchoolRecordsSync` (entidad `student_group_marks`). Se mandan siempre todas, como las lesiones, para que un aparato actualizado tarde converja.
4. Qué columnas cuentan como Técnica, Comportamiento o Liderazgo **no se guarda en la base**: se sugiere por nombre y tipo de instrumento (`WorkGroupSkillColumns`) y la elección se recuerda en `UserDefaults` por curso y equipo.
5. La nota de cada apartado es la media simple de las columnas elegidas con nota (`gradeValueFor`, 0-10). Las calculadas quedan fuera.
6. Algoritmo `SKILL_LEVEL` en `ComposeWorkGroupsUseCase`: lesionados repartidos → un líder por grupo → comportamiento bajo (< 5) repartido → resto, de más a menos nivel, al grupo más pequeño y con menos nivel acumulado → mezcla de sexos sin mover líderes ni lesionados. La marca «Fuerte» sube el nivel al menos a 8,5 y «Necesita apoyo» lo baja como mucho a 3,5. Determinista. Los criterios anteriores no cambian.
7. Lógica en paquetes propios (`com.migestor.shared.workgroup`, `usecase`); no se toca `shared/domain/`.

## Alternativas descartadas

- Etiquetar rúbricas como «técnica» o «comportamiento» en su esquema: toca rúbricas, sync de rúbricas y su UI; la sugerencia por nombre cubre el caso diario.
- Guardar las marcas solo en el equipo (`UserDefaults`): el docente usa iPad y Mac.
- Borrar la fila al quitar la marca: obligaría a tombstones y a ordenar borrados frente a altas en el mismo lote.

## Consecuencias

- Swift no recibe `Map<Long, …>` de Kotlin (rompe al recorrerlo): notas por apartado en lista (`WorkGroupStudentScore`) y marcas como listas de ids en `WorkGroupSkillRequest`.
- La elección de columnas no viaja entre iPad y Mac; las marcas sí.
- Hay que actualizar iPad y Mac antes de sincronizar; si no, se ponen al día en el siguiente sync tras actualizar.
