# ADR 2026-06-19 - Split Notebook UI State

## Status

Accepted.

## Context

`NotebookUiState.Data` concentra estructura, filas, selección, guardado, inspector y medias del Cuaderno. En Apple, observar ese estado agregado desde SwiftUI hace que cambios calientes como selección o guardado de una celda puedan invalidar superficies que solo necesitan cabecera, filas o estado de guardado.

## Decision

`NotebookViewModel` mantiene `NotebookUiState` como contrato agregado de compatibilidad, pero expone estados derivados y pequeños:

- `NotebookStructureState`: pestañas, columnas, categorías y grupos.
- `NotebookRowsState`: filas y drafts de celdas.
- `NotebookSelectionState`: columnas seleccionadas y celda/editor activos.
- `NotebookSaveState`: dirty/saving/saved.
- `NotebookInspectorState`: detalle actual del inspector.
- `NotebookAverageState`: medias y explicaciones cacheadas por alumno.

Todos se publican como `StateFlow` con `distinctUntilChanged()` y `SharingStarted.Eagerly` para mantener el último valor disponible aunque Swift se suscriba después de la carga inicial.

## Consequences

SwiftUI puede observar `bridge.notebookRowsState`, `bridge.notebookStructureState` y `bridge.notebookSplitSaveState` sin depender de `bridge.notebookState` para cada superficie.

El estado agregado sigue existiendo para pantallas auxiliares y compatibilidad con Desktop, pero `KmpBridge` evita reenviarlo cuando solo cambia selección/editor y no cambian estructura, filas ni drafts.

La frontera de persistencia SQLDelight no cambia.
