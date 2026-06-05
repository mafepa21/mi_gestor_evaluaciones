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
 
- Detalle de cálculo de media personalizado `CustomAverageExplanationPopoverView` que muestra "Incluye", "No incluye", "Pendientes", pesos e indicador de estado de cálculo.
- Integración de presentación de popover/sheet a nivel raíz en `NotebookModuleView.swift` para evitar conflictos de gestos e instanciación de popovers duplicados en celdas del grid.
- Exposición del snapshot de tendencias académicas `AITrendsSnapshot` y la función `getAITrendsAndMetrics` en `KmpBridge.swift`.
- Sección nativa y visual de "Análisis de Tendencias IA" en la ficha del alumno dentro de `NotebookStudentInspector.swift`.
- Widget contextual premium de "Auditoría LOMLOE y Alertas de Grupo" en `DashboardView.swift` con barras de progreso y diagnóstico de cobertura.
- Bloque de parámetros con el análisis acumulado de tendencias de IA en `RubricsReportsWorkspaceViews.swift`.

### Changed

- Se unificó y encapsuló el cálculo de medias, resolución de valores de celdas (`gradeValueFor`) y desglose de explicación (`computeAverageExplanation`) en `Models.kt`, eliminando implementaciones duplicadas en `BuildNotebookSheetUseCase.kt` y `NotebookViewModel.kt`.
- Se fija `0.3.0-dev` como version interna actual hasta contar con una release reproducible y verificada.
- Los manifiestos activos bajan de `1.0` a `0.3.0` para reflejar el estado real de madurez del producto.
- Enriquecimiento del prompt base local de Apple Intelligence en `AppleFoundationReportService.swift` y de las evidencias del radar en `AppleFoundationContextualAIService.swift`.

### Fixed

- Corrección en la eliminación de columnas vinculadas a evaluaciones que usan identificadores personalizados. Al eliminar una evaluación, la base de datos de manera en cascada establecía a NULL el `evaluation_id` de la columna asociada en `notebook_columns`, impidiendo resolver la columna para eliminarla físicamente y dejándola huérfana (por lo que seguía apareciendo en el menú de cálculo de media). Ahora, se busca y elimina primero la columna usando su ID real antes de romper la relación.
- Corrección de evaluación de fórmulas calculadas: ahora las celdas vacías no se inicializan por defecto a `0.0`, lo que evita alterar a la baja de manera errónea el promedio ponderado y devuelve un valor `null` correcto en caso de variables de fórmulas no evaluadas.
- Corrección de tipo en `GetAITrendsAndMetricsUseCase.kt` (comparaciones numéricas contra literales `0L` para evitar mismatch con tipo `Long`).
- Corrección de conversión de tipo de notas en `SqlDelightRepositories.kt` (conversión segura de `String` a `Double` vía `toDoubleOrNull()`).
- Solución de ambigüedad de tipo en `DashboardView.swift` al utilizar estilos y colores de manera explícita (`Color.primary` y `Color.orange`).

### Verification
 
- Incorporación de pruebas unitarias específicas en `NotebookViewModelTest.kt` para validar el borrado completo de columnas con IDs personalizados y el comportamiento de fallback.
- Paso de todas las pruebas unitarias asíncronas en Kotlin compartidas (`./gradlew :shared:desktopTest`), incluyendo la cobertura para la eliminación correcta de columnas y evaluaciones.
- Verificación de compilación multiplataforma (iOS Simulator y macOS Native/Catalyst) completada con éxito tras la integración del popover de desglose de media.
-  Validación de compilación multiplataforma (iOS Simulator y macOS Native/Catalyst) completada con éxito vía `./scripts/verify_apple_builds.sh`.

### Docs

- Se crea `docs/VERSIONING.md` como guia canonica de SemVer interno, ramas, commits, tags, GitHub Releases, versionado de manifests y registro automatico de cambios por PR.
- Se anade base de preparacion comercial: licencia propietaria, politica de seguridad, borrador de privacidad, avisos de terceros, due diligence, mapa de datos personales y matriz de modulos.
- Se crea la estructura documental base del repositorio: indice, gobierno, roadmap, baseline inicial y plantilla de PR.
- Se documenta el workflow para agentes y el uso obligatorio de `registrar-avance-app` como capa final de trazabilidad.
- Se añade el proceso interno de release con checks obligatorios, version bump, evidencias minimas y criterio de etiquetado.
- Se actualiza el estado documental de KMP + SwiftUI Apple como target activo y Flutter como legado o referencia pendiente de decision.

### Verification

- Se añade workflow `release-check.yml` para ramas `codex/release-*` y `release/**`, con validacion documental y bloqueo de artefactos sensibles.
- Se añaden scripts `verify_no_sensitive_files.sh` y `create_release_candidate.sh` para preparar candidatas de release sin crear tags reales y detectar artefactos que no deben versionarse.
- Se añaden workflows de GitHub Actions para tests KMP/data y verificacion de builds Apple en PRs y pushes a `main`.
- Se cierra el PR #6 como redundante/conflictivo tras verificar que no quedaban commits pendientes respecto a `origin/main`.

## Baseline historico - 2026-06-04

### Changed

- El proyecto ya contiene una app Flutter original y una evolucion KMP + SwiftUI en curso.
- La documentacion canonica pasa a organizarse desde `docs/`, con ADRs tecnicos en `kmp/docs/architecture/`.

### Verification

- Se reviso la estructura del repositorio, README existentes, ADR inicial Apple dual-target y checklist UI/UX existente.
