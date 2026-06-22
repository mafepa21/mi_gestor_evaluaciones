# ADR 2026-06-22: Adjuntos diferidos en celdas del Cuaderno

## Estado

Aceptado.

## Contexto

El snapshot del Cuaderno se abre para pintar muchas celdas a la vez. Hasta ahora `selectNotebookCellsByClass` proyectaba `attachment_uris_csv` y cada `PersistedNotebookCell` materializaba la lista completa de URIs, aunque el grid solo necesita saber si hay evidencia y cuantos adjuntos mostrar.

Esto incrementaba payload, memoria y trabajo de parseo en la apertura del grid.

## Decision

`PersistedNotebookCell` transporta metadatos ligeros para el grid: `attachmentCount`, `hasAttachments` y `mainIcon`. La query de listado calcula el conteo y no devuelve `attachment_uris_csv`.

Las URIs completas se cargan con `loadCellAttachmentUris(classId, studentId, columnId)` solo cuando una superficie necesita detalle real: inspector del Cuaderno, sync/export o flujos equivalentes de serializacion.

## Consecuencias

- El grid conserva badges, radar e insights con conteos sin cargar rutas completas.
- El inspector hidrata la lista al abrir la celda y mantiene el guardado existente con `saveCell(... attachmentUris)`.
- Sync/export sigue serializando URIs completas mediante la consulta puntual.
- No se cambia el almacenamiento fisico: `attachment_uris_csv` permanece como fuente persistida compatible.
