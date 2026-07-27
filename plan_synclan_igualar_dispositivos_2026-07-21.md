# Plan: SyncLAN — "Igualar dispositivos" (adopción explícita de datos)

Fecha: 2026-07-21
Rama sugerida: `feat/synclan-adopcion-dispositivos`
Destinatario: subagente Sonnet (Fase 0 + Fase 1). La Fase 2 es un plan aparte, **no** la ejecutes.

---

## 0. Contexto imprescindible (leer antes de tocar nada)

Lee `.agents/skills/synclan-debug/SKILL.md`. Sus límites siguen vigentes:
no abrir `/sync/local-changes` más allá de loopback, no convertir el polling en
mecanismo principal, no introducir sync por internet.

### Topología real (verificada)

```
Mac                                             iPad
┌──────────────────────────────────────┐        ┌────────────────────────────┐
│ App macOS (KmpBridge)                │        │ App iPadOS (KmpBridge)     │
│  └─ escribe DIRECTO en               │        │  └─ escribe en             │
│     desktop_mi_gestor_kmp.db         │        │     mi_gestor_kmp.db       │
│                                      │        │                            │
│ Helper (commandCenterHelper)         │        │  ├─ SSE  /sync/events      │
│  └─ abre EL MISMO fichero .db        │◄──────►│  ├─ GET  /sync/pull        │
│  └─ LocalSyncServer (HTTPS :8765)    │  LAN   │  └─ POST /sync/push        │
│  └─ dbMonitor cada 3 s → SSE         │        │                            │
└──────────────────────────────────────┘        └────────────────────────────┘
```

Ficheros clave:

| Rol | Fichero |
|---|---|
| Servidor HTTPS + Bonjour + SSE | `kmp/data/src/desktopMain/kotlin/com/migestor/desktop/sync/LocalSyncServer.kt` |
| Recolección/aplicación de cambios (solo desktop) | `kmp/data/src/desktopMain/kotlin/com/migestor/desktop/sync/SqlDelightSyncAdapter.kt` |
| Contratos compartidos | `kmp/shared/src/commonMain/kotlin/com/migestor/shared/sync/SyncCoordinator.kt` |
| Proceso helper macOS | `kmp/commandCenterHelper/src/main/kotlin/com/migestor/commandcenter/CommandCenterMain.kt` |
| Ciclo de vida del helper | `kmp/iosApp/MacApp/MacCommandCenterCoordinator.swift` |
| Cliente de sync (iOS+macOS) | `kmp/iosApp/App/KmpBridge.swift` (≈13.000 líneas; zona sync ≈6500–6870, 8720–8860, 10680–11500) |
| SSE cliente | `kmp/iosApp/AppleShared/SyncEventListener.swift` |
| UI emparejamiento/diagnóstico | `kmp/iosApp/AppleShared/SyncPairingViews.swift`, `kmp/iosApp/MacApp/MacSyncView.swift` |
| Driver Apple (punto de intercepción del arranque) | `kmp/data/src/appleMain/kotlin/com/migestor/data/platform/AppleDriver.kt` |

### Por qué HOY no convergen (causas raíz confirmadas)

1. **Asimetría estructural.** El Mac tiene `collectLocalChanges(since)` que recorre
   *toda* la base de datos; con `since = 0` produce un volcado completo. **El iPad no
   tiene equivalente.** Su cola de salida (`pendingOutboundChanges`,
   `KmpBridge.swift:921`) es un diario mantenido a mano: solo se llena cuando alguna
   de las ~30 mutaciones de `KmpBridge` llama a `enqueueLocalChange(...)`
   (`KmpBridge.swift:8739`). Consecuencia: **todo lo que ya existía en el iPad antes de
   emparejar —o que se escribió por una ruta que olvidó llamar a `enqueueLocalChange`—
   no llega nunca al Mac.** Esperar no lo arregla. Mac→iPad sí funciona (full pull con
   `since = 0` al emparejar, al volver a primer plano y cada 180 s,
   `KmpBridge.swift:11038`).

