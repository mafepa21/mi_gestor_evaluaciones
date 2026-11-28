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
- Grupos desde Torneos: `SdaWorkGroupsManagerSheet` llama a `selectClass` del curso del torneo y espera a que `notebookState` sea de ese curso; cambia el curso abierto en el Cuaderno a propósito. El arrastre de varios alumnos viaja como un solo texto «id,id,id» y `handleDrop` lo trocea.
- Marcas de grupo (migración 52): son por alumno y grupo-clase; «sin marca» se guarda como `NONE`, no se borra. El tablero las relee con la notificación `.workGroupMarksDidChange` (al guardar y tras un lote de Sync LAN). Qué columnas cuentan como Técnica/Comportamiento/Liderazgo vive en `UserDefaults` (`WorkGroupSkillSelectionStore`) y no se sincroniza. Nunca pasar a Swift un `Map<Long, …>` de Kotlin: usar listas (`WorkGroupStudentScore`).
- Grupos de trabajo: `WorkGroupBoardDraft` guarda movimientos recientes 2 s para que una recarga vieja no los pise; el emparejado provisional-real es por nombre y luego por orden. No volver a `selectClass(force = true)` por cada arrastre: usar `scheduleWorkGroupReload` (Kotlin).
- Los tests de `NotebookViewModelTest` usan scope `Unconfined`: para probar `delay`/debounce hay que pasar un scope con `StandardTestDispatcher(testScheduler)`.
- Texto del grid: usar `.notebookFont(size:weight:design:)` (en `NotebookGridStyle.swift`), no `.font(.system(size:))`. Escala con Dynamic Type en iOS y no cambia nada en macOS. Por dentro delega en `ScaledSystemFont` (`ScaledSystemFont.swift`); fuera del Cuaderno se usa `.scaledSystemFont`.
- Hojas sin letra fija: `NotebookColumnStatisticsSheet`, `NotebookSeatingPlanView`, `NotebookStudentInspector`, `RubricBulkEvaluationSheet`, `StudentProfile360Sheet` e `IPadWorkspaceShell` tienen 0 `.font(.system(size:` y 0 `.primary.opacity`. Mínimo 11 pt: los antiguos 8-10 pt pasaron a 11.
- Iconos o iniciales dentro de un `.frame(width:height:)` fijo llevan `.dynamicTypeSize(...DynamicTypeSize.xxxLarge)`: si se quita el tope, en AX3 se salen del marco.
- Topes de Dynamic Type fuera del grid: la ficha de pupitre del plano (`.frame(width: 172, height: 142)`) no crece (`...large`); el panel del inspector (`NotebookInspectorPanel`) crece hasta `xxxLarge`. Si se quitan, en AX3 se parten palabras ("EN-TRAN", "Sin regis-").
- Hojas con filas de tarjetas (estadísticas de columna, Ficha 360, plano de clase): con `dynamicTypeSize.isAccessibilitySize` pasan de fila a columna. Toda fila nueva de tarjetas debe hacer lo mismo.
- Plano de clase: el lienzo nunca baja de `minimumCanvasWidth` (columnas × 188 + 120) y en pantallas estrechas se desplaza en horizontal. Si cambia el ancho de la ficha (172) o el reparto de `defaultSeatPositions`, ajustar ese mínimo. Las fichas no suben de y = 132 para no tapar la pizarra.
- El grid tiene tope de Dynamic Type en AX2 (`NotebookDynamicType.gridRange`). La altura de fila escala con `notebookRowScale` y lleva el mismo tope a mano (1.95): si cambia uno, cambiar el otro.
- El deslizamiento de asistencia en la celda Nombre no llega a VoiceOver: sus acciones están duplicadas como `accessibilityAction(named:)`. Toda acción nueva del deslizamiento debe añadirse también ahí.
- Las cabeceras de columna usan `onTapGesture`; su lectura y su acción de VoiceOver están en `columnHeaderAccessibilityLabel` y en la `accessibilityAction` del mismo bloque.
- El editor de media recibe todas las columnas pero filtra por `visibleColumnIds` (pestaña activa) y descarta ocultas; `buildUpdates` preserva las demás. Si cambia el filtro del grid, el editor lo sigue solo.
- Todo dato de columna que pinte la cabecera (p. ej. peso de media) debe entrar en `NotebookRenderCacheKey`; si no, la cabecera sigue mostrando la columna cacheada.
- El peso de columna es un % literal: `columnWeightBadge` no reinterpreta 1 ni valores <1.
- Una nota NUMERIC se valida (`isValidNotebookNumericInput`) ANTES de crear el borrador optimista y de marcar "guardando"; si no, un texto como "8,5a" se queda pintado sin guardarse. En Swift se valida al confirmar (`saveNumeric`), no a cada tecla, y al pegar se saltan los inválidos.
- «Revisar cierre» (`NotebookClosingReviewSheet`, caso de uso `BuildNotebookClosingReportUseCase`) es de solo lectura y se calcula una vez al abrir la hoja desde `data.sheet`; no se refresca si cambian notas con la hoja abierta. Su salto a celda vive en `NotebookModuleClosingReview.swift` y reutiliza `gridScrollProxy.scrollToRow` + `inspectorSelection`/`focusedCellId`: solo hay desplazamiento vertical, el grid no tiene scroll horizontal programable.
- «Nota que no se entiende» = columna NUMERIC cuya celda persistida tiene `textValue` no numérico. Si cambia dónde se guarda el texto escrito, ajustar `unreadableTextFor`. Las columnas calculadas, rúbricas y ordinales vacías salen como «vacías», nunca como «no se entiende».
- Los códigos de criterio (`CE 2.1`) salen de `container.competenciesRepository.listCompetencies()` (puente `KmpBridge+NotebookClosing.swift`); si falla la lectura, la hoja muestra «Criterio N» en vez de fallar.
- Al añadir archivos Swift nuevos hay que correr `xcodegen generate` en `kmp/iosApp` y commitear solo `project.pbxproj` (restaurar los `*.xcscheme`).
- Cambio de grupo: `selectClass` publica el estado del grupo nuevo en cuanto `notebookRowsState` trae sus filas (`publishNotebookDataWhenReady`, en `KmpBridge+Notebook.swift`), sin esperar el debounce de 150 ms de `notebookStateSubject`. El debounce sigue para lo demás (escritura en celdas). No convertir `notebookViewModel.state` en `asAsyncSequence` para esto: `FlowAsyncSequence` no cancela su `collect` y deja un recolector vivo por llamada.
- Montaje en tres vueltas: `isGridMounted` (la tabla se monta en la vuelta siguiente, con `DispatchQueue.main.async`: `.task` arranca en la misma vuelta) y `NotebookScrollSyncCoordinator` empieza con `visibleRange` vacío y publica las filas tras su primer `install`. Lo que dependa del grid (`gridNavigationContext`, `scrollProxy`) no existe en la primera vuelta.
- En Mac, abrir el Cuaderno redibuja `NotebookMacLayout` varias veces en la misma vuelta porque `MacRootView` se recalcula al cambiar de pantalla (bindings `selectedClassId`/`selectedStudentId`). Es lo siguiente a recortar si la primera vuelta (~270 ms en Debug) vuelve a dar «Pantalla congelada».
- El `body` de `NotebookModuleView` lleva `AnyView` entre bloques de modificadores (contenido, hojas/tareas, observadores) y `notebookLoadedContent` antes de su cadena de hojas. Sin ellos la primera apertura congela ~450 ms (Swift resuelve el tipo anidado nivel a nivel). No quitarlos; al añadir muchas hojas o `onChange` a un bloque, valorar otro corte. No poner `AnyView` en filas ni celdas.
- `NotebookVoiceGradeDictationService` crea reconocedor y motor de audio al primer dictado: `audioEngine` es opcional y `stopListening` no debe crearlo.
- Pruebas físicas: la pareja marca/nota se reconoce por nombre («X · Marca|Nivel» y «X · Nota») dentro de la misma categoría (`NotebookPhysicalColumns.pairs`). Si se renombra una de las dos, la celda vuelve a ser la editable normal y la marca oculta deja de verse: renombrar ambas.
- La celda física pinta la columna de nota y lee la marca de la columna oculta (`displayValue(for:column: pair.raw)`). Las columnas ocultas no cuentan en la media (`NotebookPerformanceCaches`): por eso se oculta la marca y no la nota.
- El arreglo de columnas físicas (`repairPhysicalColumnsIfNeeded`) escribe en el repositorio, no en `saveColumn` del ViewModel: ese crea una evaluación nueva al guardar una columna numérica que cuenta y no tiene `evaluationId`.
- Toda evaluación genera una columna `eval_<id>` (`BuildNotebookSheetUseCase.mergeColumns`). El alta de una prueba física crea una evaluación con su nombre; el arreglo la oculta y la saca de la media.
- El cronómetro de la celda y el grupal miden con `ProcessInfo.systemUptime`, no sumando ticks del `TimelineView`.
- El texto de exportar no se publica: `notebookExportTextProvider`/`exportTextProvider` lo calculan al exportar leyendo `bridge.notebookState`. No volver a meter `exportText(data:)` en `syncToolbarState` ni en un `ShareLink(item:)` de menú.
- El `onChange(of: toolbarStateKey)` vive solo en `notebookLoadedContent`; no duplicarlo en `centerPanel`.
- Navegar con Enter: foco inmediato solo si `gridScrollProxy.isRowMounted` era verdad antes del scroll; si no, la espera de 0,12 s es el respaldo. No quitarla sin otra forma de saber que la fila ya está montada.
- `selectClass(force)` cancela la carga anterior (`loadJob`). Todo `catch (e: Exception)` en cargas debe dejar pasar antes `CancellationException`, o acabará en `Error`.
- Con la hoja masiva de rúbricas abierta, `NotebookViewModel` está en pausa (`setReactiveReloadPaused`): el observador y `NotebookRefreshBus` solo anotan. Toda vía nueva de abrir la hoja debe pausar y toda vía de cerrarla debe pasar por `closeBulkRubricEvaluation`, que reanuda. Un cambio de clase quita la pausa.
- Rúbrica individual sin avance automático: la recarga la hace el observador de `isSaveSuccessful` en `KmpBridge.swift`, no `saveRubricEvaluation`.
- `RubricBulkEvaluationSheet` no observa el bridge: lee vía `watchedBridge` (`KmpBridgeWatch` sobre `bulkRubricEvaluationState` y `classes`). Todo dato nuevo del bridge que pinte la hoja debe añadirse a esa lista o la hoja no se refrescará.
- `BulkRubricStudentRow` y `BulkRubricCompactRow` son `Equatable`: todo dato nuevo que pinten debe entrar en su `==`, o la fila se queda con lo viejo. Las acciones nuevas reciben ids y leen el estado al ejecutarse; nunca capturan datos de la fila.
- La caché de la hoja de grupo (`BulkRubricSnapshotMemo`) se invalida por identidad del estado Kotlin. Solo vale mientras `BulkRubricEvaluationUiState` sea inmutable (siempre `copy`).
- `RubricBulkEvaluationViewModel.load` replica la regla de `getGradeForColumn` (primero la evaluación de la columna, luego `columnId`) sobre `listGradesForClass`. Si cambia `getGradeForColumn`, cambiar también `resolveCellGrades`.
- La carga por lote vuelve a la lectura individual con columnas virtuales `eval_<id>` o notas ambiguas: es la vía segura, no un fallo.
- Hoja de grupo de instrumentos: sus celdas 1-4 y Sí/No son `Equatable` (`StructuredBulkScaleCell`, `StructuredBulkCheckCell`). Lo nuevo que pinten debe entrar en su `==`. Su apertura sigue leyendo alumno por alumno.
- `NotebookModuleView` no observa `NotebookBridgeStore` entero: lo recalcula `NotebookStoreRenderWatch`, con lista cerrada que deja fuera los estados de guardado (los pintan `NotebookToolbarSaveStatus` y el observador `NotebookSaveStateChangeObserver`). Todo `@Published` nuevo que deba repintar el Cuaderno hay que añadirlo a esa lista.
- Solo `NotebookSyncStatusLabel` observa `DashboardBridgeStore` en el Cuaderno. No volver a leer `dashboardStore` desde `NotebookModuleView`.
- El resumen de celdas por fila (`NotebookRowCellDigestCache`) se reutiliza si `row ===` y las columnas visibles del panel son las mismas. Vale solo mientras `NotebookRow` sea inmutable.
- Las tablas de `NotebookGridNavigationContext` (categoría y pareja física) se rehacen solo si cambia la instancia de `data.sheet`.
- «Enviar notas al alumnado» copia la Media tal cual (`averageExplanation` de la pestaña activa): una columna oculta que cuenta sale en el informe. Si cambia qué entra en la Media, el informe lo sigue solo; no recalcular en `BuildStudentGradeReportsUseCase`.
- El nivel de rúbrica del informe se ordena por puntos, no por `order` de edición. El correo de familias no existe en el modelo (`Student.email` es el único): la opción «Familia» de la maqueta quedó fuera.
- «Comentario de evaluación» es una columna de texto normal (`instrumentKind` privado, no cuenta para la media) que se reconoce por su título en cada pestaña (`KmpBridge.evaluationCommentColumn`). Si el docente la renombra, la exportación a Educamos no la encuentra sola y hay que elegirla en el menú de la fila «Comentarios».
- Importar comentarios empareja por posición: fila N del Excel → alumno N en el orden de `data.sheet.rows`. Las filas vacías cuentan y no desplazan a los siguientes: no usar `AppleSpreadsheetReader.readRows` aquí, que descarta filas vacías; `EvaluationCommentImport.readTable` conserva el número de fila.
- Con plantilla de Educamos se leen sus filas de alumnado (`EducamosSMStudent.rowIndex`) y su columna `TipoColumna=20`. `EducamosSMXMLParser` numera filas por orden de aparición, no por su atributo `r`: si una plantilla tuviera filas omitidas, `rowIndex` y la lectura por número de fila no coincidirían.
- El guardado en bloque escribe directo al repositorio y recarga una vez (`saveEvaluationComments`); devuelve el texto anterior para «Deshacer».
- Importar por código «Alumno NN»: la clave sale de `BulletinBaseReportBuilder.codeNumbers` con el alumnado de `listStudentsInClass`, igual que el informe anónimo. Si se da de alta o de baja a alguien después de generar el informe, los números se mueven: el pie de la hoja lo advierte. Cualquier cambio en `codeOrder` rompe la importación de textos ya generados.
- «Cerrar evaluación» (`EvaluationClosingSheet`) sustituye a «Revisar cierre» en los menús, pero reutiliza `NotebookClosingReviewSheet` como paso «Notas» (`embedded: true`). Al tocar un aviso hay que cerrar toda la hoja con `onFinish`, no con el `dismiss` del paso (solo volvería atrás); el salto a la celda sigue en `goToPendingClosingTarget`.
- Los sellos se guardan en `iconValue` de la celda. Al leer de la base de datos, `annotation.icon` llega vacío: hay que leer `annotation?.icon ?? iconValue`.
- «Ya lo he subido» y el último Excel generado viven en `UserDefaults` por grupo y pestaña (`EvaluationClosingStore`): no se sincronizan entre iPad y Mac.
- «Valoración rápida» guarda en «Tu valoración» con formato «Fortaleza: A, B. A mejorar: C. Orientación: D.» en la primera línea (`QuickNoteComposer`) para volver a marcar las fichas al abrir. Las frases no pueden llevar comas ni puntos (`QuickNoteCatalog.sanitize`).
- Pestaña de evaluación (ADR 003): es una raíz con hijas. `NotebookEvaluation` (KMP) es la única fuente de la nota por bloques. `withActiveTabAverages` y `WebPortalGrades.scope` deben coincidir: si se toca uno, hay que tocar el otro.
- El Resumen agrupa por categorías de mentira `evalblock:<tabId>`: no existen en la base de datos. Su menú contextual no puede renombrar ni mover (`categoryContextMenu`).
- `activeNotebookTabId` acepta bloques (pestañas hijas); la barra de arriba marca su evaluación con `activeRootNotebookTabId`.
- Swift no ve los parámetros por defecto de Kotlin: cualquier `NotebookTab(...)` o `NotebookRow(...)` en Swift debe pasar `weight:` y `evaluationExplanation:`.
- Etiquetas de trimestre en pruebas: sin cifras 1, 2 o 3, o `TeacherTermNoteKeys.fromLabel` las convierte en T1–T3 y se mezclan con otras pruebas.
- «Organizar por evaluaciones…» se abre desde el menú del shell (iPad, iPhone y Mac) con `layoutState.openNotebookOrganizeTabs()`. El menú «Pestañas» de `notebookCommandMenuContent` solo existe en la vista compacta: lo que se ponga solo ahí no se ve en iPad ni en Mac.
- Exportar a Educamos: la «Nota final» la decide `EducamosFinalGradeSource`, que usa la evaluación del trimestre del Excel y, si no la reconoce, la de la pestaña abierta. Las SA se emparejan con `EducamosSATabMatcher`, que nunca empareja con una evaluación, y se guardan en el mismo diccionario de `UserDefaults` que las columnas con el valor `tab:<id>`.
