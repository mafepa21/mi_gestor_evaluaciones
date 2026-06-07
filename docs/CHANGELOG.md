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

- Instrumentación debug desactivada por defecto para medir builds del sheet del Cuaderno, recálculo de medias, construcción del render model, filas visibles, hits/misses de caché y prompts derivados de IA.
- Perfil docente multi-asignatura local en SwiftUI con perfiles General, Educación Física, Lenguas, Ciencias, Matemáticas, Música, Tecnología y Personalizado.
- Registro de plantillas por asignatura sobre tipos de columna existentes del Cuaderno.
- Capa KMP `AssessmentMeasurement*` para preparar mediciones generales manteniendo `PhysicalTest*` como especialización EF.

### Changed

- La navegación iOS/iPadOS/macOS generaliza los módulos EF como módulos de dominio: sesiones prácticas, mediciones y baremos, recursos, incidencias y retos.
- El Cuaderno reutiliza cachés en memoria para el sheet por versión efectiva de clase/configuración/alumnado/columnas/celdas/rúbricas, medias por alumno/columnas/valores, render model SwiftUI y contexto derivado de Apple IA.
- Apple IA aplica un presupuesto centralizado de contexto antes de generar prompts, sourceDigest, evidencias auditadas y claves de caché de reportes/docencia.

### Fixed

- El build Apple KMP de macOS prioriza `macosArm64` cuando Xcode pasa `ARCHS="arm64 x86_64"`, excluye `x86_64` en el target Mac actual y permite forzar Intel solo con `KMP_MACOS_ARCH=x64`.

### Data

- Se añade migración SQLDelight `29.sqm` para persistir `center_id`, `academic_year_id`, `stage_cycle_id` y `subject_id` en `classes`, con índices por asignatura y curso académico.
- `ClassesRepositorySqlDelight` devuelve y guarda la metadata académica ya existente en `SchoolClass`.
- Se añaden migraciones SQLDelight `26.sqm`, `27.sqm` y `28.sqm` con índices compuestos para asistencia, incidencias, planner, horarios, rúbricas, learning situations, celdas y auditoría de celdas.
- Se reemplazan lecturas amplias en repositorios de notas y planner por queries más selectivas, manteniendo sin cambios los contratos de dominio.
- El snapshot del Cuaderno agrupa notas y celdas por clase antes de construir filas, evitando consultas repetidas por alumno sin modificar SQLDelight ni añadir migraciones.

### Docs

- Se documenta la estrategia multi-asignatura, los módulos de dominio y el roadmap específico del refactor.
- Se documenta la auditoría de performance SQLDelight y el criterio de PRs pequeños para revisar índices, consultas lentas, filtros frecuentes y joins.

### Verification

- `./gradlew :shared:desktopTest` completado correctamente tras añadir la capa `AssessmentMeasurement*`.
- `./gradlew :data:desktopTest` completado correctamente tras la migración `29.sqm`.
- `xcodebuild -quiet -project kmp/iosApp/MiGestorKMPiOS.xcodeproj -scheme MiGestorKMPiOS -configuration Debug -destination 'generic/platform=iOS Simulator' build` completado correctamente.
- `xcodebuild -quiet -project kmp/iosApp/MiGestorKMPiOS.xcodeproj -scheme MiGestorKMPMac -configuration Debug -destination 'generic/platform=macOS' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build` completado correctamente. El build macOS genérico sin `ARCHS=arm64` falla porque el script del target selecciona el framework macOS x64 cuando Xcode pasa `ARCHS=arm64 x86_64`.
- Se añade cobertura de test para comprobar que el schema crea los índices críticos de performance.
- `xcodebuild -project kmp/iosApp/MiGestorKMPiOS.xcodeproj -scheme MiGestorKMPiOS -configuration Debug -destination 'generic/platform=iOS Simulator' build` completado correctamente tras limitar payloads de Apple IA.
- `xcodebuild -project kmp/iosApp/MiGestorKMPiOS.xcodeproj -scheme MiGestorKMPiOS -configuration Debug -destination 'generic/platform=iOS Simulator' build` completado correctamente tras la auditoría de caché del Cuaderno.

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
