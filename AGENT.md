# MiGestor KMP - Documentación de Agente

## Contexto del Proyecto
MiGestor es una aplicación educativa multiplataforma (KMP) centrada en la gestión de cuadernos de notas, criterios y rúbricas. Utiliza Jetpack Compose para la UI y SQLDelight para la persistencia.

## Sistema de Diseño (Organic Precision)
- **Geometría**: Basada en rejilla de 8pt.
- **Componentes**: `OrganicGlassCard.kt`, `MeshBackground.kt`.
- **Interacciones**: Glassmorphism, micro-animaciones y feedback visual inmediato.
- **Filosofía Jobs (Skill)**: Se ha integrado el skill `jobs-design-philosophy` para auditoría y refactorización de UI/UX basada en simplicidad radical, rejilla de 8pt y reducción de carga cognitiva.

## Funcionalidades Críticas

### Cuaderno de Notas (Notebook)
- **Grid de Datos**: Implementado con celdas editables y soporte para diferentes tipos de entrada (Texto, Decimal, Selector, Rúbrica).
- **Navegación**: Uso de teclado para desplazarse (`Enter`, `Tab`) y edición rápida.
- **Vínculo de Rúbricas**: Las columnas de tipo `RUBRIC` abren un diálogo de evaluación específico.

### Evaluaciones y Rúbricas
- **Constructor de Rúbricas**: Permite definir criterios y niveles de logro con pesos y puntos automáticos.
- **Lógica de Cálculo (Nueva)**:
    - **Puntos por Nivel**: Se asignan automáticamente según el orden (1, 2, 3...). Las entradas manuales de puntos en la DB se ignoran visualmente.
    - **Pesos de Criterios**: Se distribuyen de forma equitativa (1/N) de manera automática.
    - **Escala 10**: La nota final se calcula promediando los porcentajes de cada criterio y escalando el resultado a un rango de 0.0 a 10.0.
- **Sincronización de UI**: Los componentes `RubricsScreen`, `RubricEvaluationDialog` y `RubricEvaluationScreen` reflejan esta lógica automática de puntos y pesos, ignorando valores obsoletos de la base de datos.

### Gestión de Alumnos y Estados
- **Alumnos Lesionados**: Se ha añadido el flag `isInjured` (boolean) en el modelo de `Student` y en la base de datos (`is_injured` INTEGER).
- **Visualización**: Los alumnos lesionados se resaltan en rojo en las listas de evaluación y se agrupan en un panel lateral en la vista masiva.

### Evaluación Masiva (Bulk Evaluation)
- **Vista de Matriz**: Permite evaluar a todo un grupo simultáneamente para una rúbrica específica.
- **Acceso**: Icono de "Bulk Evaluation" en las cabeceras de columnas tipo Rúbrica del cuaderno.
- **Herramientas de Productividad**:
    - **Copiar/Pegar**: Permite duplicar la evaluación detallada de un alumno a otro.
    - **Guardado Manual**: Botón "Guardar Todo" y "Guardar Evaluación" (en diálogo individual) para garantizar la persistencia masiva y puntual, complementando el auto-guardado.
- **Fiabilidad de Persistencia**: 
    - Se ha implementado una restricción `UNIQUE(student_id, column_id)` en la tabla `grades` para asegurar actualizaciones consistentes.
    - **Sincronización Transversal**: Uso de `NotebookRefreshBus` (SharedFlow) para notificar cambios desde cualquier `ViewModel` de evaluación al `NotebookViewModel`, forzando la recarga del snapshot y manteniendo todas las vistas (Individual, Bulk, Cuaderno) sincronizadas en tiempo real.
    - **Gestión de Diálogos**: La evaluación individual utiliza **Guardado Manual** (en lugar de auto-save reactivo) para prevenir cierres inesperados por colisiones de hilos/recomposición. Mantiene flags para feedback visual (`isSaveSuccessful`) y cierre controlado (`shouldDismissDialog`).
    - **Columnas Dinámicas**: `NotebookRepositorySqlDelight` detecta IDs de columna con prefijo `eval_` para persistir notas en evaluaciones automáticas del cuaderno que no tienen una columna manual vinculada.

