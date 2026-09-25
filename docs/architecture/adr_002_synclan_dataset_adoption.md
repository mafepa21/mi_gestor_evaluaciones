# ADR 002: Adopción explícita de snapshot completo SQLite frente a fusión de changelogs en SyncLAN ("Igualar dispositivos")

- **Fecha:** 2026-09-10
- **Estado:** Aprobado e implementado (Fase 0 y Fase 1)
- **Contexto del proyecto:** Mi Gestor Evaluaciones (KMP + SwiftUI + SQLDelight)

---

## 1. Contexto y Problema

Mi Gestor Evaluaciones utiliza un subsistema de sincronización local en red de área local (SyncLAN) para comunicar la estación de trabajo principal en macOS (que ejecuta `commandCenterHelper` como servidor HTTPS/SSE) y una o más instancias móviles en iPadOS.

Durante el análisis del comportamiento de sincronización con situaciones de aprendizaje, evaluaciones importadas y datos preexistentes, se identificaron dos problemas estructurales graves que impedían la convergencia de datos entre dispositivos:

1. **Asimetría estructural en la recolección de cambios:**
   - En macOS, `SqlDelightSyncAdapter.collectLocalChanges(since)` puede recorrer la base de datos completa; con `since = 0` genera un volcado completo de todas las entidades.
   - En iPadOS no existía un adaptador equivalente en KMP común. Su cola de salida (`pendingOutboundChanges` en `KmpBridge.swift`) es un diario en memoria/disco poblado manualmente en cada una de las ~30 mutaciones de alto nivel de Swift mediante `enqueueLocalChange(...)`.
   - **Consecuencia:** Cualquier dato creado en el iPad antes del emparejamiento, o escrito por rutas de importación u optimizaciones que omitieran llamar a `enqueueLocalChange`, **nunca** se transmitía al Mac. El sync incremental posterior no podía recuperarlos jamás.

2. **Colisión en el espacio de claves primarias autoincrementales:**
   - Ambas bases de datos SQLite utilizan identificadores autoincrementales de 64 bits (`Int64` / `INTEGER PRIMARY KEY AUTOINCREMENT`) para todas las entidades principales (`academic_year`, `class`, `student`, `evaluation`, `grade`, etc.).
   - El protocolo incremental transmite registros identificados por esa clave primaria local (por ejemplo `id = "3"`).
   - Al aplicar cambios remotos, el sistema ejecuta sentencias `INSERT OR REPLACE` en SQLDelight.
   - Si dos dispositivos se han utilizado de forma independiente antes de sincronizarse, `class 3` o `student 7` en el iPad representan entidades completamente distintas a `class 3` o `student 7` en el Mac.
   - **Consecuencia:** Intentar "reproducir" o "fusionar" los registros incrementales de un dispositivo sobre el otro no los combina: **los sobrescribe y corrompe los grafos relacionales**. La fusión por change-log en este contexto es destructiva.

3. **Inoperancia de LWW (*Last-Write-Wins*) nominal:**
   - La función `applyIncomingChangesLww` en el adaptador no contrastaba `updatedAtEpochMs` contra las marcas de tiempo locales antes del upsert; ganaba simplemente el último paquete recibido, y la deriva de reloj entre dispositivos agravaba la pérdida de modificaciones recientes.

---

## 2. Decisión Arquitectónica

Se decidió implementar un mecanismo explícito y guiado de **"Igualar dispositivos"** basado en la **adopción de snapshot íntegro de la base de datos SQLite**, complementado por una **huella determinista de dataset** para detección de divergencia.

Se descarta expresamente la fusión heurística de changelogs entre dispositivos con historias de base de datos desalineadas.

### 2.1. Huella determinista de integridad (`SyncDatasetFingerprint`)
- Implementada en `kmp/data/src/commonMain/kotlin/com/migestor/data/sync/SyncDatasetFingerprint.kt`.
- Inspecciona 11 entidades clave de la base de datos (`academic_year`, `class`, `student`, `class_roster`, `evaluation`, `grade`, `attendance_record`, `tutoring_incident`, `tutoring_interview`, `rubric_template`, `planner_session`).
- Extrae recuentos de filas, la marca máxima de actualización (`maxUpdatedAtEpochMs`) y un hash determinista de 64 bits (algoritmo **FNV-1a**) calculado sobre tuplas canónicas ordenadas `(id, name/title/description, updatedAtEpochMs)`.
- Se expone mediante el endpoint seguro `GET /sync/fingerprint` en `LocalSyncServer.kt` y en Swift a través de `LanSyncClient.fingerprint()`.
- Permite detectar de inmediato si los dos dispositivos están sincronizados fila a fila, si hay divergencia de datos o si existe un desajuste de versión de esquema (`schemaMismatch`).

