# Mapa de flujos · Situaciones de Aprendizaje (Fase 1)

Fecha: 2026-10-03 · Rama: `codex/ui-situaciones-aprendizaje` · Solo análisis, sin cambios de código ni compilación.
Abreviaturas: WV = `LearningSituationsWorkspaceView.swift`, SS = `LearningSituationScheduleSheet.swift` (ambos en `kmp/iosApp/App/`).

## 1. Tareas del docente y coste hoy
1. **Leer una SdA** (diario): 1 toque en la fila (WV:890). Criterios, saberes, DUA y tablas van cerrados: 1 toque por bloque (WV:1189-1219).
2. **Abrir módulo vinculado**: 1 toque, pero "Vínculos creados" está al final (WV:964-965, :1127).
3. **Evaluar**: abrir hoja (WV:1013), 2 toques por instrumento para elegir rúbrica (:2104), 1 para crear (:1925). Con DOCX: 3 ventanas. Con rúbrica Excel: 4 ventanas apiladas.
4. **Programar**: 2 toques (WV:1007, SS:592). Con secuenciación DOCX: selector + 2 ventanas.
5. **Importar** (inicio de curso): 4-5 toques y 2 ventanas. En lote, cada documento se abre para asignar grupo (:1653) y "Importar" sigue desactivado hasta que todos lo tengan (:1620).
6. **Cambiar estado**: 3 toques en submenú anidado (WV:1034).
7. **Duplicar**: 4+ toques (WV:768).
8. **Borrar**: 3 toques (WV:1049); en lote, modo selección + confirmar.

## 2. Ventanas a fusionar o quitar
- Vista previa simple (:1541) y de lote (:1596): una sola "Revisar importación" (1 documento = lote de 1). Añadir "Asignar grupos a todas" y preseleccionar `selectedClassId`.
- "Editar" reutiliza esa hoja: título "Editar ficha".
- EvaluationSheet:
  - Vista previa de instrumentos (:1952) y de pruebas físicas (:1961) pasan a navegación con push dentro del `NavigationStack` existente (:1802).
  - Vista previa de rúbrica Excel (:1970) se elimina: resumen en la fila del instrumento y el archivo abre directo el editor.
  - `RubricsBuilderScreen` (:1977) se mantiene como hoja (otro módulo; en Mac necesita 1120 pt).
  - Alerta "Nueva pestaña" (:1994) pasa a campo inline.
  - Selector único de origen: "De la SdA · Documento Word · Pruebas físicas" (hoy 3 secciones excluyentes, :1832-1894).
- Alertas de borrado simple y lote (:778, :786): un solo `confirmationDialog`.
- Fallo al recargar el detalle (:1286): aviso inline, no alerta.

## 3. Problemas de usabilidad
Vista principal:
- `HStack` fijo maestro-detalle (:715-720, mín. 336 pt): en iPhone el detalle queda aplastado. Falta `NavigationSplitView` o control por size class.
- Acción principal ambigua: "Importar" (:835) y "Programar" (:1012) ambas prominentes; CTA de vacío duplicado (:871, :971).
- Ruido: estadísticas (:848, :950) y hash SHA (:1088).
- Filtros escondidos en un `Menu` (:909) sin indicar cuántos hay activos. Mejor chips + "Limpiar" + `.searchable`.
- Sin estado de carga: se ve un vacío falso (:868).
- Selección múltiple solo borra; menú contextual solo "Eliminar" (:893). Archivadas mezcladas con activas.
- Accesibilidad: badge en mayúsculas con tracking (:1472), fila sin `accessibilityElement(children: .combine)`, botón de solo icono con `.help`, `.largeTitle` redondeado (:945) se desborda con Dynamic Type grande.

ScheduleSheet:
- Doble cierre: "Cerrar" (SS:168) y "Cancelar" (:586).
- Fila de controles (:244-295) no se reparte en líneas: se corta en iPhone.
- "Inicio común" sobrescribe fechas por grupo sin aviso (:199-203).
- Jerga en subtítulo (:235), icono decorativo (:212).
- Secuenciación DOCX: botón pequeño (:284), tarjeta plegada (:61).
- Errores solo por alerta (:174); sin estado inline de "sin periodos de evaluación".
- Estilos mezclados: EvaluationDesign, NotebookStyle, plannerGlassPanel y `Color.purple` (:249).

## 4. Estilo visual (decisión recomendada)
`EvaluationDesign` editorial para el contenido. Vidrio solo en el chrome del sistema. Nada de estilo denso. Motivo: una SdA es un documento que se lee; el vidrio sobre texto largo resta legibilidad.

## 5. Archivos nuevos propuestos
No se toca la proyección (WV:96-600) ni el puente.
- `LearningSituationsWorkspaceView.swift`: solo proyección + shell adaptativo; conserva estado, `reload`/`reloadDetail` y `loadedDetailSituationId`.
- `LearningSituationsListColumn.swift`: búsqueda, chips, lista, selección múltiple, vacíos.
- `LearningSituationDetailView.swift`: cabecera, acciones, lectura curricular, vínculos (subidos) y documento.
- `LearningSituationsComponents.swift`: badge de estado, tarjeta, listas, tabla.
- `LearningSituationImportReviewSheet.swift`: revisión unificada.
- `LearningSituationDuplicateSheet.swift`.
- `LearningSituationEvaluationSheet.swift`: `NavigationStack` con selector de origen.
- `LearningSituationAssessmentReviewView.swift`: destino de push.
- `LearningSituationScheduleControls.swift`: controles de cabecera adaptables.
- Al extraer: quitar `private`, `xcodegen --spec kmp/iosApp/project.yml`, commitear `project.pbxproj`.

## 6. Estados para la maqueta (Fase 2)
- **Lista:** cargando (skeleton), vacío inicial, sin resultados con filtros, con datos, archivadas ocultas/visibles, selección múltiple con 0 y N.
- **Detalle:** nada seleccionado, cargando, completo, sin payload curricular, sin vínculos, aviso inline de error.
- **Tamaños:** iPhone (stack), iPad horizontal y vertical, Mac ventana estrecha, Dynamic Type XXL.
- **Importar:** leyendo, revisión de 1, lote con fallos parciales, documento sin grupos, error total.
- **Programar:** cargando, sin grupos, sin franjas, sin periodos de evaluación, 1 grupo, varios (ancho y compacto), secuencia DOCX con avisos, guardando, error.
- **Evaluar:** origen SdA con rúbrica pendiente/completa, DOCX (push), pruebas físicas (push), pesos ≠ 100 %, sin pestañas, creando, error.
- **Confirmaciones:** borrado simple y en lote; duplicar sin grupos y con grupos.
