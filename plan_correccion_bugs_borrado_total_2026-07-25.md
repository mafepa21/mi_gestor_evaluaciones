# Plan de corrección — crash y agujeros de "Borrar todos los datos" (2026-07-25)

Rama: `fix/borrado-total-seguro`, desde `origin/main` (`d3932fd`).
Origen: crash reproducible en macOS (SIGABRT) al confirmar `BORRAR` en Ajustes › Zona de Riesgo, con traza de Xcode aportada por el usuario.

---

## 1. Diagnóstico

### Qué pasa exactamente

`SettingsDangerZoneView.wipeAllData()` borra del disco `desktop_mi_gestor_kmp.db`, `-wal` y `-shm` **mientras el driver de SQLDelight los tiene abiertos**. Nadie cierra el driver: `AppleBridgeBootstrap.current()` crea el `NativeSqliteDriver` y no existe API para cerrarlo.

Eso produce, en orden, exactamente lo que muestra el log del usuario:

1. `BUG IN CLIENT OF libsqlite3.dylib: vnode unlinked while in use` + `invalidated open fd` — un fd por cada conexión del pool.
2. La siguiente consulta contra esos fds huérfanos falla con `SQLITE_IOERR`.
3. La dispara `DashboardRepositorySqlDelight.getStats()`, invocada como `suspend fun` desde Swift.
4. `DashboardRepository.getStats()` **no estaba anotada `@Throws`**. Kotlin/Native no puede convertir `SQLiteExceptionErrorCode` en `NSError`, imprime *"Exception doesn't match @Throws-specified class list…"* y **aborta el proceso** (`Kotlin_ObjCExport_runCompletionFailure` → SIGABRT).

### Estado previo en `main`

Este crash ya se había atacado **dos veces, por síntomas**, en las horas previas:

