# Ámbito: Cuaderno

## Estado actual

- Grid SwiftUI en `kmp/iosApp/App/Notebook*.swift`. Datos desde `KmpBridge` (`notebookState`).
- Paso 1 (PR 268): caché de filas con firma de celdas y borradores optimistas que se limpian solos.
- Paso 2 (`codex/lag-grid-cuaderno`): menos repintados, foco calculado en el padre, resize al soltar, firma de fila completa, scroll al navegar con Enter, tareas canceladas al cambiar de grupo.

## Terreno de juego

- `NotebookModuleView.swift` (no rehacer entero), `NotebookDataGrid.swift`, `NotebookModuleGridCells.swift`, `NotebookEditableTableCell.swift`, `NotebookModuleColumnModel.swift`, `NotebookGridContent.swift`.
- Stores: `Bridge/KmpBridgeObservationStores.swift`.

## Trampas

- Las firmas de `NotebookDataSignatures` se reutilizan si la instancia de `NotebookUiStateData` es la misma (`===`). Solo es válido mientras esa clase Kotlin sea inmutable.
- `isFocused` y `navigationDirection` deben estar en el `==` de cada celda; si no, la celda queda obsoleta.
- Todo dato nuevo que pinte una fila (asistencia, riesgo, resaltado) debe entrar en `notebookRowContextDigest`, o la fila no se repinta.
- El ancho de columna en vivo es local a la cabecera: las celdas cambian al soltar.
- Los borradores optimistas solo se limpian cuando el valor guardado coincide; un formato distinto los deja hasta cambiar de grupo.
- `scrollToRow` no hace nada si el viewport aún no está medido.
- `xcodebuild` puede reescribir `*.xcscheme`: restaurar antes de commitear.
- Los avisos de fondo y de teclado van por `NotebookCellNoticeRouter` (un observador); toda celda editable debe registrarse ahí, no con `onReceive` propio.
- La zebra se pinta solo en el fondo de la fila (`notebookRowView`); `notebookColumnCellFill` no debe volver a pintarla.
- Las celdas de solo lectura no fijan altura: la impone la fila (`notebookGridRowHeight`). No reintroducir `height: 52`.
- La nota de rúbrica llega como texto ("7,5 / 10"): `NotebookRubricValueLabel.parse` lo interpreta; si cambia el formato, ajustar ahí.
- El nombre de nivel (`NotebookGradeBand.levelName`) es por bandas de nota, no los niveles reales de la rúbrica.
- Las micro-animaciones del grid (`NotebookAnimatedGradeText`, anillo de Media, barra de nivel) dependen de que `animation(value:)`/`keyframeAnimator(trigger:)` no disparen en el primer render: no envolver el grid en `withAnimation` ni cambiar la identidad de la celda al hacer scroll, o los números "rodarán" al aparecer.