2. **Colisión de espacios de ID.** Ambas DB usan PK autoincrementales `Int64` y el
   protocolo identifica filas por esa PK (`id = "3"`). La aplicación es
   `INSERT OR REPLACE` (`AppDatabase.sq:723`, `:838`, `:1025`…). Dos DB pobladas por
   separado tendrán `class 3` / `student 7` significando cosas distintas: al
   intercambiar datos no se fusionan, **se pisan**. Igualar por el protocolo de
   cambios actual no solo es incompleto: es destructivo.

3. **El LWW es nominal.** `applyIncomingChangesLww`
   (`SqlDelightSyncAdapter.kt:1044`) nunca compara el `updatedAtEpochMs` entrante con
   el de la fila local: hace upsert a ciegas. La única defensa es el tombstone
   (`:1076`). Gana quien empuja el último, no quien editó el último.

4. **`desktopAuthoritative` está muerto.** `LocalSyncServer.encodeAck`
   (`LocalSyncServer.kt:754`) nunca lo emite y `SyncCoordinator` no lo conoce, así que
   la rama de `KmpBridge.swift:6847` ("macOS prevalece, re-pull completo") es
   inalcanzable. Ya existía un intento de "plataforma maestra" sin cablear.

5. **Desfase de reloj.** El cursor del iPad (`lastSyncCursorEpochMs`) se fija con el
   reloj del Mac, pero los `updatedAtEpochMs` de las entidades vienen del dispositivo
   que las escribió. Unos segundos de deriva bastan para que un pull incremental se
   salte cambios; solo el full pull de 180 s los rescata.

**No arregles 1–5 en este plan.** Están aquí para que entiendas por qué la solución
correcta es *adoptar*, no *fusionar*.

---

## 1. Qué construimos

Una operación explícita **"Igualar dispositivos"**: el usuario elige qué plataforma
manda (iPad o Mac) y esa base de datos se replica íntegra en la otra. Al terminar,
ambas son idénticas fila a fila, con los mismos IDs, y el sync incremental existente
vuelve a tener sentido porque parte de un estado común.

Decisiones de diseño (respétalas):

- **Se transfiere el fichero SQLite completo, no un log de cambios.** Reproducir miles
  de cambios con IDs que chocan produce basura; copiar el fichero produce dos DB
  idénticas. Ambas plataformas usan el mismo esquema SQLDelight, así que el fichero es
  portable.
- **Es destructivo por definición.** Backup automático obligatorio del lado perdedor
  antes de sobrescribir, con ruta visible al usuario.
- **Se aplica en el próximo arranque, no en caliente.** Sustituir el `.db` con el
  driver abierto es la forma más rápida de corromper datos. Se deja el fichero en
  *staging* y se intercambia en el arranque, antes de abrir el driver — el mismo
  patrón que ya usa `migrateAppleDatabaseIfNeeded` (`AppleDriver.kt`).
- **El disparador no es "se ha perdido la conexión X tiempo".** Ese heurístico es
  poco fiable (la red se cae constantemente) y el propio usuario dudaba de él. El
  disparador es **divergencia detectada**: se comparan huellas de dataset y, si no
  coinciden tras un ciclo de sync completo, se ofrece igualar. Nunca se destruye nada
  sin confirmación explícita.
- **Siempre hay un botón manual**, para que el usuario no dependa de la detección.

---

## Estado (2026-07-21)

- **Fase −1: HECHA** en la rama `feat/synclan-fix-ruta-db-macos`. Ver "Resultado" al final
  de la fase. Ampliada sobre lo planeado: se descubrió un segundo fallo de pérdida de
  datos (el rescate silencioso de `createAppleDriver`) y se corrigió también.
- **Fases 0 y 1: pendientes**, para el subagente.
- Decisiones del usuario: trabajo secuencial; se acepta el reinicio de la app tras
  igualar; la base de datos del Mac se deja como está (se igualará desde el iPad).

---

## Fase −1 (BLOQUEANTE) — Ruta de base de datos incorrecta en macOS

**Hazlo antes que nada y en su propio commit.** Todo este plan crea copias de
seguridad antes de sobrescribir datos; si el subsistema de copias no funciona, la
adopción es una ruleta rusa.

### El fallo

`AppleBridgeBootstrap.swift:14` declara la ruta de la DB en macOS como
`getMacosAppDataPath(fileName: "mi_gestor_kmp.db")`, pero la app macOS abre
`desktop_mi_gestor_kmp.db` (`MacosDriver.kt:5`). `mi_gestor_kmp.db` es el nombre
*legacy* y además vivía en otro directorio (`MiGestorKMPMac`).