### 2.2. Adopción íntegra de snapshot SQLite (`VACUUM INTO`)
- Para igualar dispositivos, el dispositivo elegido como **fuente autoritativa** genera una copia snapshot consistente mediante `VACUUM INTO` (método `KmpContainer.exportConsistentDatabaseCopy`). Esto garantiza que la copia binaria no contenga transacciones parciales ni bloqueos WAL.
- La transferencia del fichero SQLite íntegro se realiza a través de `GET /sync/snapshot/db` (cuando el iPad adopta los datos del Mac) o `POST /sync/snapshot/db` (cuando el Mac adopta los datos del iPad).
- El servidor y el cliente aplican estrictas validaciones de seguridad:
  - Límite de tamaño máximo del payload (512 MB).
  - Comprobación de cabecera mágica binaria de SQLite (`SQLite format 3\0`).
  - Verificación de cabecera `X-Schema-Version`: si la versión del esquema de la base de datos no coincide exactamente con el valor esperado (`AppDatabase.Schema.version`), se rechaza con `HTTP 409 Conflict`.
  - Verificación de `PRAGMA user_version` en el fichero recibido.

### 2.3. Intercambio atómico en el arranque con copia de seguridad y rollback (`AppleDriver.kt`)
- Para evitar la corrupción de datos que ocurriría si se sobrescribe el archivo `.db` mientras las conexiones SQLite están abiertas y en caché, la adopción se realiza en **modo staging**:
  - El snapshot se deposita en `<basePath>/pending_adopt.db` junto a un manifiesto de metadatos `<basePath>/pending_adopt.json`.
  - La sustitución real se difiere al siguiente arranque de la aplicación, ejecutándose en `applyPendingAdoptionIfNeeded(...)` dentro de `AppleDriver.kt` **antes** de abrir el driver `NativeSqliteDriver`.
- **Protocolo de seguridad en 4 fases durante el arranque:**
  1. **Copia de seguridad preventiva obligatoria:** Se copian el fichero actual `mi_gestor_kmp.db` y sus ficheros auxiliares `-wal` y `-shm` a `<basePath>/backups/<timestamp>_pre_adopt_<dbName>`.
  2. **Intercambio atómico de ficheros:** Se mueve `pending_adopt.db` sobre `mi_gestor_kmp.db` y se eliminan los auxiliares WAL/SHM obsoletos.
  3. **Verificación de integridad:** Si ocurre cualquier error durante el reemplazo, se dispara inmediatamente un **rollback defensivo** restaurando la copia de seguridad y registrando el incidente en `last_adoption.json` con estado `failed`.
  4. **Limpieza del estado de sincronización:** Al adoptar, se purgan los cursores antiguos y colas previas (`sync.pending.changes.v2`, `sync.last.cursor`, `sync.notebook.cache.v1`) para evitar reenvíos obsoletos.

### 2.4. Experiencia de usuario transparente y no destructiva por descuido
- Se añade un banner reactivo `SyncDivergenceBanner` que alerta de la desalineación tras un ciclo de sincronización sin interferir en el uso diario.
- Se implementa `SyncAdoptionSheet` en SwiftUI con un flujo guiado en 4 pasos:
  1. Comparativa visual de registros, fechas y huellas entre iPad y Mac.
  2. Selección explícita del dispositivo que manda, **sin preselección por defecto** (obliga a una decisión consciente del docente).
  3. Pantalla de confirmación con advertencia de sustitución destructiva y confirmación interactiva escribiendo el nombre del dispositivo de origen.
  4. Progreso de descarga/subida y solicitud de reinicio de la app (con reinicio automatizado en macOS vía `relaunchApp`).

---

## 3. Consecuencias

### Positivas
- **Integridad absoluta garantizada:** Tras la adopción, ambos dispositivos cuentan con una base de datos 100% idéntica (mismos IDs, mismos registros, mismos historiales).
- **Seguridad ante fallos:** El docente nunca puede perder sus datos; si la adopción se interrumpiera o fallara, el arranque restaura automáticamente la copia previa intacta.
- **Restaura la utilidad del sync incremental:** Una vez unificadas las bases de datos con los mismos identificadores, las mutaciones incrementales subsiguientes operan sobre entidades comunes y no generan duplicaciones ni sobreescrituras destructivas.
- **Detección temprana:** La huella FNV-1a permite comprobar en cualquier momento si los dispositivos están sincronizados sin necesidad de descargar todos los registros.

### Desventajas y Compromisos
- **Reinicio requerido:** El usuario debe reiniciar la aplicación en el dispositivo receptor para que el driver cargue la nueva base de datos.
- **Decisión manual:** Requiere que el docente decida qué dispositivo tiene los datos correctos cuando se produce divergencia.
- **Tráfico de red LAN:** Transferir la base de datos completa requiere enviar un archivo de varios megabytes (habitualmente de 5 a 50 MB), lo que toma entre 1 y 4 segundos en red local.

---

## 4. Hoja de Ruta y Próximos Pasos (Fase 2)

Este ADR cubre las Fases 0 y 1 del plan de igualación.

Como trabajo posterior (Fase 2, plan independiente):
- Mover `SqlDelightSyncAdapter.kt` de `desktopMain` a `commonMain`.
- Con ello, el iPad dispondrá de `collectLocalChanges(since = 0)` de forma nativa en Kotlin, eliminando la necesidad del diario manual en Swift (`pendingOutboundChanges`) y dotando al protocolo de simetría real en ambas direcciones.
