# AGENTS.md - mi_gestor_evaluaciones

## Proyecto

App educativa KMP + SwiftUI para gestion docente: cuaderno, rubricas, asistencia, alumnado, planificacion, informes, sync, backups y modulos especificos de Educacion Fisica.

Prioridad:
- Uso diario fiable.
- SwiftUI iOS/macOS premium, limpio y nativo.
- Arquitectura KMP estable.
- Cambios pequenos, seguros y revisables.

## Paso previo obligatorio

Antes de escribir codigo, pensar como implementar de la mejor manera las ideas del skill `jobs-design-philosophy`:
- Simplicidad radical: una pantalla debe tener una tarea principal obvia.
- Whitespace generoso para reducir carga cognitiva.
- Rejilla disciplinada de 8pt; usar 4pt solo para microajustes justificados.
- Jerarquia visual clara, con un unico foco dominante.
- Cambios quirurgicos que no alteren la logica de negocio salvo peticion expresa.
- Eliminar ruido visual, divisores innecesarios y acciones sin utilidad diaria real.
- Validar mentalmente el Test del Aire, el Test del Bizqueo y el Test de la Obviedad.

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

No tocar salvo peticion explicita:
- `KmpBridge.swift`
- `kmp/shared/`
- `kmp/data/`
- `EvaluationDesign.swift`
- `desktopApp/`

## Skills

| Intencion | Skill |
|---|---|
| UI/UX SwiftUI | `swiftui-polish` |
| Bug SwiftUI | `swiftui-bugfix` |
| Funcion nativa Apple | `swiftui-native-feature` |
| Adaptacion macOS | `swiftui-macos-adapt` |
| Binding Swift-KMP | `kmp-bridge-fix` |
| Logica KMP | `kmp-logic-fix` |
| SQLDelight | `sqldelight-fix` |
| Servicios Apple | `apple-service-patch` |

Usar una sola skill principal por tarea, salvo que el usuario pida una intervencion transversal.

## Reduccion de alcance

Por defecto:
- 1 View.
- 1 flujo.
- 1-3 archivos.
- 1 entregable.
- Sin refactor global.

Si el archivo es grande, acotar a una seccion, componente o flujo concreto.

Archivos especialmente grandes o sensibles:
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

## Archivos protegidos

No modificar salvo orden explicita:
- `kmp/iosApp/App/KmpBridge.swift`
- `kmp/iosApp/App/EvaluationDesign.swift`
- `kmp/shared/domain/`
- `kmp/data/src/commonMain/sqldelight/`
- `kmp/desktopApp/`

Si parece necesario tocarlos, explicar primero el motivo.

## UI/UX

La app debe sentirse:
- premium,
- nativa Apple,
- minimalista,
- rapida,
- clara para uso docente diario.

Prioridades:
- Menos ruido visual.
- Jerarquia clara.
- Acciones principales visibles.
- Menus compactos.
- Inspector util y no invasivo.
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

Antes de finalizar, intentar ejecutar las comprobaciones relevantes.

Pendiente de confirmar comandos reales del proyecto.

Posibles comprobaciones:
- Build iOS desde Xcode.
- Build macOS desde Xcode.
- Tests KMP si se toca `kmp/shared/`.
- Verificacion SQLDelight si se toca `kmp/data/`.

No inventar comandos si no estan claros en el repo.

## Entregable

Responder siempre con:
1. Resumen breve.
2. Archivos modificados.
3. Cambios realizados.
4. Que no se ha tocado.
5. Riesgos o pendientes.
6. Casos probados.
7. Diff o resumen del diff.

No mezclar tareas no pedidas.
No hacer refactors globales sin autorizacion.
