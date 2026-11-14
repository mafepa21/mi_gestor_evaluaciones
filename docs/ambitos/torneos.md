# Ámbito: Torneos

## Estado actual

- Torneos ligados a una Situación de Aprendizaje. Formatos: Liga, Rotaciones, Eliminatoria, Liguilla + eliminatorias y Liguilla + puestos (nadie queda eliminado: quien gana sigue por los puestos de arriba).
- F1 (`codex/torneos-cuadro-f1`): línea de fases y cuadro en árbol con «Seguir a» en el detalle (iPad y Mac).
- F2 (`codex/torneos-proyeccion-f2`): ventana de proyección en el Mac abierta con «Proyectar» (`MacTournamentProjectionWindow`, `SdaProjectionScenes`, `TournamentProjectionModel`) y recarga con la sync.
- Pendiente: F3 (canal en directo iPad → helper → Mac). Decisiones del docente: la proyección se abre sola, solo muestra «Equipo N · Pista P» (sin nombres) y usa fondo claro.

## Terreno de juego

- Lógica pura: `kmp/iosApp/AppleShared/Tournament/` (`TournamentPlan`, `PlacementTournament`, `KnockoutBracketResolver`, `BracketTreeLayout`, `TournamentPhaseTimeline`).
- SwiftUI: `kmp/iosApp/App/Tournament/` (`SdaTournamentDetailView` es grande: cambios acotados; `SdaBracketTreeView`, `SdaPhaseTimelineView`, `SdaTournamentLiveView`).
- Persistencia: el plan entero viaja como JSON en la entidad `learning_situation_tournament` (SyncLAN la cubre con `.learningSituations`).
- Tests: `kmp/iosApp/PlannerTests/` (`BracketTreeLayoutTests`, `TournamentPhaseTimelineTests`, `PlacementTournamentTests`, `TournamentEngineTests`).

## Trampas

- Los números «P» de los huecos («Gana P5») son índices en el calendario guardado, no ids.
- En Liguilla + puestos el pase directo (grupo impar) se detecta porque la pareja salta una ronda.
- `placementBracket` (en `PlacementTournament.swift`) es `internal` para que lo lea `BracketTreeLayout`: cualquier cambio en la regla del árbol cambia el dibujo.
- Si el calendario guardado no cuadra con el árbol (p. ej. cambió `placementRounds`), `BracketTreeLayout.make` devuelve nil y la vista muestra un aviso en vez del cuadro.
- «En juego» en el árbol es una deducción (primera ronda con partidos pendientes y las dos parejas conocidas): el plan no guarda qué se está jugando. El estado real llegará con F3.
- `BracketTreeLayout.make` se recalcula en cada render del detalle; vigilar con torneos muy grandes.
- `SyncEventListener` trata cualquier `data:` desconocido como «sincroniza ya»: el canal en directo de F3 no puede ir por `/sync/events`.
- `TournamentProjectionModel` nunca expone nombres: todo equipo pasa por `ProjectionTeamLabels` («Equipo N», N = posición en `plan.teams`). Un texto nuevo de la proyección debe entrar en `allTexts` para que el test de nombres lo cubra. Un participante que no es equipo del plan solo pasa tal cual si es un hueco de la lista `isSlotPlaceholder` («Gana P5», «Clasificado 1 Grupo A», «3º liguilla»…); si no, sale «Equipo». Un formato nuevo de hueco hay que añadirlo ahí.
- En la proyección, la ronda «en juego» y el «descanso» son deducciones (primera ronda con partidos pendientes; descanso = ronda previa completa y ningún resultado en la actual). No hay reloj hasta F3.
- El cuadro proyectado se parte en mitades solo si una ronda tiene más de 8 partidos.
- La proyección se refresca con `.tournamentPlanSaved` (guardado en este Mac) y con `.reloadOnLanSync(.learningSituations)`. Un guardado que no pase por `SdaTournamentStore` no la refresca.
- `SdaTournamentStore.refreshFromDatabase()` no hace nada si hay cambios sin guardar. El detalle aplaza la recarga mientras haya una hoja, integrantes, inscripción o modo directo abiertos (`hasPendingRemoteReload`).
- «Proyectar» y `openWindow` solo existen bajo `#if os(macOS)`. `SdaProjectionScenes.swift` es SwiftUI puro: no meter AppKit ahí.
- La ventana de proyección guarda un monitor de teclado (Esc) y una actividad de `ProcessInfo` para no dormir el Mac. Ambos se liberan en `willClose`.
- `groupStandings` devuelve «Grupo Grupo A» (bug previo, sin arreglar). La proyección usa `GroupStageConfiguration.groupName`.