En la máquina del usuario existe un `MiGestor/mi_gestor_kmp.db` **de 0 bytes** (19 de
mayo). Como el fichero existe, `require(fileExists)` pasa y nada lanza excepción: se
copian 0 bytes y se reporta éxito.

Verificado empíricamente en una copia real del 11 de junio:
`databaseSizeBytes: 0`, `schemaVersion: 0`, todos los contadores a 0, y
`checksumSHA256 = e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`
(el SHA-256 de la cadena vacía).

En iOS la ruta sí es correcta; el fallo es exclusivo de macOS.

### Impacto

| Consumidor | Comportamiento real en macOS |
|---|---|
| `AppleBackupService.createBackup` (`AppleBackupService.swift:27`) | Paquete `.migestorbackup` con `database.sqlite` de 0 bytes, reportado como éxito |
| `AppleBackupService.restoreBackup` (`:293–296`) | Escribe sobre el fichero fantasma; la DB real no se toca. Pide reinicio y no cambia nada |
| `SettingsDangerZoneView.wipeAllData` (`:105–133`) | Borra el fantasma (inocuo) pero **sí borra `backups/` y los adjuntos**. Medio destructivo y engañoso |
| `SettingsDiagnosticsView` (`:87`, `:171`, `:187`) | Recuentos y versión de esquema leídos del fantasma ⇒ siempre 0 |

Nota: `MacosBackupService` (`PlatformFactories.macos.kt:16`) tiene el mismo error, pero
**no** lo usa ninguna vista Apple (`KmpBridge.createLocalBackup`/`restoreLocalBackup`,
`KmpBridge.swift:6644–6650`, no tienen ni un solo punto de llamada). El único consumidor
real de `container.backupService` es la app Compose Desktop
(`kmp/desktopApp/.../Main.kt:1405`), que usa `DesktopBackupService`, y esa sí apunta al
fichero correcto.

Contraste revelador: `KmpBridge.getDatabaseURL()` (`KmpBridge.swift:10918–10931`) sí usa
`desktop_mi_gestor_kmp.db`. Hay dos fuentes de verdad para la misma ruta en el mismo
código, y una está mal.

### Qué hacer

1. Corrige `AppleBridgeBootstrap.swift:14` → `"desktop_mi_gestor_kmp.db"`.
2. Corrige `MacosBackupService` (`PlatformFactories.macos.kt:16` y `:44`) al mismo
   nombre, aunque hoy no se use: es una trampa esperando.
3. **Elimina la duplicación**: expón el nombre desde `MacosDriver.kt` (p. ej.
   `fun macosDatabaseFileName(): String = MACOS_DB_NAME`) y que
   `AppleBridgeBootstrap`, `MacosBackupService` y `KmpBridge.getDatabaseURL()` lo
   consulten en vez de repetir literales. Haz lo mismo en el lado iOS con
   `IosDriver.kt`.
4. Sustituye el `require(fileExists)` por una comprobación que además **rechace
   ficheros de 0 bytes o sin cabecera SQLite** (`SQLite format 3\0`), tanto al crear
   como al restaurar. Un backup vacío nunca debe reportarse como éxito.
5. Al arrancar en macOS, si existe `MiGestor/mi_gestor_kmp.db` con 0 bytes, renómbralo
   a `mi_gestor_kmp.db.ghost` y deja traza en consola. No lo borres sin más.
6. Avisa en la UI de copias: si hay paquetes existentes con `databaseSizeBytes == 0`,
   márcalos como **"Copia no válida"** y no permitas restaurarlos.

### Verificación

- Test en `desktopTest` (o test de Swift si encaja mejor): `createBackup` sobre una DB
  con datos produce `databaseSizeBytes > 0` y un checksum distinto del de la cadena
  vacía; `createBackup` sobre una DB de 0 bytes **falla** en vez de reportar éxito.
- Manual en macOS: crear copia → comprobar que `database.sqlite` pesa lo mismo que
  `desktop_mi_gestor_kmp.db`; restaurar esa copia y comprobar que los datos cambian de
  verdad.

