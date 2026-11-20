# Ticket · Portal del alumnado · Fase 3A: Base operativa

- **Estado**: Borrador pendiente de `APROBADO` (no se toca código de producción hasta aprobación)
- **Fecha**: 2026-11-20
- **Rama**: `codex/portal-alumnado-fase3a-base-operativa`
- **Repos afectados**: **solo `mi_gestor_evaluaciones`** (SwiftUI / `kmp/iosApp/AppleShared/`). Cero cambios en `entregas-alumnado`, `portal.php`, KMP ni SQLDelight.
- **Maqueta interactiva**: [portal_alumnado_fase3a_base_operativa_2026-11-20.html](../maquetas/portal_alumnado_fase3a_base_operativa_2026-11-20.html)
- **Dependencias previas**: Fase 1 (Cuentas y Para hacer), Fase 2 (Mis notas, PR #420) y Fase 3B (Torneos, PR #421), ya fusionadas en `main`.

---

## 1. Problema y objetivo

Con el portal ya publicado y operativo en `https://projectosef.alwaysdata.net/`, quedan tres fricciones operativas muy reales del día a día docente antes de abrir módulos nuevos:

1. **Altas en clase sin correo**: hoy el alta masiva depende de Borradores de Mail en macOS. En Primaria, 1.º ESO o en el iPad en el gimnasio, lo más rápido y fiable es repartir una tarjeta recortable con QR y código de 10 letras.
2. **Confianza antes de publicar**: el docente quiere comprobar con sus propios ojos qué ve un alumno concreto (sus tareas, sus notas visibles con o sin media, su torneo y equipo) sin tener que crearse cuentas falsas ni publicar nada.
3. **Cambio de Mac o formateo sin perder el portal**: hoy `K_tablon` y `accountKey` viven únicamente en el Llavero local (`ThisDeviceOnly`) y fuera del backup cifrado `.migestorbackupx`. Si el docente cambia de ordenador o restaura una copia, tendría que reinvitar a todo el alumnado.

Esta fase cierra los tres frentes con una interfaz mínima (principios `jobs-design-philosophy`: una acción principal por pantalla, cero ruido, rejilla 8pt) y sin relajar ninguna garantía de privacidad ni cifrado.

---

## 2. Alcance cerrado (3 bloques)

### Bloque 1 · Tarjetas QR imprimibles en PDF (Mac + iPad)

- **Entrada**: en `WebPortalSheet` › pestaña `Cuentas`:
  - Botón secundario limpio **«Tarjetas QR en PDF…»** en el pie de la hoja (y también visible en el estado vacío «Aún no has invitado a este grupo», tanto en **Mac** como en **iPad**).
- **Hoja previa (`WebPortalCardsPDFSheet`)**:
  - Permite elegir destinatarios:
    - **«Sin invitar y caducados»** (opción por defecto, no toca cuentas ya activas).
    - **«Solo seleccionados (N)»** (disponible si el docente marcó filas en la tabla).
  - Si la selección incluye alumnos con cuenta ya activa, avisa en una línea clara de que su cuenta actual seguirá funcionando hasta que canjeen el código nuevo.
  - Aviso de custodia visible: *«Cada código sirve una sola vez y caduca en 7 días. Guarda o destruye el PDF tras repartirlo.»*
  - Botón principal único: **«Generar PDF (N tarjetas)»** (llama a `WebPortalInviter.invite` solo al confirmar; si el servidor falla, no genera ningún PDF).
- **Motor PDF (`WebPortalCardsPDFRenderer.swift`)**:
  - Renderizado puro con `CoreGraphics` + `CoreImage` (`CIQRCodeGenerator`, corrección `M`), idéntico en macOS e iPadOS.
  - Formato **A4 vertical** (`595 × 842 pt`), rejilla **2 × 4 = 8 tarjetas por página** con líneas de corte discontinuas.
  - Contenido de cada tarjeta:
    - Nombre del alumno (solo en el PDF local para repartir en aula; **nunca** viaja al servidor).
    - Nombre del grupo (ej. `2º ESO B`).
    - QR con el enlace `#portal/alta=XXXXX-XXXXX`.
    - Código legible en monoespaciada (`XXXXX-XXXXX`).
    - Caducidad exacta (`Caduca el 27 nov`) e instrucción en 2 líneas (*«1. Escanea el QR o entra en la web · 2. Crea tu usuario sin usar tu nombre real»*).
- **Entrega nativa**:
  - **macOS**: `NSSavePanel` para guardar el `.pdf` (y botón rápido de imprimir o abrir en Vista Previa).
  - **iPadOS**: hoja nativa de compartir / imprimir (`ShareSheet` / `UIActivityViewController`).

### Bloque 2 · Vista previa «Ver como este alumno…»

- **Entrada**: menú contextual `•••` de cualquier fila en `WebPortalSheet` › `Cuentas` → **«Ver como este alumno…»** (disponible tanto si la cuenta está activada como si aún está pendiente o sin invitar).
- **Comportamiento (`WebPortalStudentPreviewSheet.swift`)**:
  - 100 % local y de **solo lectura**: no crea invitaciones, no sube ningún dato ni modifica el estado de publicación.
  - Construye los datos con las **mismas funciones reales** que usa el publicador:
    - Tareas (`Para hacer`): misiones abiertas del grupo del alumno.
    - Notas (`Mis notas`): `WebPortalGrades.loadGroup` aplicando exactamente la selección actual de columnas visibles y el interruptor «Mostrar la media».
    - Torneos (`Torneos`): `WebPortalTournaments.loadGroup` aplicando los torneos visibles y la configuración de nombres reales vs «Equipo 1, Equipo 2…», resaltando el equipo del alumno si participa.
  - **Banner superior fijo** (imposible confundir con datos publicados):
    - *«Vista previa local · Así lo vería Ana García ahora mismo (no se ha publicado nada)»*
    - Resumen discreto de visibilidad: ej. `2 tareas · 3 de 6 notas visibles · 1 torneo` (y si no tiene cuenta aún: *«Aún sin cuenta activada»*).
  - **Contenido**: selector segmentado con las 3 secciones reales del portal (`Para hacer`, `Mis notas`, `Torneo`) sobre el papel cálido de cuaderno del portal (`#f2eee1`, tinta `#0f3d2e`) para que el docente reconozca al instante lo que verá el alumno en su móvil.
  - Si el alumno no tiene nada visible (ninguna tarea, ninguna nota activada y ningún torneo activado), muestra el sello «AL DÍA · No tienes nada pendiente», confirmando visualmente que no se filtra ningún dato oculto.

### Bloque 3 · Respaldo cifrado de llaves del portal en `.migestorbackupx`

- **Nuevo componente (`WebPortalBackupVault.swift`)**:
  - Estructura `Codable` (`version: 1`) que encapsula:
    - `alumnosJson`: contenido de `Documentos/EntregasWeb/portal/alumnos.json` (si existe).
    - `notasVisiblesJson`: contenido de `notas-visibles.json` (si existe).
    - `torneosVisiblesJson`: contenido de `torneos-visibles.json` (si existe).
    - `keys`: array de `{ portalId, tablonKeyBase64, pendingKeyBase64? }` leído del Llavero (`com.migestor.portal`).
    - `accountKey`: `WebSubmissionInbox.accountKey` (si existe).
  - Resumen rápido sin exponer secretos (`WebPortalBackupVaultSummary`: `accountCount`, `keyCount`, `hasAccountKey`).
- **Garantías de seguridad estrictas**:
  1. **Solo en `.migestorbackupx` (cifrado)**: `portal-vault.json` solo se añade al ZIP temporal dentro de `AppleBackupService.exportEncryptedBackup(_:to:password:includePortalKeys:)` justo antes de cifrar con PBKDF2-HMAC-SHA256 (600 000 iter.) + AES-256-GCM. El staging temporal se borra siempre en `defer`.
  2. **Cero llaves en claro en disco**: las copias locales `.migestorbackup` en `backupsDirectoryURL` **nunca** contienen `portal-vault.json`. Al importar un `.migestorbackupx` en `importPortableBackup`, `portal-vault.json` se lee a memoria en staging y se **elimina inmediatamente** de `stagedPackageURL` antes de validar y mover al historial local.
  3. **Copias legacy (`.migestorbackup`) inmunes**: ni exportan llaves ni leen un `portal-vault.json` aunque alguien lo inyectase manualmente (si aparece en un paquete legacy, se descarta y elimina).
  4. **Compatibilidad total hacia atrás**: el formato binario `MGEBKP01` no cambia. Copias `.migestorbackupx` antiguas sin `portal-vault.json` siguen importando exactamente igual.
- **UX en `ApplePortableBackupSheets.swift`**:
  - **Al exportar (`EncryptedBackupExportSheet`)**: si el equipo tiene llaves del portal o `accountKey`, aparece un único interruptor (activado por defecto) encima del botón principal:
    - *«Incluir llaves del portal del alumnado»*
    - Subtítulo: *«28 cuentas y clave del buzón · cifradas con esta misma contraseña»*.
  - **Al importar (`PortableBackupImportSheet`)**: tras descifrar e incorporar la copia al historial, si traía `portal-vault.json`, se muestra una vista clara de confirmación antes de cerrar:
    - *«Esta copia incluye las llaves del portal del alumnado (28 cuentas)»*.
    - Si el equipo destino ya tiene llaves del portal distintas, se avisa explícitamente (*«Sustituirá las llaves actuales de este equipo»*) y **«Omitir llaves»** queda como acción por defecto (`keyboardShortcut(.defaultAction)`).
    - Si el equipo destino no tiene llaves del portal todavía (caso habitual al estrenar Mac), **«Restaurar llaves»** importa `K_tablon`, `tablon-pend-*`, `accountKey` al Llavero y escribe los ficheros JSON en `Documentos/EntregasWeb/portal/` con permisos `0o600`.
    - Al cerrar o pulsar «Omitir llaves», el objeto en memoria se descarta.

---

## 3. Archivos previstos (estimación acotada)

### Nuevos en `kmp/iosApp/AppleShared/`
- `WebPortalCardsPDFRenderer.swift` — Generador A4 2×4 (CoreGraphics + CoreImage QR) + `WebPortalCardsPDFSheet.swift` (o dentro del mismo fichero si es compacto).
- `WebPortalStudentPreviewSheet.swift` — Vista previa local de solo lectura del tablón de un alumno.
- `WebPortalBackupVault.swift` — Captura, serialización y restauración segura de llaves y configuración del portal.

### Modificados en `kmp/iosApp/AppleShared/`
- `WebPortalSheet.swift` — Añadir botón «Tarjetas QR en PDF…» en `Cuentas` y acción «Ver como este alumno…» en el menú contextual de fila (manteniendo `minHeight: 340, maxHeight: 560` y `WebPortalSheetLayoutTests` intactos).
- `AppleEncryptedBackup.swift` — Permitir pasar ficheros extra en memoria (`extraEntries: [String: Data]`) a `AppleBackupPackageArchive.createArchive` sin escribir secretos en el paquete origen `.migestorbackup`.
- `AppleBackupService.swift` — Integrar `includePortalKeys` en `exportEncryptedBackup` y extracción + borrado inmediato de `portal-vault.json` en `importPortableBackup` (solo `.encryptedV1`).
- `ApplePortableBackupSheets.swift` — Interruptor de inclusión al exportar y paso de confirmación al importar llaves del portal.

### Tests nuevos en `kmp/iosApp/PlannerTests/`
- `WebPortalCardsPDFRendererTests.swift` — Paginación A4 (1, 8, 9, 25 tarjetas → 1, 1, 2, 4 páginas), dimensiones A4, ausencia de PDF vacío, filtro de destinatarios («sin invitar y caducados» vs selección).
- `WebPortalStudentPreviewTests.swift` — Fidelidad con columnas ocultas/visibles, media activada/desactivada, torneo oculto/visible y estado vacío «Al día» sin llamadas de red.
- `WebPortalBackupVaultTests.swift` — Round-trip cifrado `.migestorbackupx` con llaves `K_tablon` + `pendingKey` + `accountKey`, verificación de que `backupsDirectoryURL/*.migestorbackup` **no contiene** `portal-vault.json`, rechazo en copias `.migestorbackup` legacy y compatibilidad con copias `.migestorbackupx` antiguas sin bóveda.

### Archivos protegidos que NO se tocan
- `kmp/iosApp/App/KmpBridge.swift`
- `kmp/iosApp/App/EvaluationDesign.swift`
- `kmp/shared/domain/`
- `kmp/data/src/commonMain/sqldelight/`
- `kmp/desktopApp/`
- Todo el repo `entregas-alumnado`

---

## 4. Plan de verificación

1. Tests unitarios macOS (`MiGestorKMPMac`):
   - `WebPortalCardsPDFRendererTests`
   - `WebPortalStudentPreviewTests`
   - `WebPortalBackupVaultTests`
   - Toda la batería existente `WebPortal*Tests` (7 suites) + `AppleEncryptedBackupTests`
2. Compilación completa `MiGestorKMPMac` y `MiGestorKMPiOS` (simulador con DerivedData temporal en `/tmp` que se borra al terminar).
3. Verificación manual de layout (Jobs Design Philosophy: Bizqueo, Aire, Obviedad) y comprobación de que `WebPortalSheetLayoutTests` pasa sin cambios de altura máxima.
4. Registro de cierre con `registrar-avance-app`: `docs/CHANGELOG.md`, `kmp/docs/architecture/ADR-2026-11-18-portal-alumnado-cuenta-propia.md`, `docs/ambitos/entregas-web.md` y PR limpio en `mafepa21/mi_gestor_evaluaciones`.

---

## 5. Criterios de aceptación

- [ ] Desde `WebPortalSheet` › `Cuentas` (en Mac y en iPad) se puede generar un PDF A4 con 8 tarjetas QR recortables por página para alumnos sin invitar/caducados o seleccionados, con códigos válidos en el servidor y aviso de custodia.
- [ ] Desde el menú de cualquier alumno se abre «Ver como este alumno…» mostrando exactamente lo que vería (Para hacer, Mis notas y Torneo) sin publicar ni tocar el servidor.
- [ ] Al exportar una copia cifrada `.migestorbackupx` se incluyen opcionalmente (ON por defecto) las llaves y configuración del portal; al importarla en otro equipo se ofrece restaurarlas al Llavero, y **nunca** quedan llaves en claro en `.migestorbackup` ni se aceptan desde copias legacy sin cifrar.
- [ ] Todas las suites `WebPortal*Tests` y `AppleEncryptedBackupTests` pasan en verde, y compilan tanto `MiGestorKMPMac` como `MiGestorKMPiOS`.
