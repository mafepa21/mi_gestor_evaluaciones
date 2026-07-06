---
name: planner-workspace
description: Trabaja sobre el módulo de Planificación (Planner) en iOS/iPadOS/macOS - Semana, Día, Secuencia, Resumen, composer de sesiones, drag & drop, informes PDF. Usar SIEMPRE que la tarea mencione planificación, planner, sesiones planificadas, secuencia didáctica, situaciones de aprendizaje agendadas, el Gantt trimestral, la miniatura semanal o el informe PDF del planificador, aunque el usuario no diga "Planner" (ej. "quiero mover una sesión de un día a otro", "el informe de la semana sale mal").
version: 1.0.0
---

# planner-workspace

## Por qué existe esta skill

El Planner es el segundo módulo más grande de la app tras el Cuaderno y acaba de cerrar un rediseño de 8 fases (navegación universal, datos reales, drag & drop, Día cockpit, Secuencia Gantt, Resumen dashboard, PDF, paridad Mac). Su arquitectura de archivos es extensa y muy fácil de romper si se toca sin mapa. Esta skill es el mapa.

## Mapa de arquitectura

### Estado y lógica (ViewModel troceado por extensiones)

`PlannerWorkspaceViewModel.swift` es el núcleo; cada preocupación vive en su propia extensión. Tocar SOLO la extensión de la preocupación afectada:

| Preocupación | Archivo |
|---|---|
| Grid semanal | `PlannerWorkspaceViewModel+WeekBoard.swift` |
| Vista Día | `PlannerWorkspaceViewModel+DayBoard.swift` |
| Secuencia didáctica | `PlannerWorkspaceViewModel+Sequences.swift` |
| Composer crear/editar sesión | `PlannerWorkspaceViewModel+Composer.swift` |
| Movimiento en cascada (drag & drop) | `PlannerWorkspaceViewModel+CascadeMove.swift` |
| Operaciones en bloque | `PlannerWorkspaceViewModel+BulkOperations.swift` |
| Informe PDF | `PlannerWorkspaceViewModel+Report.swift` |
| Diario ligado a sesión | `PlannerWorkspaceViewModel+Journal.swift` |
| Horario docente | `PlannerWorkspaceViewModel+Schedule.swift` |
| Presentación/formateo | `PlannerWorkspaceViewModel+Presentation.swift` |

Modelos de presentación en `PlannerModels.swift`. La proyección semanal es `PlannerWeekRenderModel`: consulta celdas por clave día/franja; las vistas leen de esta proyección, no recalculan desde el bridge.

### Vistas por sección

- **Semana**: `PlannerWeekMiniatureGrid.swift` (miniatura semafórica ~200pt) + `PlannerWeekMiniatureLayout.swift` + `PlannerWeekDetailPane.swift` (detalle contextual por sesión/franja/día). Los slots vacíos crean sesión sin salir del grid.
- **Día**: `PlannerDayView.swift` ("cabina de vuelo" del día).
- **Secuencia**: `PlannerSequenceGanttView.swift` — Gantt horizontal por trimestre, filas por situación de aprendizaje, subfilas colapsables por grupo, línea de semana actual.
- **Resumen**: `PlannerSummaryDashboard.swift` — métricas semanales, próximas sesiones, cobertura diaria y alertas. No añade lógica KMP: agrega datos ya cargados.
- **Detalle/edición**: `PlannerSessionDetailSheet.swift`, `PlannerSessionComposerSheet.swift`.
- **Chrome**: `PlannerFloatingTabBar.swift` (tab bar flotante Liquid Glass) y `kmp/iosApp/AppleShared/PlannerLiquidGlassControls.swift` (botones `.glass`/`.glassProminent`, densidad en menú secundario). Para estilos glass, seguir `liquid-glass-design`.

### Informe PDF

`PlannerReportDocument.swift` (es `@MainActor` — no quitarlo, fue un fix explícito) + `PlannerReportPDFRenderer.swift`. El PDF incluye resumen y justificación documental.

## Invariantes del módulo (no romper)

1. **La Secuencia renderiza el plan completo, no solo lo agendado.** Cruza `LearningSituationSessionPlan` (secuencia teórica, vía `learningSituationSessionPlans(sequenceVersionId:)` del bridge) con las `PlanningSession` del calendario (`plannerListAllSessions()`). Las no ubicadas aparecen como "Pendiente de ubicar" con botón `+` que abre el composer precargado con `learningSituationSessionPlanId`, título, objetivos y actividades. Si tocas el guardado del composer, verifica que `learningSituationSessionPlanId` se sigue propagando por `plannerSaveSessionWithLinks` → `openComposer`/`saveComposer`/`updateSessionFromComposerSave`; perderlo rompe el cálculo de progreso de la secuencia.
2. **La fuente de verdad de densidad es `vm.density`** (el picker vive en el menú secundario de `PlannerLiquidGlassControls`, no en la toolbar).
3. **macOS reutiliza las vistas iPadOS** (mismo toolbar, tab bar, miniatura, Gantt, Resumen). No reintroducir sidebar interna ni inspector lateral en macOS: se eliminaron a propósito.
4. **El estado de expansión del strip de progreso persiste en `@AppStorage`.**
5. **Drag & drop en cascada** pasa por `PlannerCascadeDropCoordinator.swift`; si añades un archivo Swift nuevo al Planner, recuerda que hubo que añadirlo al target de Xcode (el script de build corre `xcodegen generate`).

## Cómo trabajar aquí

1. Identificar la sección afectada (Semana/Día/Secuencia/Resumen/Composer/PDF) y limitarse a sus archivos.
2. Los cambios visuales siguen `jobs-design-philosophy` y `swiftui-polish`; los datos nuevos que necesite una vista se cargan en la extensión del VM correspondiente, nunca con llamadas al bridge desde el body de la vista.
3. Si la feature necesita datos que el bridge no expone, escalar a `kmp-feature-vertical` (fue exactamente el caso del enriquecimiento de Secuencia).
4. Verificar con `./scripts/verify_apple_builds.sh` (iOS + macOS: este módulo comparte vistas entre ambos, un `#if os` mal puesto rompe el otro target).
5. Cerrar con `registrar-avance-app`.

## Interacciones a revisar mentalmente antes de entregar

Cambiar de semana, abrir detalle desde miniatura, crear sesión desde slot vacío, arrastrar sesión (cascada), colapsar grupo en el Gantt, agendar una "Pendiente de ubicar", generar el PDF, y todo lo anterior también en macOS.

## Salida esperada

Sección afectada, archivos tocados, invariantes verificadas (citarlas), builds ejecutados y riesgos por plataforma.