Commit aparte, con su entrada propia en `CHANGELOG.md`. Este fallo merece mención
explícita: los usuarios de macOS llevan tiempo generando copias vacías.

### Resultado (2026-07-21)

Hecho, más un segundo fallo descubierto durante la implementación:

**Rescate silencioso en `createAppleDriver` (`AppleDriver.kt:46`).** Cuando el driver no
podía abrir la base de datos, la renombraba a `<nombre>.backup_<epoch>`, **borraba el WAL
y el SHM** y arrancaba con una vacía, sin aviso alguno. En la máquina del usuario había
ocurrido dos veces: 19-jun (27 clases / 309 alumnos) y 13-jul (16 clases / 126 alumnos),
dejando la base activa en 1 clase / 2 alumnos. Borrar el WAL destruía transacciones ya
confirmadas y dejaba la cuarentena incompleta.

Ficheros modificados:

| Fichero | Cambio |
|---|---|
| `AppleDriver.kt` | El rescate mueve `-wal`/`-shm` junto al `.db` en cuarentena en vez de borrarlos |
| `MacosDriver.kt` / `IosDriver.kt` | Nuevas `macosDatabaseFileName()`/`getMacosDatabasePath()` y equivalentes iOS: única fuente de verdad |
| `AppleBridgeBootstrap.swift` | Usa esas funciones en vez de literales |
| `PlatformFactories.macos.kt` | Ruta corregida + rechazo de DB vacía al crear y al restaurar + limpieza de sidecars del destino |
| `KmpBridge.swift` | `getDatabaseURL()` delega en el bootstrap |
| `AppleBackupService.swift` | `validateUsableDatabase` (tamaño + cabecera SQLite) al crear y restaurar; copia de emergencia best-effort; `scanQuarantinedDatabases()` |
| `AppleBackupModels.swift` | `AppleQuarantinedDatabase`; `hasEmptyDatabase` / `isRestorable` |
| `AppleAppRootView.swift` | Aviso único de datos en cuarentena, con recuentos y ruta |
| `BackupHistoryList.swift` | Distintivo "Vacía" y restauración deshabilitada en esas copias |

**Verificación**

Compila y no hay regresiones:

- `:data:compileKotlinMacosArm64`, `:data:compileKotlinIosArm64`,
  `:data:compileKotlinIosSimulatorArm64` → BUILD SUCCESSFUL.
- `./scripts/verify_apple_builds.sh` → macOS ✓ y iOS Simulator ✓ (incluye regeneración
  del proyecto con XcodeGen, necesaria porque `getMacosDatabasePath()` /
  `getIosDatabasePath()` son símbolos nuevos del framework).
- `:data:desktopTest` → 62 tests, 1 fallo
  (`NotebookInstrumentsRepositorySqlDelightTest > saveResponses derives an observation
  grid score`). **Preexistente**: reproducido idéntico con `git stash` de los cambios.

> **Nota de entorno, importante para cualquier sesión futura.** En esta máquina
> `xcode-select -p` apunta a `/Library/Developer/CommandLineTools`, con lo que Kotlin/Native
> falla con `xcrun` código 72 y parece que "no se puede compilar para Apple". El Xcode real
> está en `~/Downloads/Xcode-beta.app`. Basta exportar
> `DEVELOPER_DIR=~/Downloads/Xcode-beta.app/Contents/Developer` (no requiere `sudo` ni
> cambiar la configuración del sistema). `:shared:test` sigue sin poder ejecutarse por
> falta del SDK de Android (`ANDROID_HOME` / `sdk.dir`).

Pendiente de prueba manual (no automatizable aquí):

1. Crear copia en macOS y comprobar que `database.sqlite` pesa lo mismo que
   `desktop_mi_gestor_kmp.db`; restaurarla y comprobar que los datos cambian de verdad.
2. Comprobar que el aviso de cuarentena aparece: la máquina del usuario tiene dos ficheros
   `desktop_mi_gestor_kmp.db.backup_*` que deben dispararlo, con 27 clases / 309 alumnos y
   16 clases / 126 alumnos respectivamente.

---

## Fase 0 — Huella de dataset y detección de divergencia

### 0.1 `SyncDatasetFingerprint` en commonMain

