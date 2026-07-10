# Integración masiva — 6 de julio de 2026

## Alcance
Consolidación de ramas funcionales en `main`.
Commit base anterior: `a86b5374`
Baseline posterior: `v0.3.0-traceability-baseline` (SHA: `9c067a14`)

Este documento detalla cada una de las 13 integraciones ejecutadas el 6 de julio de 2026. Sirve como índice técnico e histórico para identificar las zonas de impacto, los conflictos resueltos y los riesgos de regresión residual que requieren pruebas prioritarias.

## Índice de Integraciones

| Merge | Rama | Área | Cambio verificable | Validación | Riesgo pendiente / Conflicto |
|---|---|---|---|---|---|
| `8b138790` | `notebook/premium-cuaderno-mejoras` | Cuaderno, Fórmulas, Configuración Regional | Edición de celdas premium, render ligero y cálculo decimal en fórmulas. | Tests de KMP (`FormulaEvaluatorTest`, `IsoWeekHelperTest`). | **Conflictos**: En archivos del Planner (`PlannerWorkspaceIOS.swift`, `PlannerWorkspaceViewModel.swift`, `MacPlannerView.swift`, etc.). Riesgo de regresión en las vistas SwiftUI del Planificador. |
| `debeaa8a` | `feature/premium-audit-lomloe-and-fixes` | Dashboard, Fórmulas, Sync, Accesibilidad | Distinción de estados vacíos ("sin datos" vs "falló la carga") en Dashboard, empty states en rúbricas, glosario consistente. Corrección decimal y crash de sync. | Compilación iOS/macOS + pruebas manuales. | Tests unitarios de flujo completo de negocio insuficientes. |
| `27517f81` | `feature/attendance-macos-exception-panel` | Asistencia, Shortcuts, Animación | Panel por excepción en macOS, atajos de teclado, layout adaptativo macOS. Plan de animaciones técnico. | Compilación macOS + navegación por teclado. | **Conflicto**: En `DashboardView.swift`. Falta de pruebas de UI exhaustivas en dispositivos reales. |
| `97e3478b` | `feature/planner-premium-fases` | Planificador (Planner) | Cierre de fases de UX/accesibilidad, panel diario tipo cabina de vuelo, inspector detallado en macOS, resumen en PDF. | Compilación iOS/macOS. | **Conflicto**: En `PlannerWorkspaceIOS.swift` (se dividió el archivo). Validar comportamiento en dispositivos reales. |
| `ec219899` | `codex/planner-sequence-enrichment` | Planificador (Planner), Torneos | Gantt de secuencias continuas, miniatura semanal premium, módulo de torneos, panel de creación de workspaces. | Compilación iOS/macOS. | **Conflictos**: En `DashboardView.swift` e `IPadWorkspaceShell.swift`. |
| `8aaf7064` | `feature/synclan-security-and-data-integrity` | SyncLAN, SQLDelight | Seguridad en SyncLAN, adaptador local de SQLDelight, control de echo de red, roster resurrection y roster / tombstone tests. | Tests automatizados (`SqlDelightSyncAdapterRosterTest`, `SqlDelightSyncAdapterTombstoneTest`). | Integridad de datos en redes LAN inestables con múltiples dispositivos. |
| `9a729ec0` | `codex/synclan-courses-sync` | SyncLAN, Cursos, Sidebar | Sincronización local de cursos, UI de emparejamiento, atajos y visualizaciones de configuración de horarios. | `LocalSyncServerTest` en desktopApp. | **Conflictos**: En `DashboardView.swift`, `TeacherScheduleSettingsView.swift` y `docs/CHANGELOG.md`. |
| `61f6a728` | `codex/session-import-detail-polish` | Planificador (Planner), Situaciones de Aprendizaje | Importación de situaciones de aprendizaje y justificación documental, celdas dinámicas en el cuaderno. | Compilación + tests unitarios. | **Conflicto**: En `docs/CHANGELOG.md`. |
| `e072dd7f` | `codex/notebook-tab-isolation` | Cuaderno, Lógica KMP | Aislamiento de pestañas del cuaderno para evitar propagación de estado inválido, caché optimizada. | `BuildNotebookSheetUseCaseTest`, `NotebookViewModelTest`. | Regresión en vistas que compartan datos de pestañas. |
| `8e2d363d` | `feat/dashboard-docente-architecture` | Dashboard, Arquitectura | Nueva arquitectura del Dashboard, especificación de bloques prioritarios (Hoy, Alertas, KPIs, Accesos, Insights). | Inspección visual y estática de código. | Integración completa de todos los módulos en los bloques del Dashboard. |
| `124dffba` | `codex/rubrics-direct-bulk-evaluation` | Rúbricas, Cuaderno | Evaluación masiva directa en rúbricas desde la vista detallada de informes. | Compilación y visualización. | Sincronización de promedios de rúbricas modificadas masivamente. |
| `8b7652c8` | `codex/agent-skills-battery` | Tooling de Agentes, Gobernanza | Batería de skills de dominio en `.agents/skills/` (SyncLAN, Liquid Glass, IA, etc.) y actualización de `AGENTS.md`. | Carga exitosa en entorno de agente (Codex/Claude). | Mantenimiento de la paridad en copias y symlinks de skills. |
| `4c04cf00` | `fix/consolidate-premium-components-and-kmp-build` | KMP Build, UI Components | Consolidación de componentes premium (tarjetas, botones) y resolución de build KMP compartido roto. | Gradle build exitoso en la capa compartida y compilación iOS/macOS. | Consistencia de diseño de componentes antiguos que no usen los nuevos estilos compartidos. |

## Zonas Críticas de Conflicto (Regresión Prioritaria)

1. **Dashboard (`DashboardView.swift`)**:
   - Afectado por 4 fusiones distintas (`27517f81`, `ec219899`, `9a729ec0`, `debeaa8a`).
   - Se modificaron de forma paralela la arquitectura de los bloques, el panel de asistencia por excepción y la visualización de la auditoría LOMLOE.
   - *Plan de acción:* Requiere pruebas completas de interacción en iPad y iPhone.
   
2. **Planner (`PlannerWorkspaceIOS.swift`, `PlannerDayView.swift`, `MacPlannerView.swift`)**:
   - Afectado por las fusiones `8b138790`, `97e3478b` y `ec219899`.
   - Se reestructuraron por completo las clases internas dividiendo el archivo masivo del planner, lo que provocó colisiones con los cambios de cuaderno y shortcuts de macOS.
   - *Plan de acción:* Ejecutar verificación de navegación semanal, creación de sesiones y generación de PDF.

3. **Horario Docente (`TeacherScheduleSettingsView.swift`)**:
   - Conflictos durante la fusión `9a729ec0` de sincronización de cursos.
   - *Plan de acción:* Validar la consistencia horaria en iOS y macOS.
