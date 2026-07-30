# AGENTS.md - mi_gestor_evaluaciones

## Proyecto

App educativa KMP + SwiftUI para gestion docente: cuaderno, rubricas, asistencia, alumnado, planificacion, informes, sync, backups y modulos especificos de Educacion Fisica.

Prioridad:
- Uso diario fiable.
- SwiftUI iOS/macOS premium, limpio y nativo.
- Arquitectura KMP estable.
- Cambios pequenos, seguros y revisables.

## Modelos y consultas complejas

- Usar `gpt-5.6-terra` como modelo predeterminado para el trabajo principal y los subtareas ordinarios.
- Cuando una decisión o diagnóstico sea excepcionalmente complejo —por ejemplo, un problema de concurrencia, una regresión difícil de aislar, una migración delicada o un diseño arquitectónico con alternativas relevantes—, lanzar un subagente de consulta con `gpt-5.6-sol`.
- El subagente `gpt-5.6-sol` debe limitarse a analizar, proponer y señalar riesgos; el agente principal conserva la decisión final y aplica los cambios tras verificar su alcance.
- No delegar en `gpt-5.6-sol` tareas rutinarias ni usarlo solo para acelerar trabajo paralelo.

## Paso previo obligatorio

Antes de tocar UI, aplicar la skill `jobs-design-philosophy`. No repetir aqui su contenido: la skill es la fuente unica.

## Arquitectura

- `kmp/iosApp/App/`: SwiftUI nativo iOS/iPadOS/macOS Catalyst.
- `kmp/iosApp/MacApp/`: overrides y pantallas especificas macOS.
- `kmp/iosApp/AppleShared/`: componentes SwiftUI compartidos.
- `kmp/iosApp/App/KmpBridge.swift`: puente Swift <-> KMP.
- `kmp/shared/`: logica de negocio Kotlin.
- `kmp/data/`: repositorios + SQLDelight.
- `kmp/desktopApp/`: Compose Desktop, target distinto.

## Regla de oro

"Mejorar iOS/macOS" significa trabajar por defecto en:
- `kmp/iosApp/App/*.swift`
- `kmp/iosApp/AppleShared/*.swift`
- `kmp/iosApp/MacApp/*.swift` si es macOS especifico

Archivos protegidos (no tocar salvo orden explicita, explicando antes el motivo):
- `kmp/iosApp/App/KmpBridge.swift`
- `kmp/iosApp/App/EvaluationDesign.swift`
- `kmp/shared/domain/`
- `kmp/data/src/commonMain/sqldelight/`
- `kmp/desktopApp/`

## Skills

| Intencion | Skill |
|---|---|
| Registrar avance, PR y documentacion | `registrar-avance-app` |
| UI/UX SwiftUI | `swiftui-polish` |
| Bug SwiftUI | `swiftui-bugfix` |
| Funcion nativa Apple | `swiftui-native-feature` |
| Adaptacion macOS | `swiftui-macos-adapt` |
| Binding Swift-KMP | `kmp-bridge-fix` |
| Logica KMP | `kmp-logic-fix` |
| SQLDelight (bug de query/transaccion) | `sqldelight-fix` |
| SQLDelight (esquema, tablas, migraciones) | `sqldelight-migration` |
| Servicios Apple | `apple-service-patch` |
| Feature completa datos->UI (persistencia nueva) | `kmp-feature-vertical` |
| Modulo Planificacion (Semana/Dia/Secuencia/Resumen/PDF) | `planner-workspace` |
| Liquid Glass, materiales, chrome premium | `liquid-glass-design` |
| IA local Foundation Models (insights, EarlyWarning, informes) | `apple-intelligence-service` |
| Layout adaptativo iPad/iPhone/macOS, sheets, controles cortados | `adaptive-layout-apple` |
| SyncLAN, helper macOS, sync entre dispositivos | `synclan-debug` |
| Release, versiones, evidencias, tag | `release-prep` |

Usar una sola skill principal por tarea, salvo que el usuario pida una intervencion transversal.

### Skill de registro obligatoria

Usar `registrar-avance-app` al cerrar cualquier cambio que modifique producto, UI, KMP, SQLDelight, build, tests, documentacion relevante o decisiones tecnicas.

