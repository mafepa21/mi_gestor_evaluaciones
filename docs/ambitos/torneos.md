# Ámbito: Torneos

## Estado actual

- Torneos ligados a una Situación de Aprendizaje. Formatos: Liga, Rotaciones, Eliminatoria, Liguilla + eliminatorias y Liguilla + puestos (nadie queda eliminado: quien gana sigue por los puestos de arriba).
- F1 (`codex/torneos-cuadro-f1`): línea de fases y cuadro en árbol con «Seguir a» en el detalle (iPad y Mac).
- Pendiente: F2 (ventana de proyección en el Mac con la sync de hoy) y F3 (canal en directo iPad → helper → Mac). Decisiones del docente: la proyección se abre sola, solo muestra «Equipo N · Pista P» (sin nombres) y usa fondo claro.

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
- Las vistas de torneo no llevan `.reloadOnLanSync`: un torneo abierto en el Mac no se refresca al llegar resultados (lo arregla F2).
- `SyncEventListener` trata cualquier `data:` desconocido como «sincroniza ya»: el canal en directo de F3 no puede ir por `/sync/events`.