- `10a787c` — `KmpBridge.stopBackgroundSyncWork()` al empezar el borrado (cancela 7 tareas + listener SSE).
- `1b704cb` (PR #160) — guards de `!AppleBackupService.shared.needsRestart` en `syncNow`, `onAppDidEnterBackground`, `checkLocalDbFileModification` y el bucle de auto-sync.
- `469e092` — relanzado automático de la app en macOS tras el borrado.

Los tres son correctos y se conservan, pero mientras el borrado siguiera destruyendo el fichero bajo el driver, **cada ruta nueva que tocara la base tras borrar era un crash en potencia**, y había que taparlas de una en una. El propio `docs/CHANGELOG.md` dejaba registrado como *"riesgo relacionado, no resuelto"* el helper de macOS.

### Agravante: un segundo proceso con la BD abierta

`MacCommandCenterCoordinator` lanza el helper de sincronización con `--db-path .../desktop_mi_gestor_kmp.db`. El log del usuario lo confirma durante el borrado (`[Pairing] helper launched`, `[Sync] helper ready … starting listener`), y la propia app Mac actúa además de cliente de su propio helper (`127.0.0.1:8765/sync/pull`). El helper mantiene abierto el vnode borrado y/o recrea un fichero nuevo en esa ruta.

### El borrado no sobrevivía al reinicio

No desemparejaba, no borraba `sync.last.cursor` ni el token. Tras reiniciar, el primer pull podía **resucitar los datos** desde el iPad emparejado.

### Lo que el borrado dejaba sin borrar

| Qué | ¿Se borraba? |
|---|---|
| `*.db`, `-wal`, `-shm` | Sí (mal: en caliente) |
| `backups/`, `NotebookEvidence/` | Sí |
| `LearningSituations/` | **No** |
| `*.backup_<epoch>` en cuarentena | **No** — copias íntegras de todos los datos |
| `*.rescue_marker` | **No** |
| Token/host/fingerprint + cursor de sync | **No** |

### Bug adicional en la misma pantalla

`clearAppCache()` borra todo el contenido de `.cachesDirectory`. La app de macOS **no está en sandbox**, así que eso es `~/Library/Caches` del usuario entero — cachés de Safari, Xcode y cualquier otra app — bajo un botón que dice "No afecta a tus datos".

### Mismo patrón en dos sitios más

`AppleBackupService.restoreBackup` y `AppleDatabaseRescueService.retryRescuedDatabase` borran/sustituyen la BD activa en caliente con `removeItem` + `copyItem`. Sobrevivían por suerte, no por diseño.

---

## 2. Estrategia

**Dejar de borrar ficheros bajo un driver vivo. Vaciar el contenido *por SQL* con la conexión que ya está abierta.** Un `DELETE FROM` de todas las tablas en una transacción no invalida ningún fd, no puede fallar por E/S y deja esquema y `user_version` intactos.

---

## 3. Fixes aplicados

| # | Commit | Qué |
|---|---|---|
| F4 | `fix(kmp): anotar @Throws las suspend fun expuestas a Swift…` | 208 de 232 `suspend fun` de `Contracts.kt` sin anotar; un fallo de BD abortaba el proceso en vez de propagarse. Cambio puramente aditivo. |
| F1 | `fix(apple): borrar todos los datos por SQL…` | Nuevo `DatabaseWipe.kt` + `KmpContainer.wipeAllData()` + `KmpBridge.wipeAllDatabaseData()`. Elimina la causa raíz. Nuevo `DatabaseWipeTest` (3 tests). |
| F2 | `fix(sync): desemparejar y parar el helper…` | `unpairLanSync()` + `.appleCommandCenterStopRequested` antes de vaciar. Borrado local al dispositivo, no se propaga al iPad. |
| F3 | `fix(apple): incluir situaciones de aprendizaje, cuarentenas y marcador…` | Cierra los tres agujeros de la tabla de arriba. |
| F6 | `fix(apple): limitar la limpieza de caché…` | macOS se acota a `~/Library/Caches/<bundle id>`. |
| F7 | `fix(apple): sustituir la base de forma atómica…` | `replaceItemAt` en restaurar copia y rescate. |

**F5 (frenar el trabajo de fondo) no se aplica**: `main` ya lo trae vía `stopBackgroundSyncWork()` y los guards de `needsRestart` de PR #160. Se conserva tal cual.

### Decisiones tomadas (aprobadas por el usuario antes de aplicar)

1. **El borrado es local a este dispositivo.** Desempareja, pero no genera tombstones ni propaga la eliminación al iPad: un borrado accidental en el Mac no debe vaciar remotamente el otro dispositivo. Si se vuelve a emparejar con un iPad que aún tiene los datos, volverán. El diálogo lo advierte.
2. **`@Throws` en las 232**, no solo en la ruta del crash.
3. **Caché acotada** en macOS, no retirada.
4. **Sin copia de emergencia** previa al borrado: sigue siendo irreversible por diseño.

### Nota sobre archivos protegidos

`kmp/iosApp/App/KmpBridge.swift` está en la lista de protegidos de `AGENTS.md`. Se le añade **un único método** de 3 líneas (`wipeAllDatabaseData()`) porque `container` es privado y la vista no puede alcanzarlo sin abrir un driver nuevo por su cuenta, que es justo lo que se quiere evitar. PR #160 ya había tocado este archivo por este mismo bug.

---

## 4. Verificación ejecutada

- `:data:desktopTest --tests DatabaseWipeTest` → **3/3 en verde**. Cubre: todas las tablas a 0; esquema y `user_version` intactos; **el mismo driver sigue usable tras borrar** (con el borrado por fichero, fallaba con `SQLITE_IOERR`); idempotencia sobre base vacía.
- `:shared:compileKotlinMacosArm64` y `:data:compileKotlinMacosArm64` → sin errores (confirma que los overrides heredan `@Throws` sin `INCOMPATIBLE_THROWS_OVERRIDE`).
- `xcodebuild -scheme MiGestorKMPMac -configuration Debug -destination 'platform=macOS,arch=arm64'` → `BUILD SUCCEEDED`, ejecutado sobre el estado de **cada** commit, no solo el final.
- `:data:desktopTest` completo → **89/90**. El único fallo (`NotebookInstrumentsRepositorySqlDelightTest > saveResponses derives an observation grid score and it counts toward the average`) es **preexistente**: se reproduce idéntico en un worktree limpio de `origin/main` (`d3932fd`) sin ninguno de estos cambios. No lo introduce ni lo arregla esta rama.
- `:shared:desktopTest` → `BUILD SUCCESSFUL`.
- `xcodebuild -scheme MiGestorKMPiOS -configuration Debug -destination 'generic/platform=iOS Simulator'` → `BUILD SUCCEEDED` (los cambios de `AppleShared/` son compartidos con iOS).

### Lo que NO se ha verificado

- **No se ha ejecutado la app y borrado datos de verdad.** La comprobación definitiva (consola sin `SQLITE_IOERR` ni `vnode unlinked`, y que los datos no vuelvan tras reiniciar con el iPad emparejado) requiere una sesión manual con los dos dispositivos. Es la única prueba que cierra el bug original de extremo a extremo.
- **El efecto en runtime de `@Throws` no se ha observado**, solo compilado. La cabecera ObjC generada es idéntica con y sin la anotación (toda `suspend fun` lleva ya `NSError` en el completion handler); lo que cambia es la conversión en runtime. Es el mecanismo documentado de Kotlin/Native, pero aquí se apoya en la documentación, no en una observación directa.
- **No hay test del borrado en Swift** (el repo no tiene tests Swift): `performWipe()` se ha verificado compilando y por inspección, no ejecutándose.
