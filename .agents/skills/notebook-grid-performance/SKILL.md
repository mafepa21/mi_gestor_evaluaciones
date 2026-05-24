---
name: notebook-grid-performance
description: Optimiza problemas de fluidez del Cuaderno SwiftUI cuando el grid, las categorias, el resize de columnas, seleccion/foco o popovers provocan lag en iOS, iPadOS o macOS. Usar antes de cambios visuales amplios cuando el sintoma sea rendimiento del grid.
version: 1.0.0
---

# notebook-grid-performance

## Objetivo
Corregir cuellos de botella del Cuaderno sin tocar logica de negocio, KMP ni SQLDelight salvo que la causa raiz sea claramente de datos. El cambio debe ser pequeno, medible y compatible con iOS/iPadOS/macOS.

## Evidencia local que origino esta skill
- 2026-05-23: lag al plegar/desplegar categorias y `Invalid sample AnimatablePair`.
- 2026-05-23: resize de la primera columna fija provocaba repintados caros.
- 2026-05-23: seleccion, foco y popovers invalidaban filas completas del grid.
- `memoria` registra reglas ya aprendidas sobre `NotebookRow.persistedCells`, evitar `withAnimation` masivo y no consultar `KmpBridge` por cada celda visible.

## Archivos frecuentes
- `kmp/iosApp/App/NotebookModuleView.swift`
- `kmp/iosApp/App/NotebookGridContent.swift`
- `kmp/iosApp/App/NotebookModuleGridCells.swift`
- `kmp/iosApp/App/NotebookModuleColumnModel.swift`
- `kmp/iosApp/App/NotebookModuleDisplayFormatting.swift`
- `kmp/iosApp/App/NotebookDataGrid.swift`

## Proceso
1. Localiza el estado que cambia durante la interaccion: categoria colapsada, ancho, seleccion, foco, popover, hover, edicion o busqueda.
2. Traza su alcance de invalidacion: fila, segmento, header, grid completo o bridge.
3. Reduce el alcance antes de cambiar diseno:
   - pasa solo valores primitivos o bindings estrechos a subviews;
   - evita que estado transitorio viva en un ancestro que renderiza todas las filas;
   - extrae subviews pequenas solo si encapsulan invalidacion real;
   - usa `Equatable`/snapshots estables si encaja con patrones existentes.
4. Evita animaciones estructurales en grids grandes:
   - no envolver cambios de categorias/segmentos en `withAnimation`;
   - desactivar animacion durante drag/resize con transacciones;
   - reservar animaciones para feedback local, no insercion/eliminacion masiva.
5. Para resumenes de categorias o celdas, preferir datos ya presentes en `NotebookRow.persistedCells` / `persistedGrades`; llamar al `bridge` solo para edicion, guardado o calculo puntual.
6. Mantener la arquitectura del grid: no revertir decisiones centrales como zonas fijas izquierda/derecha o el uso de `VStack` si la alineacion depende de ello.

## No hacer
- No tocar `KmpBridge.swift`, `kmp/shared/`, `kmp/data/` ni migraciones por un problema de lag visual.
- No introducir caches globales sin invalidacion clara.
- No arreglar rendimiento mezclandolo con rediseno visual amplio.
- No ocultar el problema con delays artificiales o debounce que rompa edicion diaria.

## Validacion
- Compilar la target SwiftUI afectada cuando sea viable.
- Revisar mentalmente estas interacciones: scroll horizontal/vertical, plegar categoria, resize de columna fija, seleccionar celda, abrir/cerrar popover, editar celda.
- Confirmar que el cambio reduce invalidacion o trabajo por celda; no basta con que "se vea igual".

## Entrega
Responder con causa raiz, archivos tocados, optimizacion aplicada, riesgos restantes y pruebas ejecutadas.
