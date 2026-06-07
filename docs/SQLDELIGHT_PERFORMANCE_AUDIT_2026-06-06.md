# Auditoria SQLDelight Performance - 2026-06-06

## Contexto

La app esta en version interna `0.3.0-dev`. No se modifica versionado ni se prepara tag de release. El objetivo de esta auditoria es reducir lecturas amplias en consultas de uso diario y dejar los cambios separados por dominios para facilitar PRs pequenos y revision futura.

## Hallazgos

- `attendance` e `incidents` filtraban por clase, fecha o alumno sin indices compuestos acordes a sus listados diarios.
- `planned_session`, `planner_session` y `teacher_schedule_slots` tienen consultas frecuentes por rango, grupo, slot y dia que necesitaban indices especificos.
- El repositorio de notas buscaba una celda con una consulta amplia por alumno y clase y filtraba por columna en Kotlin.
- Planner resolvia slots cargando horarios completos y filtrando en memoria.
- Rúbricas, enlaces de competencias y learning situations tenian consultas ordenadas por FK/version sin indice compuesto explicito.
- `notebook_cell_entries` y `notebook_cell_audit_events` necesitaban indices para borrado por columna y lectura de historial de celda.

## Decision

- Crear migraciones secuenciales `26.sqm`, `27.sqm` y `28.sqm` para separar indices de uso diario, planner/horarios y rubricas/learning situations.
- Mantener `CREATE INDEX IF NOT EXISTS` como patron idempotente del proyecto.
- Reflejar los indices tambien en los `.sq` base para instalaciones nuevas.
- Cambiar solo consultas internas de repositorio, sin tocar contratos de dominio, SwiftUI, KMP shared ni `KmpBridge.swift`.

## Verificacion esperada

- Ejecutar `cd kmp && ./gradlew :data:desktopTest`.
- Mantener el PR body con pruebas ejecutadas, pruebas no ejecutadas, riesgos y cambios no realizados.
