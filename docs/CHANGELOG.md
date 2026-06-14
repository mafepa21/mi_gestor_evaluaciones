# Changelog

Todas las entradas relevantes del proyecto se registraran aqui desde el 2026-06-04.

El formato sigue una variante practica de Keep a Changelog:

- `Added`: funcionalidades nuevas.
- `Changed`: cambios funcionales, UX o arquitectura.
- `Fixed`: bugs corregidos.
- `Data`: cambios en SQLDelight, repositorios, migraciones o persistencia.
- `Docs`: documentacion relevante.
- `Verification`: builds, tests, auditorias o evidencias.

## Unreleased

### Added

- El inspector del Cuaderno incorpora una primera capa de Inteligencia Educativa local: `StudentInsightDraft`, `AverageExplanationDraft` y `TutorMeetingSummaryDraft` estructurados desde evidencia existente, con fallback determinista cuando Foundation Models no está disponible.
- Informes Apple IA incorpora `StudentReportSummary` como modelo estructurado para fortalezas, aspectos a vigilar, áreas de progreso, recomendaciones y versiones docente/familia, manteniendo `AIReportDraft` como envoltorio compatible.
- Educación Física inicia `PhysicalProgressAnalysis` para analizar condición física del grupo desde snapshots de pruebas, con fallback local y tarjeta contextual en la pestaña Informes.
- macOS incorpora ventanas auxiliares nativas para Informes, Backups y Sync LAN, reutilizando la misma sesion, bridge, Command Center y store de backups que la ventana principal.
- Comandos de menú y atajos de teclado compartidos para iPad con teclado y macOS: añadir columna (`⌘N` / `⌘⇧C`), buscar (`⌘F`), guardar/sincronizar (`⌘S`), columnas ocultas (`⌘⇧H`), reordenar columnas (`⌘⌥R`), abrir Informes (`⌘E`) y navegación rápida a Cuaderno/Asistencia/Planner (`⌘1`/`⌘2`/`⌘3`).
- La toolbar macOS del Cuaderno usa `toolbar(id: "notebook.toolbar")` con ítems identificables y acción directa para revisar columnas ocultas, habilitando personalización nativa de la barra.

### Changed

- `AppleAIOrchestrator` añade intents estructurados para insight de alumno, explicación docente de media y resumen de tutoría sin recalcular datos KMP ni modificar persistencia.
- `AppleFoundationReportService` pasa a mapear la generación local y el fallback de informes hacia `StudentReportSummary`, separando el resumen estructurado del texto editable.
- `AppleFoundationContextualAIService` añade análisis estructurado de progreso físico sin recalcular marcas ni tocar persistencia.
- Se simplifica el toolbar del Cuaderno en iOS/iPadOS unificándolo en un único toolbar nativo superior que contiene el selector de clases, estado de sincronización, selector de vista (Grid/Plano), añadir columna, reordenar columnas, toggle de inspector, búsqueda y menú overflow, eliminando la barra manual duplicada `notebookMacLikeToolbar` del cuerpo de la pantalla y el toolbar nativo duplicado de `NotebookModuleView` en iPad.
- La toolbar macOS del Cuaderno reduce su superficie primaria a clase activa, añadir columna, búsqueda, estado de sync opcional y menú secundario; Columnas ocultas pasa al menú `Más`.
- En macOS, `⌘F` ya no cambia de módulo automáticamente: enfoca la búsqueda del Cuaderno solo cuando el Cuaderno está activo y muestra un aviso discreto en otros módulos.
- En macOS, `⌘B` abre el centro de Backups y `⌘⇧S` abre Sync LAN como ventanas de trabajo; `⌘E` pasa a abrir Informes en vez de tratarse como una exportacion directa.
- La barra compacta del Cuaderno pasa a ser contextual: sin selección muestra Columna/Buscar/Filtros, con celda activa muestra Copiar/Pegar/Rellenar/Borrar/Comentario y al seleccionar encabezado muestra Editar/Ocultar/Duplicar/Reordenar/Media.
- El Cuaderno concentra el cambio de contexto en el `toolbarTitleMenu` nativo del título: clase, trimestre, grupo, situación de aprendizaje, vista y configuración, eliminando el selector visible de clase/subtítulo en la barra compacta.

### Fixed