### Inyección de Dependencias y Repositorios
- **KmpContainer**: Centraliza la instanciación de repositorios y casos de uso en el módulo `:data`. Los repositorios (`NotebookRepositorySqlDelight`, `PlannerRepositorySqlDelight`, etc.) consumen directamente la `AppDatabase`.
- **Casos de Uso**: Desacoplan la lógica de persistencia de la UI (ej: `BuildNotebookSheetUseCase`, `RecordGradeUseCase`).

## Guía de Desarrollo
- **Modificaciones de UI**: Mantener siempre la estética Glassmorphism y la rejilla de 8pt.
- **Lógica de Negocio**: No modificar la lógica de cálculo en `RubricEvaluationViewModel.kt` sin actualizar los tests correspondientes.
- **Tests**: Todas las lógicas de cálculo deben estar cubiertas en `RubricEvaluationViewModelTest.kt`.

## Cambios Recientes (Marzo 2026)
- **Corrección de Teclado Duplicado**: Se eliminó la doble instancia de `CellInputOverlay` en `NotebookScreen.kt`, centralizando el teclado a nivel global del grid para evitar solapamientos.
- **Navegación Fluida**: Se añadió lógica de cierre automático del overlay de entrada (`showInputPicker = null`) al navegar entre celdas con las teclas `Enter` y `Tab`.
- **Vínculo de Rúbricas**: Corregido `BuildNotebookSheetUseCase.kt` para propagar el `rubricId` y asignar correctamente el tipo `RUBRIC` a las columnas vinculadas.
### 4. Persistencia (SQLDelight)
- **Base de Datos**: `AppDatabase.sq` define el esquema.
- **Migraciones**: En desarrollo, se utiliza un patrón de migración manual en `DesktopDriver.kt` mediante bloques `try-catch` y `ALTER TABLE`/`CREATE UNIQUE INDEX` para añadir columnas (ej: `is_injured`) y restricciones sin perder datos locales del usuario.
- **Campos de Sincronización**: Casi todas las tablas incluyen `updated_at_epoch_ms`, `device_id` y `sync_version`.

### 5. Nuevas Funcionalidades Implementadas
- **Cuaderno con Evaluación por Rúbricas**: Soporta celdas vinculadas a rúbricas y apertura de diálogos de evaluación.
- **Evaluación Masiva (Bulk)**: Nueva pantalla que permite evaluar a toda la clase con una rúbrica simultáneamente, con soporte para Copiar/Pegar notas entre alumnos.
- **Estado del Alumno**: Soporte para marcar alumnos como "Lesionados", lo cual se refleja visualmente en el Cuaderno y la Evaluación Masiva.
- **Auto-guardado**: Implementado en la evaluación masiva con debounce y visualización de estado de guardado.
- **Sincronización entre ViewModels**: Implementado `NotebookRefreshBus` para desacoplar las vistas de evaluación del cuaderno principal.
- **Robustez en Rúbricas (Marzo 2026)**: Eliminado el auto-guardado reactivo en `RubricEvaluationViewModel` para solucionar el bug de cierre prematuro del diálogo. Implementada persistencia explícita en el cuaderno mediante `notebookRepository.upsertGrade` integrada en el flujo de guardado de la rúbrica.
- **Persistencia de Notas (Fix)**: Corregida la restricción `UNIQUE` en la tabla `grades`, que ahora utiliza `(student_id, column_id)` en lugar de `(student_id, evaluation_id)`. Se ha implementado una lógica de **fallback obligatorio** (`eval_${evaluationId}`) en los ViewModels para evitar `columnId` vacíos que rompan el índice único.
- **Simplificación de Repositorios**: Se centralizó la lógica de `upsert` en `NotebookRepository.upsertGrade`, eliminando llamadas duplicadas y desincronizadas a `GradesRepository.saveGrade` desde las capas superiores.
- **Sincronización Reactiva**: Implementado `RubricEvaluationBus` y `NotebookRefreshBus` (SharedFlow) para notificar cambios de nota en tiempo real entre el Cuaderno, Evaluación Individual y Evaluación Masiva, asegurando coherencia visual inmediata.
- **Auto-guardado**: Implementado en la evaluación masiva y cuaderno con debounce de 500ms y 30s respectivamente.
- **Paneles Colapsables (Marzo 2026)**: Implementados paneles laterales colapsables (Banco y Configuración) en `RubricsScreen.kt` usando `AnimatedVisibility`. 
    - **UX**: Botones toggle con estética `OrganicGlassCard` y atajos de teclado (`Ctrl+B` para Banco, `Ctrl+L` para Configuración).
    - **Estado**: Elevado al `RubricsViewModel` para persistencia durante la navegación.
