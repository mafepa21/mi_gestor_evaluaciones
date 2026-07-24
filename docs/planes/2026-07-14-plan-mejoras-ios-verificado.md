# Plan de mejoras iOS/macOS — versión verificada (2026-07-14)

> Este plan **sustituye** a un análisis externo previo cuyas afirmaciones se
> contrastaron contra el código real. Buena parte de aquel análisis resultó
> falsa o desactualizada (se apoyaba en el SHA `56d0d70` y en detalles
> inventados). Aquí solo se recoge lo verificado.

## Resultado de la verificación

| Afirmación del análisis externo | Veredicto | Evidencia |
|---|---|---|
| `KmpBridge.swift` ≈ 562 KB, god object | ✅ Cierto | 576.547 bytes reales |
| `IPadWorkspaceShell.swift` ≈ 119 KB, god view | ✅ Cierto | 119.762 bytes |
| Guardado individual vs masivo inconsistente | 🟡 Plausible | Coincide con lo documentado |
| Accesibilidad **ausente** | ❌ Falso | 27 archivos usan `accessibilityLabel/Value/Hint`, incluidas celdas del grid |
| Backups **sin implementar** (placeholder 195 B) | ❌ Falso | `AppleShared/BackupCenterView.swift` (349 líneas) + `AppleBackupService` (create/restore/export/validación) |
| `NotebookGeometry.swift` sin `@ScaledMetric` | ❌ Falso | **El archivo no existe**. Sí es cierto que hay 0 usos de `@ScaledMetric` |
| Estado de sync "invisible" | ❌ Matizado | `syncStatusMessage` + `syncPendingChanges` ya se muestran en `DashboardView`; falta un badge no intrusivo en la toolbar |
| `PlannerWorkspaceIOS.swift` ≈ 126 KB | ❌ Desactualizado | Son 61 KB hoy |

## Alcance de ESTA rama (`feat/ios-mejoras-sync-a11y-2026-07-14`)

Solo cambios de **bajo/medio riesgo, quirúrgicos y verificables por lectura**.
No se toca el monolito `KmpBridge` ni la god view en esta rama (ver "Trabajo
futuro").

### Tarea A — Badge de estado de sync en la toolbar (bajo riesgo)

**Objetivo:** indicador no intrusivo `✓ / ⏱ N / ✗` en la toolbar del workspace,
reutilizando estado que YA existe.

**Estado disponible** (no crear estado nuevo):
- `DashboardBridgeStore` en `kmp/iosApp/App/KmpBridgeObservationStores.swift:101`
  expone `syncStatusMessage`, `syncPendingChanges: Int`, `syncLastRunAt: Date?`,
  `pairedSyncHost: String?`.

**Implementación sugerida:**
1. Crear una vista pequeña reutilizable `SyncStatusBadge` (nuevo archivo
   `kmp/iosApp/App/SyncStatusBadge.swift`) que reciba esos 4 valores y derive
   un estado enum:
   - `pairedSyncHost == nil` → inactivo (icono `bolt.horizontal.circle`, gris,
     etiqueta "Sync inactivo"); ocultarlo o mostrarlo tenue.
   - `syncPendingChanges > 0` → pendiente (icono `clock.badge`, ámbar, texto
     "N pendientes").
   - error (si `syncStatusMessage` contiene "fallido"/"Error"/"failed") →
     `exclamationmark.triangle`, rojo.
   - resto → sincronizado (`checkmark.circle`, verde).
2. Añadir un `ToolbarItem(placement: .navigationBarTrailing)` en
   `IPadWorkspaceShell.swift` (anclas de toolbar ya existentes hacia la
   línea 1585–1613) que muestre `SyncStatusBadge`. Debe recibir el
   `DashboardBridgeStore` ya inyectado.
3. Accesibilidad: el badge debe tener `accessibilityLabel` dinámico
   (p. ej. "Sincronización: 3 cambios pendientes") y `accessibilityHint`.

**Verificación:** revisar que el enum cubre los 4 estados y que compila
sintácticamente (tipos de los `@Published`). No introducir dependencias nuevas.

### Tarea B — Ampliar accesibilidad donde falta (bajo riesgo)

**Objetivo:** cerrar huecos de VoiceOver en los controles del flujo principal,
sin rehacer lo que ya existe.

1. Auditar (grep) qué botones de evaluación rápida y celdas del grid **no**
   tienen `accessibilityLabel`. Punto de partida: la accesibilidad ya presente
   en `NotebookModuleGridCells.swift` y `NotebookEditableTableCell.swift` sirve
   de patrón de estilo.
2. Añadir `accessibilityLabel`/`accessibilityValue` a las celdas del cuaderno
   que muestran nota+alumno+columna (label combinando los tres) y a los botones
   de acción rápida sin etiqueta textual (solo icono).
3. No cambiar layout ni lógica; solo modificadores de accesibilidad.

**Verificación:** el grep posterior debe mostrar cobertura en las celdas del
grid y en los botones icon-only del command bar.

### Tarea C — Dynamic Type con `@ScaledMetric` (riesgo medio) — OPCIONAL

**Objetivo:** que los espaciados internos de las celdas escalen con el tamaño
de fuente accesible, sin romper la rejilla estructural.

> No existe `NotebookGeometry.swift`. Localizar primero dónde están definidos
> los espaciados fijos de celda (buscar constantes de padding/spacing en
> `NotebookModuleGridCells.swift`, `NotebookEditableTableCell.swift`,
> `NotebookDataGrid.swift`).

1. Introducir `@ScaledMetric` para el padding **interno** de la celda (no para
   el ancho de columna, que debe seguir siendo estructural).
2. Limitar el cambio a 1–2 constantes para acotar el riesgo de layout.

**Si el riesgo de romper el grid es alto, dejar C solo documentada y no
implementarla.** Priorizar A y B.

## Fuera de alcance — trabajo futuro (NO en esta rama)

Estos ítems son ciertos pero son refactors grandes que **no se pueden
compilar/verificar en este entorno** y meterlos a medias sería peor:

- **Partir `KmpBridge.swift` (562 KB)** en servicios por dominio
  (`NotebookBridge`, `PlannerBridge`, `SyncBridge`, `AttendanceBridge`).
  Requiere plan de migración incremental con la app compilando en cada paso.
- **Fraccionar `IPadWorkspaceShell.swift` (119 KB)** en `@ViewBuilder` pequeños.
- Unificar el mecanismo de guardado individual/masivo (verificar antes el bug de
  colisión que motivó eliminar el reactivo en individual).

## Restricciones para quien ejecute

- Artefactos y mensajes en **español**.
- Cambios quirúrgicos; nada de reformatear archivos completos.
- No tocar `KmpBridge.swift` ni la god view en esta rama.
- Actualizar el CHANGELOG con las mejoras reales implementadas.
- Este entorno no compila iOS de forma fiable: asegurar corrección sintáctica y
  de tipos por lectura; no afirmar "compila" sin haberlo compilado.
