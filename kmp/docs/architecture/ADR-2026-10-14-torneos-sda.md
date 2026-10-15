# ADR 2026-10-14: Torneos dentro de la Situación de Aprendizaje

## Estado
Aceptado.

## Contexto
El proyecto TourneyFlow (Swift + SwiftData) generaba torneos con pistas y tiempos. La app ya tenía grupos de trabajo vinculados a SdA (`notebook_work_groups.learning_situation_id`) y un módulo de torneos de EF guardado en UserDefaults, sin sync ni backup.

## Decisión
- El motor de torneos vive en Swift (`kmp/iosApp/AppleShared/Tournament/`), sin SwiftData. No se porta a Kotlin: solo lo usan iOS/iPadOS/macOS.
- Persistencia en SQLDelight: tabla `learning_situation_tournaments` con columnas JSON (`config_json`, `team_snapshot_json`, `schedule_json`, `results_json`, `knockout_results_json`). Entra en SyncLAN y en backups (copia completa del SQLite).
- `learning_situation_id` es opcional: los torneos antiguos migrados pertenecen solo a un curso.
- El módulo antiguo de EF se retira; un migrador idempotente copia sus datos al arrancar y conserva la clave de UserDefaults.
- Los equipos se toman de los grupos de trabajo al crear el torneo (instantánea); si los grupos cambian, se avisa y el docente decide actualizar.

## Consecuencias
- El motor identifica equipos por nombre: los nombres repetidos se desambiguan.
- Compose Desktop no tiene torneos.
- Cambios de esquema futuros en el JSON deben ser tolerantes (campos opcionales, `legacyExtras`).