- **Sidebar Colapsable (Marzo 2026)**: Refactorización de la navegación principal para optimizar el espacio en pantalla.
    - **Comportamiento Rail**: El sidebar se contrae a 56dp (iconos centrados) y se expande a 240dp (iconos + etiquetas).
    - **Estado Global**: Gestionado por `AppLayoutViewModel` con persistencia reactiva.
    - **Atajo de Teclado**: Soporte para `Cmd + \` (o `Ctrl + \`) para alternar el estado desde cualquier parte de la aplicación.
    - **Animaciones**: Transiciones fluidas de ancho con `animateDpAsState` y visibilidad de etiquetas con `AnimatedVisibility`.

### 6. Módulo Planificador (Marzo 2026)
- **Consolidación de Nomenclatura**: Se ha unificado el repositorio bajo el nombre `PlannerRepository` (eliminando `PlanningRepository`) y el modelo de sesión bajo `PlanningSession`.
- **Vista Semanal**: Rejilla de Lunes a Viernes con 6 periodos lectivos. 
- **Integración con Horario**: Fusiona automáticamente los huecos del horario (`schedule_slot`) con las sesiones reales (`planner_session`).
- **Navegación ISO**: Soporte para cambio de semana con cálculos ISO-8601 (lunes como primer día).
- **Auto-guardado con Debounce**: Las ediciones en los detalles de la sesión se guardan automáticamente tras 500ms de inactividad del usuario en el `PlannerViewModel`.
- **UI Glassmorphism**: Uso de `OrganicGlassCard` para las celdas de la rejilla y el panel lateral de detalles, manteniendo la coherencia estética "Organic Precision".
- **Lógica de Colisiones**: El repositorio maneja conflictos de sesiones (misma fecha/periodo) mediante `INSERT OR REPLACE` para asegurar que solo exista una sesión por hueco.

### 7. Modernización del Cuaderno (Marzo 2026)
- **Arquitectura de UI**: Refactorización del `NotebookScreen` en componentes modulares (`ContextBar`, `ActionBar`, `GroupSummaryBar`) para reducir la carga cognitiva.
- **Geometría Unificada**: Implementación de `NotebookGeometry` para centralizar espaciados (8pt grid), radios de bordes y márgenes de pantalla.
- **Heatmap Semántico**: Las celdas del grid aplican colores de cristal semánticos (`GreenGlass`, `BlueGlass`, `RedGlass`) según la calificación, facilitando la identificación visual de patrones de rendimiento.
- **Persistencia Reactiva**: 
    - Integración de `SaveState` (Guardado, Pendiente, Guardando) vinculado al `NotebookViewModel`.
    - Auto-guardado inteligente cada 30 segundos si hay cambios pendientes.
    - Atajos de teclado: `Ctrl+S` (Guardar manual), `Ctrl+Z` (Deshacer local hasta 30 pasos).
- **Densidad Dinámica**: Soporte para modos `COMPACT` y `COMFORTABLE` con ajuste automático de fuentes y paddings en el grid.

### 8. Sincronización iOS (Marzo 2026)
- **Equidad de Dashboards**: El dashboard de iOS se ha rediseñado completamente para igualar la funcionalidad y estética de la versión desktop.
- **UI SwiftUI**: Implementación de `OrganicGlassCard` y componentes bento en SwiftUI, manteniendo la coherencia con el sistema "Organic Precision".
- **Bridge de Datos**: El `KmpBridge.swift` ahora expone métricas avanzadas, próximas clases (Calendar), tareas pendientes (Incidents) y distribución de alumnos calculada desde el core KMP.
- **Geometría Adaptativa**: Uso de `LazyVGrid` y `ScrollView` para asegurar que el dashboard sea funcional tanto en iPhone como en iPad.
- **Bridging de Colecciones**: El uso de `Map<Pair<Long, String>, V>` desde Kotlin requiere en Swift que las claves de tipo `KotlinPair` usen explícitamente `KotlinLong` y `NSString` para asegurar que el `Dictionary` de Swift reconozca la clave y no falle con errores de subscript (`RangeExpression`).
- **Arquitectura Modular iOS (Marzo 2026)**: El módulo del Cuaderno se ha extraído de `ContentView.swift` hacia archivos especializados (`NotebookModuleView.swift`, `NotebookDataGrid.swift`, `NotebookTopBar.swift`) para mejorar la mantenibilidad y resolver problemas de layout.
- **Rediseño Jobs iOS (Marzo 2026)**: 
    - **Geometría y Grid**: Implementación de `NotebookGeometry.swift` (rejilla estricta 8pt) y `NotebookColumnWidths.swift` (`ObservableObject`) para asegurar redimensionado de columnas en tiempo real en todas las celdas (solucionando el bug de `Equatable` en `StudentRow`).
    - **Interacción Nativa**: Implementado **Drag & Drop nativo** de SwiftUI (`.onDrag`/`.onDrop`) en las cabeceras del grid con feedback háptico y animaciones fluidas.
    - **Categorías Visuales**: Soporte para agrupación de columnas por categorías mediante el patrón `"Categoría | Título"` en la cabecera.
    - **Colorización Semántica**: Las celdas adoptan un `tintColor` dinámico derivado del `colorHex` de la columna, aplicado como un fondo sutil (6% opacidad) para mejorar la segmentación visual sin perder legibilidad.
    - **Evaluación Masiva**: Refinada la vista `RubricBulkEvaluationSheet` con celdas de 56pt, popovers a 16pt y priorización de valoración textual.

### 9. Sincronización LAN v2 — Contrato Completo (Marzo 2026)

#### Contrato (`SyncChange` v2)
- **`op: String = "upsert"`** — soporta operaciones explícitas de borrado (`delete`). Retrocompatible: clientes v1 reciben siempre `upsert`.
- **`schemaVersion: Int = 1`** — permite versionar payloads sin romper emparejamientos existentes.
- **`SyncAck`** — ahora incluye métricas `ignored` y `failed` para observabilidad en Desktop y iOS.

#### Catálogo de Entidades Sincronizables (25 total)
| Entidad | Colección | Cobertura |
|---|---|---|
| `class` | global | ✅ Desktop ↔ iOS |
| `class_roster` | por clase | ✅ Desktop ↔ iOS |
| `student` | global | ✅ Desktop ↔ iOS |
| `student_deleted` | global | ✅ op=delete |
| `evaluation` | por clase | ✅ Desktop ↔ iOS |
| `grade` | por clase | ✅ v2: columnId real |
| `notebook_tab` | por clase | ✅ Desktop ↔ iOS |
| `notebook_column` | por clase | ✅ Desktop ↔ iOS |
| `notebook_cell` | por clase | ✅ Desktop ↔ iOS |
| `attendance` | por clase | ✅ Desktop ↔ iOS |
| `incident` | por clase | ✅ Desktop ↔ iOS |
| `calendar_event` | global | ✅ Desktop ↔ iOS |
| `rubric_bundle` | global | ✅ Desktop → iOS |
| `rubric_assessment` | por eval | ✅ Desktop ↔ iOS |
| `teaching_unit` | global | ✅ Desktop → iOS |
| `planning_session` | global | ✅ Desktop → iOS |

#### Reglas de Conflicto
- **LWW (Last-Write-Wins)**: desempate por `updatedAtEpochMs`, secundario por `deviceId` (mayor gana).
- **`grade` fix**: `columnId` se propaga directamente (antes iOS construía `eval_$id`, Desktop usaba el ID real). Fallback v1: si `columnId` está vacío, se infiere `eval_$evaluationId`.

#### Persistencia iOS
- **Cola saliente**: `pendingOutboundChanges` se serializa en `UserDefaults["sync.pending.changes.v2"]` en cada `enqueue` y se borra tras push exitoso.
- **Device ID estable**: `localDeviceId` persiste en `UserDefaults["sync.device.id"]` — elimina la rotación aleatoria en cada arranque que generaba conflictos LWW espurios.
- **Control de Refrescos (Marzo 2026)**: 
    - Se ha implementado un `debounce(400)` en el `NotebookViewModel.kt` para evitar recargas del snapshot ante ráfagas de cambios locales.
    - `KmpBridge.swift` ahora realiza refrescos condicionales: solo recarga el cuaderno si el `pull` de sincronización trajo cambios reales, eliminando el parpadeo constante cada 6 segundos.
    - El `auto-sync` post-edición se ha ajustado a 2.0s para no interrumpir el flujo de escritura del usuario.
    - **Optimización de Snapshots (Marzo 2026)**: 
        - `KmpBridge.enqueueNotebookSnapshot` realiza una **única persistencia a disco** (`UserDefaults`) al final del volcado completo, reduciendo drásticamente la latencia de I/O en iOS.
        - Se ha añadido el parámetro `shouldPersist` a `enqueueLocalChange` para permitir encolados masivos sin bloqueos.
    - **Propagación de Borrados (Tombstones)**:
        - `deleteTab` y `deleteColumn` en iOS encolan explícitamente cambios con `op: "delete"` antes de aplicar el borrado local, asegurando que el Desktop reciba la instrucción de eliminación en el siguiente ciclo de `push`.
    - **Estabilización iOS (Marzo 2026)**: 
        - `KmpBridge.swift` aplica un `debounce(150ms)` a las actualizaciones de estado para no saturar el hilo UI de SwiftUI durante la escritura rápida.
        - `StudentRow` implementa `Equatable` para evitar re-calculados de Layout innecesarios en toda la fila si no hay cambios estructurales.
        - Eliminado `GeometryReader` del grid principal para evitar conflictos de Layout Guide con el teclado de iOS.
        - **Estabilización de Refrescos (Marzo 2026)**:
            - `NotebookViewModel.selectClass` nunca emite `Loading` si ya hay datos para la misma clase; los refrescos forzados (sync, addColumn) son siempre silenciosos.
            - `startObservingData` preserva los drafts del usuario (map merge: drafts de usuario prevalecen) cuando `_isDirty = true`, evitando que el eco de escrituras en DB sobreescriba valores en edición.
            - `KmpBridge.setupObservers` ignora las transiciones a `NotebookUiStateLoading` si ya hay datos previos, impidiendo que la jerarquía SwiftUI se destruya.
            - `performPullSync` filtra `refreshCurrentNotebook()`: solo lo llama si algún cambio sincronizado afecta a entidades del cuaderno (`grade`, `notebook_tab`, `notebook_column`, `notebook_cell`, `rubric_assessment`).
            - `NotebookModuleView` observa cambios en `bridge.notebookState` mediante `.onChange` para actualizar su cache `lastKnownData` de forma segura, eliminando la mutación de estado prohibida dentro de `@ViewBuilder`. Muestra el grid previo con un `ProgressView` lineal sutil durante recargas en segundo plano.
            - `NumericCell` y `TextCell` tienen un flag `isSaving` para ignorar actualizaciones de `persistedValue` mientras procesan su propio eco de escritura (ciclo: usuario escribe → saveGrade → DB emite cambio → observer recarga → persistedValue cambia → no se sobreescribe localValue).
            - **Resolución de Tab IDs por Título (Sync)**: En `KmpBridge.swift`, si una columna recibida de Desktop referencia un `tabId` que no existe en iOS, el bridge busca una pestaña local con el mismo nombre y la re-asigna automáticamente para asegurar la visibilidad en el grid.
            - **Gestión de Grupos en iOS (Marzo 2026)**: 
                - Se corrigió la exportación del framework `MiGestorKit` para exponer correctamente las entidades `NotebookWorkGroup` y `NotebookWorkGroupMember`.
                - `NotebookDataGrid.swift` ahora organiza dinámicamente las filas en secciones basadas en la pertenencia a grupos para la pestaña activa.
                - **Rediseño Nativo**: `NotebookGroupManagerSheet` reimplementado con una arquitectura de **2 pasos** (Lista -> Detalle) usando `NavigationStack`, `swipeActions` para borrado rápido y guardado automático al cerrar el detalle (`.onDisappear`).
                - **Sincronización de Grupos**: Las operaciones de grupos se persisten localmente y se encolan automáticamente para sincronización bidireccional con el Desktop.

#### Archivos Afectados
- `kmp/shared/.../sync/SyncCoordinator.kt` — contratos `SyncChange`, `SyncAck`
- `kmp/desktopApp/.../sync/SqlDelightSyncAdapter.kt` — collect & apply 25 entidades + delete handler
- `kmp/desktopApp/.../sync/LocalSyncServer.kt` — encode/decode `op`, `schemaVersion`, métricas ACK