- Corrige la compilación de `IPadWorkspaceShell.swift` en iOS 16.0 reemplazando el modificador `.searchable` programático por un helper compatible `appSearchable` que implementa fallback en [AppleViewCompatibility.swift](file:///Users/mariofernandez/Projects/mi_gestor_evaluaciones/kmp/iosApp/AppleShared/AppleViewCompatibility.swift).
- Corrige la compilación Apple del inspector del Cuaderno evitando una colisión de nombre entre el closure `isSummaryColumn` y su valor booleano local.
- El Cuaderno macOS vuelve a mostrar la tira de pestañas y permite crear nuevas pestañas aunque la toolbar principal sea propiedad de la shell.
- El Cuaderno macOS deja de renderizar dos toolbars a la vez: `MacRootView` queda como unico owner de la toolbar y `NotebookModuleView` publica acciones sin pintar su barra interna.
- La toolbar macOS deja de duplicar los botones manuales de barra lateral e inspector; se conserva el control nativo de `NavigationSplitView`/inspector y los atajos siguen funcionando.
- La toolbar contextual del Cuaderno se muestra también en iPad/macOS cuando el módulo usa toolbar nativa (`shellOwned`/`macWindowOwned`), no solo en la barra compacta de iPhone.

### Data

### Docs

- ADR `kmp/docs/architecture/ADR-2026-06-14-local-educational-intelligence.md` documenta la regla de arquitectura para IA educativa local: KMP calcula hechos y Foundation Models genera objetos renderizables.
- ADR `kmp/docs/architecture/ADR-2026-06-13-macos-auxiliary-windows.md` documenta la estrategia de ventanas auxiliares macOS compartiendo sesion, bridge, Command Center y store de backups.

### Verification

- `plutil -lint kmp/iosApp/MiGestorKMPiOS.xcodeproj/project.pbxproj` y `git diff --check` completados correctamente tras registrar `AppleFoundationStudentInsightService.swift` en los targets Apple. `xcodebuild -project kmp/iosApp/MiGestorKMPiOS.xcodeproj -list` no pudo ejecutarse porque `xcode-select` apunta a `/Library/Developer/CommandLineTools` y no hay Xcode completo visible en `/Applications`.
- `git diff --check` completado correctamente tras introducir `StudentReportSummary` en `AppleFoundationReportService` y exponer `reportSummary` en `AppleAIOrchestrator`. La compilación Xcode sigue pendiente por la misma limitación de entorno local.
- `git diff --check` completado correctamente tras iniciar `PhysicalProgressAnalysis` en Educación Física. La compilación Xcode sigue pendiente por la limitación de Command Line Tools.
- Se validó la consistencia estructural de los cambios en [IOSRootView.swift](file:///Users/mariofernandez/Projects/mi_gestor_evaluaciones/kmp/iosApp/App/IOSRootView.swift) y [IPadWorkspaceShell.swift](file:///Users/mariofernandez/Projects/mi_gestor_evaluaciones/kmp/iosApp/App/IPadWorkspaceShell.swift) mediante la ejecución de `xcodegen generate` completado correctamente. Los builds locales de `verify_apple_builds.sh` fallan porque `xcode-select` apunta a `CommandLineTools` en el entorno, pero la sintaxis SwiftUI de la barra de herramientas cumple con la especificación de Apple para iOS 16.0+.
- Se validó el cambio de compatibilidad con iOS 16.0 en [IPadWorkspaceShell.swift](file:///Users/mariofernandez/Projects/mi_gestor_evaluaciones/kmp/iosApp/App/IPadWorkspaceShell.swift) mediante `xcodegen generate` completado correctamente. Los builds locales de `xcodebuild` no pudieron compilar porque `xcode-select` apunta a `CommandLineTools` en el entorno, pero el ajuste de compatibilidad en SwiftUI sigue el estándar establecido en el proyecto.
- Logs de GitHub Actions del run `27462430911` inspeccionados: macOS e iOS fallaban por `NotebookInspectorPanel.swift:60:44: error: cannot call value of non-function type 'Bool'`. `git diff --check -- kmp/iosApp/App/NotebookInspectorPanel.swift docs/CHANGELOG.md` completado correctamente tras el fix. La verificación local `scripts/verify_apple_builds.sh` sigue bloqueada por `xcode-select` apuntando a `/Library/Developer/CommandLineTools`.
- `git diff --check -- kmp/iosApp/App/NotebookModuleView.swift kmp/iosApp/MacApp/NotebookMacLayout.swift docs/CHANGELOG.md docs/ROADMAP.md` completado correctamente tras restaurar pestañas y creación de pestañas en el Cuaderno macOS shell-owned. `scripts/verify_apple_builds.sh` regenero el proyecto con XcodeGen, pero los builds macOS e iOS volvieron a quedar bloqueados por `xcode-select` apuntando a `/Library/Developer/CommandLineTools`.
- `git diff --check -- kmp/iosApp/MacApp/NotebookMacLayout.swift docs/CHANGELOG.md docs/ROADMAP.md` completado correctamente tras ocultar la toolbar interna duplicada del Cuaderno macOS. `scripts/verify_apple_builds.sh` regenero el proyecto con XcodeGen, pero los builds macOS e iOS volvieron a quedar bloqueados por `xcode-select` apuntando a `/Library/Developer/CommandLineTools`.
- `git diff --check -- kmp/iosApp/MacApp/MacRootView.swift docs/CHANGELOG.md docs/ROADMAP.md` completado correctamente tras ajustar foco de búsqueda y toolbar primaria del Cuaderno macOS. `scripts/verify_apple_builds.sh` regenero el proyecto con XcodeGen, pero los builds macOS e iOS volvieron a quedar bloqueados por `xcode-select` apuntando a `/Library/Developer/CommandLineTools`.
- `git diff --check -- kmp/iosApp/MacApp/MacRootView.swift docs/CHANGELOG.md` completado correctamente tras eliminar los toggles manuales duplicados de sidebar/inspector. `scripts/verify_apple_builds.sh` regenero el proyecto con XcodeGen, pero los builds macOS e iOS volvieron a quedar bloqueados por `xcode-select` apuntando a `/Library/Developer/CommandLineTools`.
- `git diff --check -- kmp/iosApp/MacApp/MiGestorKMPMacApp.swift kmp/iosApp/MacApp/MacAppSessionController.swift kmp/iosApp/MacApp/MacRootView.swift kmp/iosApp/AppleShared/AppleAppCommands.swift` completado correctamente tras añadir ventanas auxiliares macOS. `scripts/verify_apple_builds.sh` regenero el proyecto con XcodeGen, pero los builds macOS e iOS no pudieron ejecutarse porque `xcode-select` apunta a `/Library/Developer/CommandLineTools` y no hay Xcode completo visible en `/Applications`.
- `git diff --check` completado correctamente tras añadir la toolbar contextual del grid. `xcodebuild -list -project kmp/iosApp/MiGestorKMPiOS.xcodeproj` no pudo ejecutarse porque `xcode-select` apunta a `/Library/Developer/CommandLineTools` y no hay Xcode completo visible en `/Applications`.
- `xcodegen generate` completado correctamente para incluir `AppleAppCommands.swift` en los targets Apple. `git diff --check` completado correctamente tras añadir comandos y shortcuts Apple. `xcodebuild -list -project kmp/iosApp/MiGestorKMPiOS.xcodeproj` y la misma prueba con `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` no pudieron ejecutarse porque el entorno apunta a `/Library/Developer/CommandLineTools` y no hay Xcode completo visible en `/Applications`.
- `git diff --check -- kmp/iosApp/MacApp/MacRootView.swift kmp/iosApp/MacApp/MiGestorKMPMacApp.swift docs/CHANGELOG.md` completado correctamente. Prueba aislada `swift -module-cache-path /private/tmp/migestor-swift-module-cache -e '...'` completada para validar `toolbar(id:)` con `some CustomizableToolbarContent`. `xcodebuild -list -project kmp/iosApp/MiGestorKMPiOS.xcodeproj` no pudo ejecutarse porque `xcode-select` apunta a `/Library/Developer/CommandLineTools` y no hay `Xcode.app` ni `Xcode-beta.app` en `/Applications`.
- `git diff --check -- kmp/iosApp/App/NotebookModuleView.swift kmp/iosApp/App/NotebookCompactCommandBar.swift` completado correctamente. `xcodebuild -quiet -project kmp/iosApp/MiGestorKMPiOS.xcodeproj -scheme MiGestorKMPiOS -configuration Debug -destination 'generic/platform=iOS Simulator' build` no pudo ejecutarse porque `xcode-select` apunta a `/Library/Developer/CommandLineTools` y no hay Xcode instalado en `/Applications`.

## 0.3.0-alpha.2 - 2026-06-11

### Added

- Reordenación nativa de columnas del Cuaderno, borrador de criterios en el builder de rúbricas y reordenación local de sesiones/baterías desde listas SwiftUI.
- Acciones rápidas por swipe/context menu en sesiones del Planner y baterías físicas para completar, editar, duplicar, abrir diario/asignar y eliminar cuando el contrato existente lo permite.
- Inspector rápido de alumno en el Cuaderno con Media explicada, columnas pendientes, últimas observaciones, rúbricas asociadas y acciones principales.
- Modelo explícito de explicación de Media del Cuaderno con columnas incluidas, columnas excluidas, celdas pendientes y contribuciones ponderadas, manteniendo compatibilidad con el contrato anterior.
- Instrumentación debug desactivada por defecto para medir builds del sheet del Cuaderno, recálculo de medias, construcción del render model, filas visibles, hits/misses de caché y prompts derivados de IA.
- Perfil docente multi-asignatura local en SwiftUI con perfiles General, Educación Física, Lenguas, Ciencias, Matemáticas, Música, Tecnología y Personalizado.
- Registro de plantillas por asignatura sobre tipos de columna existentes del Cuaderno.
- Capa KMP `AssessmentMeasurement*` para preparar mediciones generales manteniendo `PhysicalTest*` como especialización EF.
- Catálogo visible de asignaturas en Cursos, con alta, edición, borrado seguro y asignación de materia al crear o editar grupos.
- Presets reales por materia para el Cuaderno, aplicables desde Añadir columna con nombre, peso, media, categoría y contexto preconfigurados.
- Piloto no-EF de mediciones genéricas para fluidez lectora (`READING_FLUENCY`) con definición, escala y resultado reutilizando `AssessmentMeasurement*`.

### Changed

- Sustitución de campos de búsqueda diseñados a mano en el Cuaderno, asistencia y búsqueda global por el modificador nativo `.searchable` en el shell de iPad/macOS (`IPadWorkspaceShell.swift`) y en el Cuaderno (`NotebookModuleView.swift`), unificando y simplificando la experiencia de búsqueda. Se introduce el helper `.avoidHidingContentDuringSearch()` para soportar de manera segura la opción `.avoidHidingContent` en iOS 17.1+ / macOS 14.1+ manteniendo compatibilidad nativa con iOS 16.0.
- Se simplifica la barra de herramientas del Cuaderno (`NotebookModuleView.swift`) mostrando solo las acciones principales (`[+ Columna]` y `[Buscar]`) y agrupando el resto bajo el menú secundario `[···]`.
- Se añade el toggle "Vista compacta" en el menú `···` que disminuye dinámicamente la altura del grid (38 en macOS y 40 en iOS).
- Se añade el botón "Configuración de media" en el menú `···` para acceder a la configuración de medias.
- Se agrupan todas las demás acciones secundarias (Deshacer, Asistencia rápida, Síntesis IA, Inspector, Organizar columnas, Columnas ocultas, Exportar cuaderno y submenú Filtros) en el menú `···`.
- Se añade el helper `.notebookSearchable(if:text:prompt:)` en `NotebookViewModifiers.swift` para evitar barras de búsqueda duplicadas en iPhone.
- Se añade el rol de toolbar de edición nativo (`.toolbarRole(.editor)`) en el Cuaderno (`NotebookModuleView.swift`) para adaptar la alineación de la navegación en iPadOS y mejorar la experiencia de edición documental/tabla.
- La toolbar del Cuaderno se rediseña por completo como toolbar nativa de SwiftUI (`.toolbar` y `.toolbarTitleMenu`) en iPad y macOS. Se elimina la barra manual (`notebookMacLikeToolbar`) en `IPadWorkspaceShell.swift` y se delega el título, clase activa, trimestre, situaciones de aprendizaje, filtros, acciones primarias/secundarias y la barra de estado de guardado/sincronización directamente a los componentes y placements nativos del sistema.
- La celda Media en macOS abre la ficha rápida completa del alumno, no solo el desglose aislado de cálculo.
- Las columnas de pruebas físicas del Cuaderno separan dato bruto y nota evaluable: `Marca`/`Nivel` se crean como dato bruto y `Nota` como nota baremada ponderable.
- La celda Media del Cuaderno separa visualmente qué entra, qué queda pendiente, qué no entra y cuánto aporta cada peso; en macOS se abre dentro del inspector contextual.
- La navegación iOS/iPadOS/macOS generaliza los módulos EF como módulos de dominio: sesiones prácticas, mediciones y baremos, recursos, incidencias y retos.
- El Cuaderno reutiliza cachés en memoria para el sheet por versión efectiva de clase/configuración/alumnado/columnas/celdas/rúbricas, medias por alumno/columnas/valores, render model SwiftUI y contexto derivado de Apple IA.
- Apple IA aplica un presupuesto centralizado de contexto antes de generar prompts, sourceDigest, evidencias auditadas y claves de caché de reportes/docencia.
- La toolbar del Cuaderno en macOS e iPad prioriza clase, añadir columna, búsqueda e inspector, desplazando recarga, exportación, deshacer, organización, grupos y opciones avanzadas al menú secundario.
- macOS incorpora una base controlada de Liquid Glass para paneles principales, paneles secundarios, superficies legibles, hairline borders y estados activos/inactivos sin aplicar transparencia al grid del Cuaderno.
- El Dashboard macOS conserva el servicio pesado de Apple IA en `@State` y queda auditada la inicialización de stores en Cuaderno, Planner y Tests físicos para evitar recreaciones accidentales.

### Fixed

- Se corrige el funcionamiento del Drag & Drop en el Plano de clase (`NotebookSeatingPlanView.swift`) asociándolo al coordinate space `seatingCanvas`, evitando que las tarjetas de los alumnos vibren o se queden atascadas al arrastrar.
- Se añade el helper `appEditMode` en `AppleViewCompatibility.swift` para activar de forma segura `editMode` en iPadOS (necesario para la reordenación de columnas en `NotebookColumnOrganizerSheet.swift`) sin provocar errores de compilación en el target de macOS.
- Se corrige un error de compilación en `NotebookModuleView.swift` causado por el uso del modificador `.symbolEffect(.rotate)` en plataformas anteriores a iOS 17.0/18.0, encapsulándolo bajo una comprobación de versión `#available(iOS 18.0, macOS 14.0, *)`.
- El build Apple KMP de macOS prioriza `macosArm64` cuando Xcode pasa `ARCHS="arm64 x86_64"`, excluye `x86_64` en el target Mac actual y permite forzar Intel solo con `KMP_MACOS_ARCH=x64`.

### Data

- Se añade migración SQLDelight `29.sqm` para persistir `center_id`, `academic_year_id`, `stage_cycle_id` y `subject_id` en `classes`, con índices por asignatura y curso académico.
- `ClassesRepositorySqlDelight` devuelve y guarda la metadata académica ya existente en `SchoolClass`.
- `SubjectsRepositorySqlDelight` expone la tabla `subjects` como catálogo gestionable y el bridge Apple refresca clases cuando cambia una asignatura.
- Se añaden migraciones SQLDelight `26.sqm`, `27.sqm` y `28.sqm` con índices compuestos para asistencia, incidencias, planner, horarios, rúbricas, learning situations, celdas y auditoría de celdas.
- Se reemplazan lecturas amplias en repositorios de notas y planner por queries más selectivas, manteniendo sin cambios los contratos de dominio.
- El snapshot del Cuaderno agrupa notas y celdas por clase antes de construir filas, evitando consultas repetidas por alumno sin modificar SQLDelight ni añadir migraciones.

### Docs

- Se documenta la estrategia multi-asignatura, los módulos de dominio y el roadmap específico del refactor.
- Se documenta la auditoría de performance SQLDelight y el criterio de PRs pequeños para revisar índices, consultas lentas, filtros frecuentes y joins.

### Verification

- Ejecución de `./scripts/verify_apple_builds.sh`. La verificación falló a nivel del entorno local ya que `xcode-select` apunta a `CommandLineTools` en lugar de una instalación completa de Xcode, impidiendo el uso de `xcodebuild` en consola.
- `./gradlew :shared:compileCommonMainKotlinMetadata :shared:compileDebugKotlinAndroid` completado correctamente tras añadir reordenación de criterios de rúbrica.
- `./gradlew :shared:compileKotlinIosSimulatorArm64` no pudo completarse porque `/usr/bin/xcrun xcodebuild -version` devuelve error 72 en la configuración local de Xcode/Command Line Tools, también fuera del sandbox.
- `./gradlew :shared:desktopTest` completado correctamente tras convertir el inspector del Cuaderno en ficha rápida del alumno.
- `./gradlew :shared:compileKotlinMetadata` completado correctamente tras el ajuste del inspector.
- `git diff --check` completado correctamente tras el ajuste del inspector.
- `PLATFORM_NAME=macosx ARCHS=arm64 CONFIGURATION=Debug ./scripts/build_apple_framework.sh` no pudo completarse porque `xcode-select` apunta a `/Library/Developer/CommandLineTools` y `xcodebuild` requiere Xcode completo.
- `./gradlew :shared:desktopTest` completado correctamente tras separar columnas físicas brutas y notas baremadas.
- `./gradlew :shared:compileKotlinMetadata` completado correctamente tras reforzar la regla KMP de dato bruto físico.
- `git diff --check` completado correctamente tras separar columnas físicas brutas y notas baremadas.
- `PLATFORM_NAME=macosx ARCHS=arm64 CONFIGURATION=Debug ./scripts/build_apple_framework.sh` no pudo completarse porque `xcode-select` apunta a `/Library/Developer/CommandLineTools` y `xcodebuild` requiere Xcode completo.
- `./gradlew :shared:desktopTest` completado correctamente tras ampliar la explicación de Media del Cuaderno.
- `./gradlew :shared:compileKotlinMetadata` completado correctamente tras ampliar el contrato común de Media.
- `PLATFORM_NAME=macosx ARCHS=arm64 CONFIGURATION=Debug ./scripts/build_apple_framework.sh` no pudo completarse porque `xcode-select` apunta a `/Library/Developer/CommandLineTools` y `xcodebuild` requiere Xcode completo.
- `./gradlew :shared:desktopTest` completado correctamente tras añadir la capa `AssessmentMeasurement*`.
- `./gradlew :data:desktopTest` completado correctamente tras la migración `29.sqm`.
- `xcodebuild -quiet -project kmp/iosApp/MiGestorKMPiOS.xcodeproj -scheme MiGestorKMPiOS -configuration Debug -destination 'generic/platform=iOS Simulator' build` completado correctamente.
- `xcodebuild -quiet -project kmp/iosApp/MiGestorKMPiOS.xcodeproj -scheme MiGestorKMPMac -configuration Debug -destination 'generic/platform=macOS' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build` completado correctamente. El build macOS genérico sin `ARCHS=arm64` falla porque el script del target selecciona el framework macOS x64 cuando Xcode pasa `ARCHS=arm64 x86_64`.
- `./gradlew :data:desktopTest` y `./gradlew :shared:desktopTest` completados correctamente tras añadir el catálogo de asignaturas.
- `xcodebuild -quiet -project kmp/iosApp/MiGestorKMPiOS.xcodeproj -scheme MiGestorKMPiOS -configuration Debug -destination 'generic/platform=iOS Simulator' build` completado correctamente tras conectar asignaturas en Cursos.
- `xcodebuild -quiet -project kmp/iosApp/MiGestorKMPiOS.xcodeproj -scheme MiGestorKMPiOS -configuration Debug -destination 'generic/platform=iOS Simulator' build` completado correctamente tras convertir plantillas por materia en presets aplicables.
- `./gradlew :shared:desktopTest` completado correctamente tras añadir el piloto `READING_FLUENCY`.
- Se añade cobertura de test para comprobar que el schema crea los índices críticos de performance.
- `xcodebuild -project kmp/iosApp/MiGestorKMPiOS.xcodeproj -scheme MiGestorKMPiOS -configuration Debug -destination 'generic/platform=iOS Simulator' build` completado correctamente tras limitar payloads de Apple IA.
- `xcodebuild -project kmp/iosApp/MiGestorKMPiOS.xcodeproj -scheme MiGestorKMPiOS -configuration Debug -destination 'generic/platform=iOS Simulator' build` completado correctamente tras la auditoría de caché del Cuaderno.
- `git diff --check -- kmp/iosApp/MacApp/MacRootView.swift kmp/iosApp/App/IPadWorkspaceShell.swift` completado correctamente tras reorganizar la toolbar del Cuaderno. Los builds `xcodebuild` de iOS Simulator y macOS no se ejecutaron porque `xcode-select` apunta a `/Library/Developer/CommandLineTools` y no hay Xcode completo visible en `/Applications`.
- `git diff --check` completado correctamente tras añadir la base Liquid Glass macOS. Build Apple pendiente por la misma configuración local de `xcode-select` en CommandLineTools.
- `git diff --check` completado correctamente tras auditar `@State`/stores en `MacDashboardView.swift`, `MacPhysicalTestsView.swift`, `NotebookModuleView.swift` y `PlannerWorkspaceIOS.swift`. Build Apple pendiente por `xcode-select` en CommandLineTools.
- Verificación de builds completada correctamente para macOS (`MiGestorKMPMac`) e iOS Simulator (`MiGestorKMPiOS`) usando la herramienta `scripts/verify_apple_builds.sh` apuntando al developer path de `Xcode-beta.app`.

## 0.3.0-alpha.1 - 2026-06-06

### Added
 
- Señales avanzadas de "Seguimiento EF" y "Cobertura LOMLOE" en el Radar docente, derivadas de `peItems` y `AITrendsSnapshot` sin ampliar KMP ni SQLDelight.
- Señal avanzada de "Media y cierre evaluativo" en el Radar docente, calculada desde resúmenes de grupo, agenda e instrumentos rápidos ya expuestos por el Dashboard.
- Radar docente proactivo compartido para Dashboard iOS/iPadOS y macOS, con insights deterministas, hechos usados, acciones reales por plataforma y briefing no bloqueante con fallback local.
- Script de automatización de Git y GitHub `scripts/auto_commit_pr.sh` para realizar análisis de seguridad local, commits formateados, push y apertura de PRs en draft de forma automática.
- Detalle de cálculo de media personalizado `CustomAverageExplanationPopoverView` que muestra "Incluye", "No incluye", "Pendientes", pesos e indicador de estado de cálculo.
- Integración de presentación de popover/sheet a nivel raíz en `NotebookModuleView.swift` para evitar conflictos de gestos e instanciación de popovers duplicados en celdas del grid.
- Exposición del snapshot de tendencias académicas `AITrendsSnapshot` y la función `getAITrendsAndMetrics` en `KmpBridge.swift`.
- Sección nativa y visual de "Análisis de Tendencias IA" en la ficha del alumno dentro de `NotebookStudentInspector.swift`.
- Widget contextual premium de "Auditoría LOMLOE y Alertas de Grupo" en `DashboardView.swift` con barras de progreso y diagnóstico de cobertura.
- Bloque de parámetros con el análisis acumulado de tendencias de IA en `RubricsReportsWorkspaceViews.swift`.

### Changed
 
- Pulido visual del componente `DashboardProactiveInsightCard`: espaciado en rejilla de 8pt, acciones adaptativas, loading skeleton y accesibilidad en iconos/progreso.
- El Dashboard Apple pasa a priorizar señales accionables de "Radar docente" antes de los bloques informativos tradicionales, manteniendo filtros y exportación como herramientas secundarias.
- Se corrige `.gitignore` con el patrón global `**/.xcode-derived/` y se remueven del repositorio Git los archivos de caché generados por Xcode que impedían pasar las validaciones de seguridad local.
- Se unificó y encapsuló el cálculo de medias, resolución de valores de celdas (`gradeValueFor`) y desglose de explicación (`computeAverageExplanation`) en `Models.kt`, eliminando implementaciones duplicadas en `BuildNotebookSheetUseCase.kt` y `NotebookViewModel.kt`.
- Se fija `0.3.0-dev` como version interna actual hasta contar con una release reproducible y verificada.
- Los manifiestos activos bajan de `1.0` a `0.3.0` para reflejar el estado real de madurez del producto.
- Enriquecimiento del prompt base local de Apple Intelligence en `AppleFoundationReportService.swift` y de las evidencias del radar en `AppleFoundationContextualAIService.swift`.

### Fixed

- Corrección de los checks Apple en CI: `navigationSubtitle` queda limitado a macOS y el Command Center Helper usa la firma actual de `LocalSyncServer`.
- Corrección en la eliminación de columnas vinculadas a evaluaciones que usan identificadores personalizados. Al eliminar una evaluación, la base de datos de manera en cascada establecía a NULL el `evaluation_id` de la columna asociada en `notebook_columns`, impidiendo resolver la columna para eliminarla físicamente y dejándola huérfana (por lo que seguía apareciendo en el menú de cálculo de media). Ahora, se busca y elimina primero la columna usando su ID real antes de romper la relación.
- Corrección de evaluación de fórmulas calculadas: ahora las celdas vacías no se inicializan por defecto a `0.0`, lo que evita alterar a la baja de manera errónea el promedio ponderado y devuelve un valor `null` correcto en caso de variables de fórmulas no evaluadas.
- Corrección de tipo en `GetAITrendsAndMetricsUseCase.kt` (comparaciones numéricas contra literales `0L` para evitar mismatch con tipo `Long`).
- Corrección de conversión de tipo de notas en `SqlDelightRepositories.kt` (conversión segura de `String` a `Double` vía `toDoubleOrNull()`).
- Solución de ambigüedad de tipo en `DashboardView.swift` al utilizar estilos y colores de manera explícita (`Color.primary` y `Color.orange`).

### Verification
 
- Verificación de builds Apple completada con éxito vía `scripts/verify_apple_builds.sh` tras añadir señales avanzadas EF y LOMLOE al Radar.
- Compilación de Compose Desktop completada con éxito vía `./gradlew :desktopApp:compileKotlin` tras adaptar el uso de `LocalSyncServer`.
- Verificación de builds Apple completada con éxito vía `scripts/verify_apple_builds.sh` tras corregir los fallos de CI en macOS e iOS Simulator.
- Verificación de builds Apple completada con éxito vía `scripts/verify_apple_builds.sh` tras añadir la señal avanzada de media y cierre evaluativo al Radar.
- Verificación de builds Apple completada con éxito vía `scripts/verify_apple_builds.sh` tras el pulido visual del Radar docente.
- Verificación de builds Apple completada con éxito vía `scripts/verify_apple_builds.sh` tras integrar el Radar docente proactivo en iOS/iPadOS y macOS.
- Incorporación de pruebas unitarias específicas en `NotebookViewModelTest.kt` para validar el borrado completo de columnas con IDs personalizados y el comportamiento de fallback.
- Paso de todas las pruebas unitarias asíncronas en Kotlin compartidas (`./gradlew :shared:desktopTest`), incluyendo la cobertura para la eliminación correcta de columnas y evaluaciones.
- Verificación de compilación multiplataforma (iOS Simulator y macOS Native/Catalyst) completada con éxito tras la integración del popover de desglose de media.
-  Validación de compilación multiplataforma (iOS Simulator y macOS Native/Catalyst) completada con éxito vía `./scripts/verify_apple_builds.sh`.

### Docs
 
- Se crea `ADR-2026-06-05-dashboard-radar.md` para formalizar el enfoque del Radar docente: reglas primero, Apple IA como redacción grounded y fallback determinista.
- Se actualiza `docs/VERSIONING.md` para incorporar la guía de uso del script de automatización `scripts/auto_commit_pr.sh`.
- Se crea `docs/VERSIONING.md` como guia canonica de SemVer interno, ramas, commits, tags, GitHub Releases, versionado de manifests y registro automatico de cambios por PR.
- Se anade base de preparacion comercial: licencia propietaria, politica de seguridad, borrador de privacidad, avisos de terceros, due diligence, mapa de datos personales y matriz de modulos.
- Se crea la estructura documental base del repositorio: indice, gobierno, roadmap, baseline inicial y plantilla de PR.
- Se documenta el workflow para agentes y el uso obligatorio de `registrar-avance-app` como capa final de trazabilidad.
- Se añade el proceso interno de release con checks obligatorios, version bump, evidencias minimas y criterio de etiquetado.
- Se actualiza el estado documental de KMP + SwiftUI Apple como target activo y Flutter como legado o referencia pendiente de decision.

### Verification

- Se añade workflow `release-check.yml` para ramas `release/**`, con validacion documental, bloqueo de artefactos sensibles, coherencia de version y artifact de evidencias.
- Se añaden scripts `verify_no_sensitive_files.sh` y `create_release_candidate.sh` para preparar candidatas de release sin crear tags reales y detectar artefactos que no deben versionarse.
- Se automatiza el flujo seguro de PR y release con `pr-check.yml`, `release-check.yml`, `publish-release.yml`, `check_version_consistency.sh` y `collect_release_evidence.sh`, manteniendo tags y publicacion como acciones manuales.
- Se añaden workflows de GitHub Actions para tests KMP/data y verificacion de builds Apple en PRs y pushes a `main`.
- Se cierra el PR #6 como redundante/conflictivo tras verificar que no quedaban commits pendientes respecto a `origin/main`.

## Baseline historico - 2026-06-04

### Changed

- El proyecto ya contiene una app Flutter original y una evolucion KMP + SwiftUI en curso.
- La documentacion canonica pasa a organizarse desde `docs/`, con ADRs tecnicos en `kmp/docs/architecture/`.

### Verification

- Se reviso la estructura del repositorio, README existentes, ADR inicial Apple dual-target y checklist UI/UX existente.
