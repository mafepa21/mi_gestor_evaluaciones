---
name: sqldelight-migration
description: Evoluciona el esquema SQLDelight de forma segura - tablas nuevas, columnas nuevas, índices, migraciones y compatibilidad con datos ya persistidos en dispositivos de docentes. Usar siempre que haya que añadir/cambiar tablas o columnas, cuando una feature necesite persistencia nueva, cuando aparezcan crashes al migrar o al abrir la app tras actualizar, o cuando se toque el directorio kmp/data/src/commonMain/sqldelight. Para bugs de queries/transacciones sin cambio de esquema, usar sqldelight-fix.
version: 1.0.0
---

# sqldelight-migration

## Por qué existe esta skill

Los docentes usan la app a diario con datos reales acumulados (cursos, notas, asistencia, pruebas físicas). Un cambio de esquema mal hecho no rompe la CI: rompe el iPad de un docente en septiembre con tres cursos de historial. El roadmap (Fase 3) exige "migraciones seguras y pruebas de repositorio"; esta skill define qué significa "seguro" en este repo.

## Principios del esquema en este proyecto

1. **Idempotencia por diseño**: el esquema usa `IF NOT EXISTS` en todas las creaciones. No quitarlo nunca; el driver puede re-ejecutar la creación.
2. **Solo evolución aditiva por defecto**: añadir tablas y columnas es seguro; renombrar, cambiar tipo o borrar es destructivo y requiere petición explícita del usuario más plan de migración de datos.
3. **Columnas nuevas siempre con `DEFAULT`**: `ALTER TABLE ... ADD COLUMN ... DEFAULT ...`. Sin default, las filas existentes rompen la lectura tipada. Es la causa nº1 de "crash al migrar" documentada.
4. **Índices acompañan a las queries**: si la query nueva filtra o une por una columna, crear su índice en el mismo cambio (auditoría de rendimiento en `docs/SQLDELIGHT_PERFORMANCE_AUDIT_2026-06-06.md`).
5. **Drivers distintos, mismo esquema**: `DesktopDriver.kt` (JDBC, macOS standalone) y el driver estándar (iOS/Android) deben tragar el mismo `.sq`. No usar features SQL que uno de los dos no soporte.

## Fronteras estructurales que respetar

- **`AcademicYear` es la frontera del trabajo diario** y `StudentEnrollment` conserva el histórico de matrículas sin duplicar alumnado. Cualquier tabla nueva que guarde trabajo docente debe decidir explícitamente si cuelga del curso escolar (se archiva con él) o del alumno global (sobrevive a los cursos). Documentar la decisión en el PR.
- El borrado de un curso archivado elimina grupos/matrículas/datos vinculados pero **conserva el alumnado global** — las FK y cascadas de tablas nuevas deben ser coherentes con ese contrato.
- `PhysicalTests` migrará gradualmente hacia mediciones genéricas (piloto `READING_FLUENCY`); no tocar las tablas físicas hasta que haga falta persistencia compartida (decisión de roadmap).

## Proceso

1. Escribir el cambio `.sq` mínimo siguiendo los principios de arriba.
2. Repasar el impacto en repositorios (`SqlDelightRepositories.kt`): inserciones con `lastInsertedId` van en `db.transactionWithResult { }` (bug histórico `rubricId = 0`).
3. Si el modelo cruza a Swift, coordinar el resto del camino con `kmp-feature-vertical` (contrato `@Throws`, bridge, UI).
4. Simular mentalmente la actualización: base de datos vieja + código nuevo. ¿Toda lectura de columnas nuevas tolera el default? ¿Alguna query asume filas que instalaciones antiguas no tienen?
5. Verificar: `./gradlew :data:desktopTest` siempre; `./gradlew :shared:test` si cambió el contrato. Añadir/actualizar test de repositorio que cubra el camino nuevo — la Fase 3 pide pruebas de repositorio, no solo compilación.
6. Cerrar con `registrar-avance-app`: entrada `Data` en el changelog y ADR si la decisión estructural condiciona el futuro (frontera curso/alumno, nueva cascada, nueva tabla troncal).

## Señales de alarma para pararse y preguntar

- El cambio requiere `DROP`, `RENAME` o cambio de tipo de columna.
- Hay que backfillear datos existentes con lógica no trivial.
- La cascada de borrado alcanzaría datos que el usuario percibe como independientes (alumnado global, histórico de cursos).
- El cambio afecta a tablas que sincroniza SyncLAN: entonces leer también `synclan-debug` (los repositorios implicados necesitan `@Throws` en su contrato).

## Salida esperada

DDL aplicado, decisión de frontera (curso vs. alumno global) justificada, compatibilidad con datos existentes argumentada, índices añadidos, tests de `:data:desktopTest` ejecutados y su resultado.