Crea `kmp/shared/src/commonMain/kotlin/com/migestor/shared/sync/SyncDatasetFingerprint.kt`.

`KmpContainer` ya vive en `commonMain`
(`kmp/data/src/commonMain/kotlin/com/migestor/data/di/KmpContainer.kt`) y ambas
plataformas usan los mismos repositorios, así que una única implementación sirve para
Mac e iPad. Si por dependencias de módulo no puede vivir en `shared`, ponla en
`kmp/data/src/commonMain/kotlin/com/migestor/data/sync/`.

```kotlin
data class SyncDatasetFingerprint(
    val schemaVersion: Long,          // AppDatabase.Schema.version
    val countsByEntity: Map<String, Int>,
    val digest: String,               // hash estable del conjunto (ver abajo)
    val computedAtEpochMs: Long,
)
```

- `countsByEntity`: al menos `academic_year`, `class`, `student`, `class_roster`,
  `evaluation`, `grade`, `notebook_tab`, `notebook_column`, `teaching_unit`,
  `planning_session`, `learning_situation`. Usa los repositorios de `KmpContainer`.
- `digest`: hash determinista sobre `"$entity:$id:$updatedAtEpochMs"` ordenado. **No
  uses `hashCode()` de Kotlin** (no está garantizado entre plataformas): implementa un
  FNV-1a de 64 bits a mano en el mismo fichero, en Kotlin puro.
- No metas timestamps de "ahora" dentro del digest.

Tests: `kmp/data/src/desktopTest/kotlin/com/migestor/desktop/sync/SyncDatasetFingerprintTest.kt`
— mismo dataset ⇒ mismo digest; una fila cambiada ⇒ digest distinto; orden de
inserción irrelevante.

### 0.2 Endpoint `GET /sync/fingerprint`

En `LocalSyncServer.start()`, junto a los demás `createContext`. Requiere
`isAuthorized(ex)`. Devuelve el JSON de `SyncDatasetFingerprint`.

### 0.3 Cliente y detección

En `KmpBridge.swift`:

- `LanSyncClient.fingerprint(host:token:pinnedFingerprint:)` → nuevo método junto a
  `pull` (≈línea 11329).
- Nueva propiedad publicada `@Published var syncDivergence: SyncDivergenceReport?`
  junto al resto del estado LAN (≈línea 270).
- Tras **completar** un ciclo `syncNow(forceFullPull: true)` sin error y con
  `pendingOutboundChanges` vacía (`KmpBridge.swift:11002`), pide la huella remota,
  calcula la local y compara. Si difieren, publica `syncDivergence`. Si coinciden,
  ponla a `nil`.
- Si `schemaVersion` difiere entre lados: publica una divergencia de tipo
  `.schemaMismatch` y **bloquea la adopción** con el mensaje "Actualiza ambas apps a
  la misma versión antes de igualar los dispositivos."
- No dispares la comprobación más de una vez cada 60 s.

### 0.4 UI de aviso

Banner no bloqueante en `SyncLanView` (`SyncPairingViews.swift:205`) y en
`MacSyncView` (`MacSyncView.swift:4`):

> "Los datos de este iPad y del Mac no coinciden (12 clases aquí, 3 en el Mac).
> **Igualar dispositivos…**"

El banner nunca actúa solo. Solo abre el flujo de la Fase 1.

---

## Fase 1 — Adopción ("Igualar dispositivos")

### 1.1 Protocolo

Tres endpoints nuevos en `LocalSyncServer`, todos con `isAuthorized(ex)`:

| Método | Ruta | Qué hace |
|---|---|---|
| `GET` | `/sync/snapshot/db` | El Mac genera una copia consistente de su DB y la transmite. |
| `POST` | `/sync/snapshot/db` | El Mac recibe la DB del iPad y la deja en *staging*. |
| `GET` | `/sync/snapshot/status` | Estado de la última adopción (`idle` / `staged` / `applied` / `failed`). |

Detalles:

- **`GET`**: genera la copia con `VACUUM INTO '<ruta_tmp>'` ejecutado por el driver
  (esto sí produce un fichero consistente aunque haya WAL activo; **no copies el `.db`
  a pelo**). Transmite los bytes con `Content-Type: application/x-sqlite3` y cabeceras
  `X-Schema-Version` y `X-Dataset-Digest`. Borra el temporal en un `finally`.