La skill no sustituye a la skill tecnica principal. Se usa como capa final de trazabilidad:
- primero aplicar la skill tecnica que corresponda,
- despues usar `registrar-avance-app` para actualizar changelog, roadmap, ADRs, evidencias, commits y nota de PR.

Referencia completa: `docs/AGENT_WORKFLOW.md`.

## Alcance

Acotar cada cambio al flujo o componente concreto que pide la tarea; no hacer refactors globales sin autorizacion explicita.

Archivos especialmente grandes o sensibles (acotar a una seccion o componente, no reescribir entero):
- `ContentView.swift`
- `IPadWorkspaceShell.swift`
- `NotebookModuleView.swift`

## Rutas frecuentes

| Area | Ruta |
|---|---|
| Vista principal iOS | `kmp/iosApp/App/ContentView.swift` |
| Shell iPad/Mac | `kmp/iosApp/App/IPadWorkspaceShell.swift` |
| Cuaderno | `kmp/iosApp/App/NotebookModuleView.swift` |
| Top bar Cuaderno | `kmp/iosApp/App/NotebookTopBar.swift` |
| Grid Cuaderno | `kmp/iosApp/App/NotebookDataGrid.swift` |
| Anadir columna | `kmp/iosApp/App/AddColumnSheet.swift` |
| Planner iOS | `kmp/iosApp/App/PlannerWorkspaceIOS.swift` |
| Rubricas masivas | `kmp/iosApp/App/RubricBulkEvaluationSheet.swift` |
| Horario docente | `kmp/iosApp/App/TeacherScheduleSettingsView.swift` |
| Diseno global | `kmp/iosApp/App/EvaluationDesign.swift` |
| Apple IA | `kmp/iosApp/App/AppleFoundationContextualAIService.swift` |
| Apple Reports | `kmp/iosApp/App/AppleFoundationReportService.swift` |
| macOS | `kmp/iosApp/MacApp/` |
| Compartido Apple | `kmp/iosApp/AppleShared/` |

## UI/UX

Prioridades:
- Menos ruido visual, jerarquia clara, acciones principales visibles.
- Inspector util y no invasivo; menus compactos.
- Coherencia iOS/macOS.
- No anadir opciones sin utilidad diaria real.

## Cuaderno

El Cuaderno es pantalla critica.

Prioridades:
- Carga rapida al cambiar de grupo.
- Grid estable.
- Media fiable y explicable.
- Categorias claras.
- Columnas ocultas seguras.
- Formulas funcionales.
- Rubricas integradas.
- Inspector correcto.
- Diferenciar datos brutos de notas evaluables.

No rehacer `NotebookModuleView.swift` completo.

No hacer:
- Anadir componentes pesados sin necesidad.
- Meter logica compleja en la View si debe vivir en KMP.
- Romper la compatibilidad con categorias, columnas ocultas, formulas, rubricas o media.

## KMP y SQLDelight

Solo tocar `kmp/shared/` cuando:
- la logica de negocio sea incorrecta,
- haya que modificar ViewModels,
- haya que crear modelos o casos de uso,
- el usuario lo pida explicitamente.

Solo tocar `kmp/data/` cuando:
- haya bug de persistencia,
- haya que modificar queries,
- haya que anadir tablas,
- haya que cambiar repositorios.

Si se toca SQLDelight:
- revisar migraciones,
- evitar cambios destructivos,
- mantener compatibilidad con datos existentes,
- anadir indices si hay consultas nuevas relevantes.

## Build y comprobaciones

Elegir segun alcance:
- KMP/shared: `./gradlew :shared:test`.
- SQLDelight/data: `./gradlew :data:desktopTest`.
- iOS/macOS Apple: `xcodebuild` con el esquema afectado.
- UI: build y, si procede, capturas o QA manual.

Si un comando falla por entorno, registrar el fallo y el motivo (ver `docs/AGENT_WORKFLOW.md`).

## Flujo Git, PR y entregable

Revisar `git status --short --branch` antes de tocar archivos. Para el flujo completo (ramas, worktree, commits, changelog, PR, formato de entregable), seguir la skill `registrar-avance-app`, `docs/AGENT_WORKFLOW.md` y `docs/REPO_GOVERNANCE.md` — no repetir aqui ese contenido.

No mezclar tareas no pedidas.
