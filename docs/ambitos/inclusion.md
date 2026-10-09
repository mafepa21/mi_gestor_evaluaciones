# Ámbito: Inclusión (plazos del Manual)

## Estado actual

- Pantalla «Inclusión» en iPhone, iPad y Mac: alumnado con medidas de nivel III/IV del grupo seleccionado, tareas del manual por fase, marcar hecha, editar fecha, restablecer, tarea libre y fecha de evaluación inicial del grupo.
- Al cargar se llama a la generación idempotente de tareas. «Esta semana» = próximos 7 días (estado `SOON` de KMP).

## Terreno de juego

- Pantalla real: `kmp/iosApp/App/InclusionTrackerView.swift` (incluye `InclusionTrackerStore`).
- Piezas visuales compartidas: `kmp/iosApp/AppleShared/InclusionTrackerComponents.swift`. La maqueta `InclusionTrackerMockView.swift` queda solo para #Preview.
- Puente: `kmp/iosApp/App/Bridge/KmpBridge+Inclusion.swift`. Lógica: `InclusionManual` e `InclusionTasksUseCase` en KMP.
- Navegación: `AppWorkspaceModule.inclusion` (`IPadWorkspaceShell.swift`), `IOSFeatureRegistry`, `IOSRootView`, `WorkspaceModuleSwitcher`, `MacFeatureRegistry`, `MacRootView`.

## Trampas

- Nombres duplicados: la maqueta define `InclusionPhase`, `InclusionDeadlineStatus` en Swift y KMP tiene los suyos; los de KMP se escriben `MiGestorKit.X` y en la vista se usan los `...UI` del puente.
- Una carga tardía de otro grupo se descarta con `InclusionLoadGate` (la posee el store de la vista); `loadInclusionBoard` devuelve `nil` en ese caso.
- Medida retirada: su tarea pendiente se oculta en el puente y los contadores se recalculan sobre lo visible; la hecha se conserva.
- Añadir un caso a `AppWorkspaceModule` obliga a tocar switches exhaustivos: `WorkspaceLayoutState+Extensions.swift` (dos) y `WorkspaceModuleSwitcher.swift`.
- `verify_apple_builds.sh` regenera el proyecto con XcodeGen y toca el `.xcscheme`: no commitear ese ruido.
- Sin runtimes de simulador instalados en esta máquina: no hay capturas de iOS.
- La hoja «Añadir tarea» es genérica en el id del alumno (`InclusionAddTaskSheet<ID>`): la maqueta usa UUID y la pantalla real Int64. Guardar con varios alumnos usa `addInclusionTasks` (una transacción en `insertFreeTasks`); con ninguno marcado no actúa y muestra «Elige al menos un alumno».
- Añadir un método a `InclusionTaskRepository` obliga a actualizar el `FakeTasks` del test de `InclusionTasksUseCaseTest`.
- `./gradlew` falla dentro del sandbox (bloqueo de `~/.gradle`); ejecutarlo fuera.