- **`POST`**: valida `X-Schema-Version` contra `AppDatabase.Schema.version`; si no
  coincide → `409 {"error":"schema_mismatch"}`. Escribe el cuerpo en
  `<appData>/pending_adopt.db`, verifica que abre como SQLite válido y que su
  `user_version` cuadra; si no, borra y devuelve `422`. Si todo va bien, escribe un
  marcador `<appData>/pending_adopt.json` con `{sourceDeviceId, schemaVersion, digest,
  stagedAtEpochMs}` y responde `200 {"staged":true}`.
- Límite de tamaño razonable (p. ej. 512 MB) y rechazo con `413` por encima.

### 1.2 Intercambio en el arranque (el corazón del cambio)

En `kmp/data/src/appleMain/kotlin/com/migestor/data/platform/AppleDriver.kt`, dentro de
`createAppleDriver`, **justo después de `migrateAppleDatabaseIfNeeded` y antes de
construir el `NativeSqliteDriver`**, añade `applyPendingAdoptionIfNeeded(basePath, databasePath)`:

1. Si no existe `pending_adopt.json` → return.
2. Copia la DB actual (y sus `-wal` / `-shm`) a
   `<basePath>/backups/<epoch>_pre_adopt_<dbName>`.
3. Borra `<databasePath>`, `-wal` y `-shm`.
4. Mueve `pending_adopt.db` a `<databasePath>`.
5. Borra el marcador y escribe `last_adoption.json` con el resultado y la ruta del
   backup, para que la UI pueda decir "Datos adoptados del iPad · copia de seguridad
   en …".
6. Cualquier fallo a mitad ⇒ restaura desde el backup y deja
   `last_adoption.json` con `status: "failed"` y el motivo. Nunca dejes el sistema sin
   una DB abrible.

Esto sirve igual a iOS y a macOS (ambos pasan por `createAppleDriver`).

Para el **helper**, el intercambio debe ocurrir con el helper parado: ver 1.4.

### 1.3 Flujo en el iPad

En `KmpBridge.swift`, junto a `runLanPullSync` (≈6630):

```swift
enum SyncAdoptionSource { case thisDevice, pairedMac }
func adoptDataset(from source: SyncAdoptionSource) async throws -> SyncAdoptionOutcome
```

- `.pairedMac` → `GET /sync/snapshot/db`, escribe a `pending_adopt.db` en el
  Application Support del iPad, escribe el marcador, devuelve
  `.needsRestart(backupHint:)`.
- `.thisDevice` → genera la copia local (ejecuta `VACUUM INTO` vía el driver; expón un
  método `suspend fun exportConsistentCopy(toPath: String)` en `KmpContainer` o en un
  servicio nuevo en `commonMain` — **no** dupliques lógica de SQLite en Swift) y la
  sube con `POST /sync/snapshot/db`.
- En ambos casos: al terminar, limpia en el iPad `sync.pending.changes.v2`,
  `sync.last.cursor` y `sync.notebook.cache.v1` (`KmpBridge.swift:921–931`). Si no lo
  haces, el siguiente ciclo incremental resucita basura del estado anterior.

### 1.4 Flujo en el Mac

En `MacCommandCenterCoordinator.swift`:

