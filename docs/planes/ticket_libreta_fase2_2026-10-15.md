# Ticket L · Libreta fase 2: clase y copias de Seguridad

- **Tamaño:** L (toca copias de Seguridad, cambia el modelo SwiftData y engancha tres módulos).
- **Rama:** `codex/libreta-fase2` (worktree `.worktrees/libreta-fase2`), cortada de `codex/libreta-integrada` (`98a21d49`), porque la fase 1 aún no está en `main`. Su PR va después del de la fase 1.
- **Maqueta:** `docs/mockups/libreta-fase2/mockup/index.html`.
- **Estado:** pendiente de «APROBADO».

## 1. Objetivo y contexto

En la fase 1 la Libreta quedó suelta: no sabe de qué clase es cada libreta y no entra en las copias de Seguridad. Esta fase hace dos cosas:

1. **Clase:** ligar una libreta a una clase de Mi Gestor y abrirla desde el Diario de aula y el Planner de esa clase.
2. **Copias:** que las copias de Seguridad del iPad guarden y restauren también las libretas.

Nombres: en la Libreta, «Grupo» sigue siendo la balda. La clase de Mi Gestor se llama «Clase» para no confundirlas.

## 2. Alcance

**Clase**
1. Campo nuevo en `Notebook`: `linkedClassId: Int64?` (opcional, `nil` por defecto).
2. Menú de lomo y portada: submenú «Clase» con «Ninguna» y las clases de Mi Gestor.
3. «Nueva libreta»: fila «Clase» opcional.
4. Lector: etiqueta pequeña con el nombre de la clase bajo el título.
5. Diario de aula (inspector de sesión, iPad): fila «Abrir libreta».
6. Planner (menú «•••» de la ficha de sesión, iPad): «Abrir libreta de la clase».
7. Abrir desde Diario o Planner: abre a pantalla completa la libreta de esa clase usada más recientemente. Si no hay, aviso «X no tiene libreta» con «Crear libreta»: la crea con el nombre de la clase, ligada, y la abre.

**Copias de Seguridad**
8. Al crear una copia en el iPad, se añade la carpeta `libreta/` al paquete:
   - una instantánea coherente de la base (`Libreta.sqlite`, con la API de copia de SQLite);
   - la carpeta de dibujos e imágenes grandes de SwiftData (`.Libreta_SUPPORT`).
   Todo con su suma de control (checksum) en `checksums.json`.
9. Resumen de la copia: campo opcional `libretaCount`. Etiqueta «Libretas N» en el historial y fila «Libretas» en la vista previa de restaurar.
10. Restaurar: si la copia trae `libreta/`, se sustituye la Libreta en la misma operación que el resto (con vuelta atrás si algo falla). Si no la trae (copia antigua o hecha en Mac), las libretas actuales no se tocan.
11. Aviso en la vista previa: «Las libretas volverán a como estaban en la copia. Si la copia no trae libretas, las de ahora se quedan como están.»

## 3. Fuera de alcance

- Libreta en iPhone o Mac, y sincronización por SyncLAN o iCloud.
- Que el Mac guarde o restaure libretas (el Mac no tiene Libreta: ignora `libreta/`).
- Varias libretas por clase con selector (se abre la más reciente; las demás, desde la estantería).
- Renombrar «Grupo» (balda) dentro de la Libreta.
- Tocar KMP, SQLDelight, `KmpBridge.swift` o `EvaluationDesign.swift`.

## 4. Modelo de datos

- **SwiftData (`Notebook`):** `var linkedClassId: Int64? = nil`. Atributo opcional nuevo: SwiftData lo migra solo (migración ligera), sin perder datos.
- **Clases:** solo se guarda el número. El nombre se lee de Mi Gestor (`shellStore.classes`) cada vez. Si la clase ya no existe, la libreta se trata como «sin clase». No se borra nada.
- **Ruta de la base:** `LibretaStorage.storeURL` fija la ruta (Application Support/`Libreta.store`, la misma que hoy usa SwiftData por defecto). La usan la Libreta y el servicio de copias.
- **Paquete de copia:** carpeta nueva `libreta/` con `Libreta.sqlite` y `_SUPPORT/` (copia de `.Libreta_SUPPORT`). Claves nuevas en `checksums.json`: `libreta/...`.
- **Manifiesto:** `AppleBackupSummary.libretaCount: Int?` (opcional: las copias viejas se siguen leyendo). Se cuenta en la tabla `ZNOTEBOOK` de la instantánea.

## 5. Plan

### Fase A · Clase en la Libreta (1 commit)
- `Models.swift`: `linkedClassId`.
- `LibretaClassOption` (id y nombre) y un valor de entorno con las clases. `IOSRootView` lo rellena desde `shellStore.classes`.
- `LibraryShared.swift` (menú del lomo): submenú «Clase». `NewNotebookSheet.swift`: fila «Clase».
- `NotebookReaderView.swift`: etiqueta de clase bajo el título.

### Fase B · Abrir desde Diario y Planner (1 commit)
- `LibretaStore`: petición `openForClass(id:name:)`, al estilo de `SettingsNavigationStore`.
- `LibraryView`: atiende la petición. Abre la más reciente, o muestra el aviso «Crear libreta».
- `DiaryWorkspaceView.swift` (`DiaryInspectorPanel`): fila «Abrir libreta», solo si `.libreta.isAvailableOnThisDevice`.
- `PlannerSessionDetailSheet.swift`: parámetro opcional `onOpenLibreta`. El Mac pasa `nil` y no ve nada.
- `PlannerWorkspaceIOS.swift` e `IOSRootView.swift`: pasan la llamada hasta `openModule(.libreta, classId:)`.