- Cuando el helper reporte adopción en *staging*, o cuando el usuario elija "mantener
  los datos del iPad" desde `MacSyncView`:
  1. Detén el helper (ya existe la maquinaria de ciclo de vida; reutilízala, no la
     dupliques).
  2. Muestra una hoja de confirmación con el resumen ("Se sustituirán los datos de
     este Mac por los del iPad. Se guardará una copia de seguridad en …").
  3. Al confirmar, relanza la app (`NSApp.relaunch`-equivalente: lanzar el bundle y
     `NSApp.terminate`). El intercambio lo hace `createAppleDriver` en el arranque.
- El helper debe emitir una línea de estado nueva para que el coordinador la parsee,
  siguiendo el formato existente de `CommandCenterMain.kt`:
  `[command-center] State: adopt_staged|source=<deviceId>|digest=<...>`.

### 1.5 UI

Una única hoja compartida, `SyncAdoptionSheet`, en
`kmp/iosApp/AppleShared/SyncAdoptionViews.swift` (fichero nuevo), presentada desde
`SyncLanView` y desde `MacSyncView`:

- Paso 1 — **Comparativa**: dos tarjetas lado a lado (Este iPad / Mac "nombre") con los
  contadores de la huella (clases, alumnado, evaluaciones, notas, situaciones de
  aprendizaje) y la fecha del último cambio. El usuario debe poder ver *qué* pierde.
- Paso 2 — **Elección**: "Mantener los datos de este iPad" / "Mantener los datos del
  Mac". Sin opción preseleccionada.
- Paso 3 — **Confirmación destructiva**: texto explícito de qué se sobrescribe, dónde
  queda el backup, y que la app se reiniciará. Botón en rol destructivo.
- Paso 4 — **Progreso y resultado**, con la ruta del backup copiable.

Sigue `GUIA_DISENO_DESKTOP.md` para la variante macOS. Textos en español, tono del
resto de la app.

---

## 2. Qué NO hacer en este plan

- No toques el protocolo incremental (`/sync/pull`, `/sync/push`, `/sync/events`) más
  allá de añadir los endpoints nuevos.
- No abras `/sync/local-changes` fuera de loopback.
- No intentes arreglar las causas 1–5 del apartado 0. Van en la Fase 2.
- No introduzcas sync por internet ni almacenamiento en la nube.
- No borres `pendingOutboundChanges` fuera del flujo de adopción.

---

## 3. Verificación

Obligatorio antes de dar nada por terminado:

```bash
cd kmp && ./gradlew :shared:test :data:desktopTest
./scripts/verify_apple_builds.sh
```

Tests nuevos exigidos:

- `SyncDatasetFingerprintTest` (ver 0.1).
- `LocalSyncServerAdoptionTest` en `kmp/data/src/desktopTest/kotlin/com/migestor/desktop/sync/`:
  `GET /sync/snapshot/db` devuelve un SQLite abrible con el `user_version` correcto;
  `POST` con `X-Schema-Version` incorrecto responde `409`; `POST` con cuerpo no-SQLite
  responde `422` y no deja `pending_adopt.json`; `POST` válido deja marcador y fichero.
- Test del intercambio de arranque (`applyPendingAdoptionIfNeeded`): caso feliz, caso
  de fallo a mitad con restauración desde backup, caso sin marcador (no-op).

Prueba manual (si el entorno lo permite; si no, **regístralo como no probado**):
iPad con datos A + Mac con datos B → igualar eligiendo iPad → reiniciar ambas → los
contadores de la huella coinciden y el banner de divergencia desaparece.

## 4. Cierre

- `CHANGELOG.md` con la disciplina habitual del repo.
- Commits atómicos, formato de scope del repo (`feat(sync): …`, `test(sync): …`).
  Fase 0 y Fase 1 en commits separados.
- Esto cambia el protocolo de sync ⇒ **escribe un ADR** en `docs/` con la decisión
  "adopción por copia de fichero en lugar de fusión por change-log", incluyendo el
  razonamiento sobre colisión de IDs.
- Actualiza `.agents/skills/synclan-debug/SKILL.md`: añade la adopción a la topología
  y una causa conocida nueva ("los datos preexistentes del iPad nunca suben: la cola
  de salida es un diario manual, no un recorrido de la DB").

---

## Fase 2 — (NO ejecutar aquí) Simetría real

Documentado para no perderlo. El arreglo duradero es mover
`SqlDelightSyncAdapter.kt` de `desktopMain` a `commonMain`. Está verificado que no usa
ni una sola API de JVM: solo `KmpContainer` (ya común), `com.migestor.shared.domain`,
`kotlinx.serialization` y `kotlinx.datetime`. Con eso el iPad obtiene
`collectLocalChanges(0)` gratis, el sync pasa a ser simétrico por construcción, y se
puede ir retirando el diario manual de Swift (`enqueueLocalChange` × ~30 puntos de
llamada, `applyPulledChanges` ≈900 líneas, `NotebookSyncCache`). Va con LWW real
(comparar `updatedAtEpochMs` contra la fila local antes de hacer upsert) y con la
eliminación de `desktopAuthoritative`. Rama y plan propios.