### Fase C · Copias de Seguridad (1 commit)
- `AppleShared/LibretaStorage.swift` (nuevo, solo Foundation): rutas de la base y de su carpeta de apoyo.
- `AppleBackupService.swift`:
  - `createBackup`: si existe la base, instantánea con `materializeSnapshot`, copia de `.Libreta_SUPPORT`, checksums y `libretaCount`;
  - `restoreBackup`: preparar `libreta/` en un sitio temporal y añadir las sustituciones a la misma `AppleBackupRestoreTransaction` (base, `-wal`, `-shm` y carpeta de apoyo). Sin `libreta/`, no se toca;
  - `verifyBackup`: valida `libreta/Libreta.sqlite` con `validateDatabase` si existe.
- `AppleBackupModels.swift`: `libretaCount` opcional.
- `BackupHistoryList.swift` y `BackupRestorePreviewSheet.swift`: etiqueta, fila y aviso, solo si hay dato.

### Fase D · Registro
- CHANGELOG, ROADMAP, ADR (ampliar `ADR-2026-10-15-libreta-swiftdata-propia.md`), ámbito `libreta.md` y nota de PR.

## 6. Agentes

| Paso | Agente | Modelo |
|---|---|---|
| Fases A y B | `worker` | Sonnet, medio |
| Fase C (copias: datos del usuario) | `worker` | Opus (riesgo de pérdida de datos) |
| Si un worker falla dos veces | `architect` | Opus |
| Revisión, sobre todo la fase C | `reviewer` | Sonnet |
| Interfaz frente a la maqueta | `ui-reviewer` | Sonnet |
| Antes del merge | `janitor` | Sonnet |

Skills: `swiftui-native-feature` (A y B), `apple-service-patch` (C) y `registrar-avance-app` al cierre.

## 7. Criterios de aceptación

- [ ] Se puede ligar y desligar una libreta a una clase desde su menú y al crearla.
- [ ] El lector muestra la clase. Sin clase, o con la clase borrada, no muestra nada.
- [ ] Diario (iPad): «Abrir libreta» abre a pantalla completa la libreta más reciente de la clase de la sesión.
- [ ] Planner (iPad): «Abrir libreta de la clase» hace lo mismo.
- [ ] Sin libreta para esa clase: el aviso crea una con el nombre de la clase, ligada, y la abre.
- [ ] En iPhone y Mac no aparece ningún botón nuevo.
- [ ] Una copia hecha en el iPad incluye `libreta/` con checksums válidos y muestra «Libretas N».
- [ ] Restaurar esa copia deja las libretas como estaban, dibujos e imágenes incluidos, tras reiniciar.
- [ ] Restaurar una copia sin `libreta/` (antigua o de Mac) no toca las libretas actuales.
- [ ] La copia de emergencia antes de restaurar también incluye las libretas.
- [ ] Una copia con `libreta/` dañada no se da por válida.
- [ ] Las copias antiguas se siguen leyendo, verificando y restaurando.
- [ ] Sin cambios en KMP, SQLDelight ni archivos protegidos.

## 8. Validación

- `xcodebuild` `MiGestorKMPiOS` (`generic/platform=iOS Simulator`) y `MiGestorKMPMac` (arm64).
- `xcodebuild test` `MiGestorPlannerTests` como regresión.
- Añadir a `PlannerTests/AppleBackupIntegrityTests.swift` una prueba de ida y vuelta de `libreta/` con una base SQLite de prueba (sin SwiftData real). Si no es viable en ese target, se explica.
- QA en iPad, cuando haya simulador o el usuario pruebe en el suyo: ligar, abrir desde Diario y Planner, crear copia, borrar una libreta, restaurar, reiniciar y comprobar.
- Solo datos de prueba.

## 9. Riesgos y puertas humanas

- **Pérdida de datos al restaurar:** es lo más delicado. Mitigación: la misma transacción con vuelta atrás que ya usa la base principal, copia de emergencia previa y no tocar nada si la copia no trae `libreta/`. **Puerta humana:** el usuario prueba restaurar en su iPad con datos de prueba antes de usarlo en serio.
- **Carpeta de apoyo de SwiftData (`.Libreta_SUPPORT`):** el nombre lo decide Core Data y no es una API pública. Si no existe, se copia vacía. Hay que comprobarla en un iPad real.
- **Restaurar con la Libreta abierta:** igual que con la base principal, se pide reiniciar la app (`needsRestart`).
- **Tamaño:** los dibujos e imágenes hacen las copias más grandes. Se guardan 5 copias, como ahora.
- **Migración SwiftData:** el campo es opcional, así que la migración es automática. Riesgo bajo, pero se prueba abriendo una base de la fase 1.
- **Dependencia:** esta rama sale de la fase 1. **Puerta humana:** fusionar primero la fase 1.

## 10. Entregables

- Código de las fases A, B y C en commits atómicos.
- Maqueta aprobada, ticket, CHANGELOG, ROADMAP, ADR ampliado y ámbito actualizado.
- PR hacia `main` tras la fusión de la fase 1, con las comprobaciones hechas y las pendientes.
