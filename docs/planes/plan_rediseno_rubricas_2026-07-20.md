# Plan: Rediseño visual del módulo Rúbricas (macOS 26 + iPadOS/iOS)

**Estado: 6/6 PR implementados y abiertos (2026-07-20), pendientes de revisión y merge.** Cadena `feature/redesign-rubricas-1..6` desde `feature/redesign-cuaderno-12`, en PRs apilados (cada uno contra el anterior; el primero, #133, contra `feature/redesign-cuaderno-12`). Varios ítems se desviaron del plan original tras leer el código real antes de tocarlo (más detalle en cada PR y en `docs/CHANGELOG.md`): el ítem 1 del PR 4 (portar el scroll-fix de `fix/rubrica-niveles-sin-scroll`) resultó innecesario porque el rediseño del Cuaderno ya lo resolvió de otra forma (`ViewThatFits`); el ítem 3 del PR 5 (señal de fila incompleta) ya existía en el layout ancho de la evaluación masiva, solo faltaba portarlo al layout compacto; el ítem 2 del PR 5 (unificar `levelColor`) se descartó deliberadamente porque sirve a un propósito distinto (comparar niveles entre sí, no mostrar una nota final). Sin verificación visual real en ningún PR (Xcode.app completo no disponible en el entorno de ejecución) — pendiente antes de mergear la cadena a `main`.

## Contexto

El usuario pidió revisar el trabajo ya hecho en la cadena `feature/redesign-cuaderno-1..12` (rediseño visual premium del Cuaderno, HIG macOS 26/iPadOS 26 + Liquid Glass) y, con ese lenguaje de diseño como base, analizar la sección **Rúbricas** en todos sus aspectos y proponer un rediseño equivalente. Este documento es esa propuesta: diagnóstico completo del estado actual y un plan de PRs en el mismo formato que `docs/planes/plan_rediseno_cuaderno_2026-07-15.md` (esa rama todavía no está en `main`; este documento se ha redactado leyendo su contenido y sus diffs vía `git show`/`git diff`, sin hacer checkout, para no interferir con otras sesiones que tienen worktrees activos sobre ese mismo trabajo).

Dato clave que cambia el punto de partida: el rediseño del Cuaderno **ya tocó una esquina de Rúbricas**. Su PR 6 ("Rúbricas desde el cuaderno") reescribió la evaluación embebida (`RubricEvaluationView.swift`, `RubricBulkEvaluationSheet.swift`) y creó `RubricEvaluationStyle.swift` como archivo de tokens local. El resto del módulo — banco/listado de rúbricas, builder de criterios×niveles, vinculación a una pestaña del cuaderno — **no se tocó** y sigue en un lenguaje visual anterior, desconectado del nuevo. Esta propuesta cierra ese hueco: extiende el PR 6 del Cuaderno al módulo completo, en vez de inventar un lenguaje nuevo.

## Alcance de la investigación

- Diff completo `main...feature/redesign-cuaderno-12` (15 commits, 16 archivos) y lectura íntegra de `NotebookGridStyle.swift` y `RubricEvaluationStyle.swift` en la punta de esa rama.
- Mapa completo del módulo Rúbricas tal y como está en `main` hoy: 6 vistas SwiftUI, 7 archivos KMP compartidos (viewmodels, modelo de dominio, repositorio, esquema SQLDelight).
- Cruce con dos auditorías estáticas ya existentes pero no versionadas (`plan_auditoria_layout_2026-07-15.md`, `plan_auditoria_ui_2026-07-15.md`) que ya señalan bugs concretos en Rúbricas.
- Cruce con 4 ramas no mergeadas que tocaron rúbricas en algún momento (`fix/rubrica-niveles-sin-scroll`, `fix/apple-p2-visual-hig-polish`, `codex/rubrics-direct-bulk-evaluation`, `nueva-ui`).

## Lenguaje de diseño heredado (resumen; fuente: `plan_rediseno_cuaderno_2026-07-15.md` + código real verificado)

No repito aquí la investigación HIG completa del plan del Cuaderno (glass = chrome nunca contenido, jerarquía por espacio no decoración, radios concéntricos, rejilla de 8pt, dígitos monoespaciados) porque sigue vigente sin cambios. Lo que sí cambia es que ahora existe **código real, no solo un plan**, y verificarlo revela varias divergencias entre lo prometido y lo implementado que esta propuesta debe evitar repetir:

- **Tokens reales de `NotebookGridStyle.swift`**: `gridLine = primary.opacity(0.07)`, `gridLineStrong = primary.opacity(0.14)`, `zebra = primary.opacity(0.025)`, `rowHover = primary.opacity(0.04)`, `columnActiveWash = primary.opacity(0.04)`, anillo de selección `accentColor` ancho 2 + `cellSelectionFill = accentColor.opacity(0.08)` (tarjetas) / `cellSelectionSurface` opaca (celdas de grid) + `cellSelectionShadow = accentColor.opacity(0.22)`, `Radius { cell:6, chip:8, card:12 }`, banda de nota `NotebookGradeBand` (`<5` bajo, `5..<7` medio, `≥7` alto, colores adaptativos light/dark vía `appAdaptiveBrandColor`).
- **Liquid Glass real solo existe en un sitio** de toda la cadena: el contenedor de pestañas del Cuaderno (`NotebookTabStrip.swift:202`, `.glassEffect` + `GlassEffectContainer`, gateado `#available(iOS 26/macOS 26)` con fallback `.ultraThinMaterial`). El plan prometía `glassEffectID` estable por pestaña con morphing nativo; el código real usa un `matchedGeometryEffect` con un string constante (`morphID`), sin rama `#available` — no hay morphing de cristal real, solo interpolación de un material estático. El patrón correcto sí existe en el repo (`PlannerFloatingTabBar.swift:124`). Si esta propuesta introduce algún control tipo pestaña, debe copiar ese patrón correcto, no el de `NotebookTabStrip`.
- **`PremiumCard.glass`** (componente preexistente, `AppleShared/AppleAppEnvironment.swift:530-546`), pese al nombre, no es cristal: es una superficie opaca (`adaptiveSurfaceBackground` + stroke + shadow). Es el contenedor que ya usan las vistas de rúbrica tocadas por el Cuaderno. Coherente con la regla "glass nunca en contenido", aunque el nombre confunda.

## Diagnóstico

### Mapa de archivos del módulo

| Archivo | Líneas | Rol | Tocado por PR 6 del Cuaderno |
|---|---|---|---|
| `kmp/iosApp/MacApp/MacRubricsView.swift` | 1131 | Banco/gestión de rúbricas, macOS | No |
| `kmp/iosApp/App/RubricsBuilderScreen.swift` | 385 | Editor CRUD (criterios × niveles), sheet compartido Mac/iOS/iPad | No |
| `kmp/iosApp/App/RubricsReportsWorkspaceViews.swift` (`RubricsWorkspaceView`, L4-634) | ~630 de 2158 | Banco/gestión de rúbricas, iOS/iPad (el resto del archivo es el módulo Informes, sin relación) | No |
| `kmp/iosApp/App/AssignRubricToTabView.swift` | 315 | Vincular una rúbrica existente a clase + pestaña/columna del Cuaderno | No |
| `kmp/iosApp/App/RubricEvaluationView.swift` | 382 | Evaluación de un alumno, embebida desde el Cuaderno | **Sí** |
| `kmp/iosApp/App/RubricBulkEvaluationSheet.swift` | 1011 | Evaluación masiva (matriz alumnos × criterios) | **Sí** |
| `kmp/iosApp/App/RubricEvaluationStyle.swift` | 115 | Tokens locales (creado por el rediseño) | **Sí (nuevo)** |

Modelo de datos KMP (`kmp/shared/.../domain/Models.kt:200-312`, esquema en `AppDatabase.sq:77-182`): `Rubric` (banco) → `RubricCriterion` (peso 0-1, renormalizado a sumar 1) → `RubricLevel` (puntos, pertenece a un criterio en BD aunque el builder los presenta como columnas compartidas entre criterios, reconciliadas por orden al guardar). `RubricDetail.calculateScore()` pondera por criterio y **solo cuenta en el denominador los criterios ya evaluados** — una rúbrica a medio evaluar puede mostrar una nota completa. La entidad `Evaluation` es el puente real Rúbrica↔Cuaderno; existen **dos vías de código distintas** que la crean (`RubricsViewModel.saveRubric()` de forma automática, y `AssignRubricToTabView` por otro camino que además crea una `NotebookColumnDefinition`), y cada evaluación se escribe por duplicado en `Grade.rubricSelections` (string) y en la tabla normalizada `RubricAssessment`. Estas tres observaciones son de modelo de datos, no de UI — se documentan como contexto y quedan fuera del alcance visual de este plan (ver Restricciones).

### Ya documentado en auditorías previas (heredar, no reinvestigar)

- **L-5** (`plan_auditoria_layout_2026-07-15.md`): `RubricBulkEvaluationSheet` (`minWidth 1320, minHeight 860`) y `RubricsBuilderScreen` (`1200×820`) son, literalmente, "los dos peores casos" de hoja modal que no cabe en un portátil de 900×600 citados en esa auditoría.
- **L-7**: `MacRubricsView.rubricsTable` + panel de detalle viven en un `HStack` **no ajustable** con mínimos (400-560) que además contradicen los mínimos internos de sus `TableColumn` (suman más que el `maxWidth` del contenedor).
- **UI-2**: la búsqueda global del iPad se muestra en Rúbricas pero no filtra nada (binding no conectado).
- **UI-13**: en macOS, Rúbricas cae en el inspector genérico del shell (`MacRootView.swift:136` no incluye `.rubrics` en la lista de exclusión) y reserva 320-440pt para un placeholder sin contenido real.

### Hallazgos nuevos de esta sesión

1. **Tres escalas de color semántico distintas para el mismo concepto** ("nota buena/mala"): la banda de 3 niveles del grid (`<5`/`5-7`/`≥7`, adaptativa), el `scorePill` de la evaluación individual (corte fijo en 5.0, `RubricBulkEvaluationSheet.swift:642`) y el tinte de nivel por ratio de puntos en la evaluación masiva (4 bandas en 0.8/0.6/0.4, `RubricBulkEvaluationSheet.swift:625-636`). Ninguna se referencia entre sí pese a expresar la misma idea.
2. **Escala de radios desconectada**: `NotebookGridStyle.Radius` define `cell:6`, `chip:8` (sin ninguna referencia real en todo el código, radio muerto), `card:12`. `RubricEvaluationStyle` define `cardRadius:16` y `rowRadius:14` en un espacio aparte, sin relación declarada con la escala del grid. El literal `16` reaparece más de 10 veces fuera de estos tokens (incluida la tarjeta elevada del grid); el literal `10`, más de 12 veces como resto de una escala pre-rediseño sin consolidar.
3. **Opacidad de hover sin token único**: `0.04` en filas de grid y en niveles de rúbrica (mismo valor, sin compartir símbolo), `0.05` en las pestañas del Cuaderno — tres sitios, tres literales.
4. **`RubricsBuilderScreen.swift` no usa ningún token compartido**: ni `MacAppStyle` ni `EvaluationDesign`, todo hardcodeado inline (radios 12/8, `Color.accentColor.opacity(...)` suelto). Es la pantalla del módulo con menos disciplina de tokens, y precisamente donde un docente pasa más tiempo (crear/editar una rúbrica).
5. **`RubricsWorkspaceView` (iOS/iPad) mezcla tres orígenes de token en la misma vista**: `EvaluationDesign.accent/success`, `IOSAppStyle.warning`, `appCardBackground` genérico.
6. **El tamaño correcto de `RubricBulkEvaluationSheet` para macOS ya existe, pero en código inalcanzable**: `IPadWorkspaceShell.swift:882` ya tiene la versión flexible y probada (`minWidth 900, idealWidth 1180, minHeight 600, idealHeight 760`), pero vive en `AppWorkspaceShell`, una vista que el `MacRootView` real **nunca instancia**. El sitio que sí se ejecuta en producción (`MacRubricsView.swift:291`) sigue con el `1320×860` fijo. No hace falta inventar valores nuevos para L-5/L-7 en Mac: solo trasladarlos.
7. **El `ScoreBadge` quedó a medio migrar**: la cabecera de `RubricEvaluationView` pasó de tamaño fijo (`28pt black rounded`) a `.title2.weight(.semibold)` (Dynamic Type), pero el `ScoreBadge` justo al lado sigue siendo `EvaluationScoreBadge` de `EvaluationDesign.swift`, sin tocar: radio 12 literal, fuente fija `.black` rounded 18pt.
8. **El panel resumen no es sticky**, aunque el plan original lo pedía como "tarjeta pinned": vive dentro del mismo `ScrollView` que los criterios y sube/baja con el scroll.
9. **La navegación de `RubricBulkEvaluationSheet` no siguió el plan** ("control segmentado o stepper del sistema"): la implementación real es una matriz alumnos×criterios con foco movido por teclado en macOS. A juicio de este análisis es una interacción mejor para puntuar una clase entera que un stepper — pero quedó como desviación silenciosa, no como decisión documentada.
10. **`RubricLevelTile` usa tamaños de fuente fijos en puntos** (`14`, `11`) en vez de fuentes semánticas — no escala con Dynamic Type, a diferencia de la cabecera de la misma pantalla que sí se corrigió.
11. Un comentario de código (`NotebookGridStyle.swift`, banda de nota) remite a `averageState` como origen del corte "aprobado = 5.0"; ese valor real vive en otro sitio (`RubricBulkEvaluationSheet.swift:642`) — cita desactualizada, sin impacto funcional pero confusa para quien mantenga el código.

## Restricciones duras

- **Solo visual.** No se toca el modelo de datos (`Rubric`, `RubricCriterion`, `RubricLevel`, `Evaluation`, `Grade`, `RubricAssessment`) ni la lógica de negocio (`RubricsViewModel`, `RubricEvaluationViewModel`, `RubricBulkEvaluationViewModel`, `RubricEvaluationBus`, `RubricImporter`). Las tres observaciones de modelo de datos del diagnóstico (doble vía de vinculación, escritura duplicada Grade/RubricAssessment, semántica de `Rubric.classId` como "sugerencia" no vinculante) se documentan para una futura decisión de producto, no se corrigen aquí.
- **No tocar `EvaluationDesign.swift`** mientras sigan activas las ramas de auditoría (`fix/auditoria-ui-2026-07` y `fix/auditoria-ui-presentacion-2026-07` tienen worktree activo ahora mismo en este repositorio). Mismo criterio que ya aplicó el PR 6 del Cuaderno: los tokens nuevos viven en un archivo local aparte y se migran cuando esas ramas aterricen.
- No tocar `KmpBridge.swift`, `kmp/shared/`, `kmp/data/`, `desktopApp/`.
- 1 PR por ítem, commits atómicos en español (`ui(rubricas): …`), entrada en `docs/CHANGELOG.md` por PR, sin batch-merge de ramas el mismo día.
- **Rama base: `feature/redesign-cuaderno-12`, no `main`.** Los PR 1-6 de este plan extienden `RubricEvaluationStyle.swift` y reutilizan `NotebookGridStyle.swift`; ninguno de los dos existe todavía en `main`. Cuando esa rama se mergee, rebasar. Nombre sugerido para la cadena: `feature/redesign-rubricas-<n>`.

## Coordinación con auditorías activas (leer antes de empezar PR 2)

Las mismas líneas que el PR 2 de este plan necesita tocar (`MacRubricsView.swift:291`, `MacRootView.swift:136`, el tamaño de `RubricsBuilderScreen`) son exactamente los ítems L-5, L-7 y UI-13 que las auditorías `fix/auditoria-layout-2026-07`/`fix/auditoria-ui-2026-07` ya tienen asignados, y esas ramas **tienen worktree activo en este momento** (`fix/auditoria-ui-2026-07` en `.claude/worktrees/agent-a9d2368ceb163bfba`, a `e9b62bb`; `fix/auditoria-ui-presentacion-2026-07` en `.claude/worktrees/auditoria-ui-encuadre`, a `daef07a`). Antes de empezar PR 2, comprobar `git log --oneline main..fix/auditoria-ui-2026-07` (o la rama que corresponda): si L-5/L-7/UI-13 ya aterrizaron en `main`, PR 2 se convierte en un simple rebase + pase de tokens; si no, hay que decidir entre esperar a que aterricen o absorber esos ítems concretos aquí mismo y avisar para que la auditoría los excluya de su alcance al llegar a Rúbricas. No abrir PR 2 sin resolver esto primero.

## PR 1 — Fundación: `RubricsStyle` (renombrar y ampliar `RubricEvaluationStyle`)

**Archivos**: renombrar `kmp/iosApp/App/RubricEvaluationStyle.swift` → `RubricsStyle.swift` (recordar `xcodegen generate` para darlo de alta en el proyecto — el mismo paso que se le olvidó a un merge anterior y rompió el build, `docs/audit/INCIDENCIA_2026-07-14-build-roto-post-merge.md`).

1. Unificar el color semántico de nota: reexportar `NotebookGradeBand`/`NotebookGridStyle.gradeLow/Mid/High` desde `RubricsStyle` (referenciar, no duplicar) y aplicar el mismo corte `<5`/`5-7`/`≥7` al `scorePill` de la evaluación individual, al tinte de nivel por ratio de la evaluación masiva y a cualquier indicador de progreso nuevo del listado. Es el cambio de mayor impacto de todo el plan: conecta visualmente "puntuar una rúbrica" con "ver la nota en el cuaderno".
2. Resolver la escala de radios: decidir explícitamente si `rowRadius` (hoy 14) es una excepción consciente frente a `NotebookGridStyle.Radius.card` (12) — y documentarlo en un comentario — o si se consolida a 12. No dejarlo como un cuarto valor sin explicación.
3. Un solo token de hover (`RubricsStyle.hover = Color.primary.opacity(0.04)`), mismo valor que `NotebookGridStyle.rowHover`.
4. Añadir tokens para las piezas que cubre este plan y que PR 6 del Cuaderno no necesitaba: superficie de tarjeta de banco/listado, hairline de tabla (reusar `NotebookGridStyle.gridLine/gridLineStrong` por valor), radio de blueprint-card del builder (12, coherente con las blueprint cards de `AddColumnSheet`).
5. Mantener y actualizar la nota de bloqueo de `EvaluationDesign.swift`.

**Aceptación**: `swiftc -parse` limpio; `xcodegen generate` registra el archivo renombrado; una única función de banda de nota usada por grid y por las cuatro superficies de rúbrica; cero radios/opacidades nuevos fuera de esta escala en los PR 2-6.

## PR 2 — Banco/gestión de rúbricas (Mac + iPad/iPhone)

**Archivos**: `MacRubricsView.swift`, `RubricsReportsWorkspaceViews.swift` (solo `RubricsWorkspaceView`), `RubricsBuilderScreen.swift` (solo su presentación como sheet, no su contenido), `MacRootView.swift:136`.

**Requiere resolver primero la sección "Coordinación con auditorías activas".**

1. Sustituir el `HStack` fijo de dos columnas de `MacRubricsView` por un contenedor realmente ajustable (`HSplitView`), con mínimos coherentes con L-7: tabla `minWidth 340, ideal 460`, revisar los mínimos de las `TableColumn` internas para que quepan.
2. Excluir `.rubrics` del inspector genérico del shell (`MacRootView.swift:136`), cerrando UI-13.
3. Redimensionar la presentación de `RubricsBuilderScreen` como sheet: de `1200×820` fijo a `minWidth 860, idealWidth 1200, minHeight 560, idealHeight 800`, contenido interno scrollable, botonera anclada fuera del scroll (política L-5).
4. Redimensionar la presentación de `RubricBulkEvaluationSheet` desde `MacRubricsView.swift:291`: sustituir `1320×860` fijo por los valores ya validados y en uso real en `IPadWorkspaceShell.swift:882` (`minWidth 900, idealWidth 1180, minHeight 600, idealHeight 760`) — trasladar, no inventar.
5. Adoptar tokens de PR 1 en tarjetas/tabla (el archivo ya usa bastante `MacAppStyle`; es más un pase de consistencia que una reescritura).
6. iOS/iPad (`RubricsWorkspaceView`): unificar los tres orígenes de token mezclados (`EvaluationDesign`, `IOSAppStyle`, `appCardBackground` genérico) bajo `RubricsStyle` + el color de banda de PR 1.

**Aceptación**: con la ventana a 900×600, banco de rúbricas visible sin recortes (tabla + detalle); Rúbricas usa todo el ancho sin placeholder de inspector; builder y evaluación masiva caben en un portátil de 900×600 con botonera visible.

## PR 3 — Builder (`RubricsBuilderScreen` + `RubricBuilderGridView`)

**Archivos**: `RubricsBuilderScreen.swift`.

1. Sustituir los radios sueltos (12, 8) y `Color.accentColor.opacity(...)` ad hoc por `RubricsStyle`.
2. Alinear el idioma de selección de nivel/criterio con las blueprint cards de "Nueva columna" del Cuaderno (mismo anillo 2pt + fill 0.08), para que crear una rúbrica y crear una columna se sientan del mismo sistema.
3. Conservar intacto `RubricBuilderGridView` y su `GeometryReader`/`makeLayout(in:)` — es la única pieza ya responsiva del módulo hoy; solo reskin de superficies, no tocar el cálculo de layout.
4. No introducir un quinto valor de radio fuera de la escala resuelta en PR 1.

**Aceptación**: crear una rúbrica de 6 criterios × 4 niveles se lee con el mismo lenguaje visual que el grid del Cuaderno; sin radios/colores hardcodeados nuevos.

## PR 4 — Evaluación individual: cerrar lo que dejó a medias el PR 6 del Cuaderno

**Archivos**: `RubricEvaluationView.swift`, `RubricsStyle.swift`. No tocar `EvaluationDesign.swift`.

1. Adoptar directamente la corrección ya validada en la rama sin mergear `fix/rubrica-niveles-sin-scroll` (`88ea4e7`, solo toca este archivo): sustituye el `ScrollView` horizontal de niveles (tiles fijos 170×110 que ocultaban niveles) por un `LazyVGrid` + `PreferenceKey` de ancho disponible que fuerza fila única. Cherry-pick directo, ya probado.
2. Definir `RubricScoreBadge` local en `RubricsStyle` (mismo patrón que `RubricLevelTile`: override local, sin tocar `EvaluationDesign.swift`) con tipografía semántica y el color de banda unificado de PR 1, para que deje de ser el único elemento sin migrar de la pantalla.
3. Decidir explícitamente el panel resumen: (a) hacerlo sticky de verdad en pantallas ≥720pt (lo que pedía el plan original y hoy no ocurre), o (b) documentar por qué se descarta. Recomendación: (a), ya que a ese ancho sobra espacio para fijarlo sin robar altura a los criterios.
4. Migrar los tamaños de fuente fijos de `RubricLevelTile` (14, 11) a fuentes semánticas (Dynamic Type), igual que ya se hizo con la cabecera.

**Aceptación**: capturas light/dark; con 6 criterios × 4 niveles no hay fatiga visual (Test del Bizqueo); el badge de puntuación se lee como parte del mismo sistema que la cabecera; Dynamic Type AX1-AX2 no rompe el layout de los tiles.

## PR 5 — Evaluación masiva: consolidar la matriz como patrón oficial

**Archivos**: `RubricBulkEvaluationSheet.swift`.

1. Adoptar formalmente la matriz alumnos×criterios (ya implementada) como el patrón oficial en vez de perseguir el stepper del plan original — es más eficiente para puntuar una clase entera. Documentar la decisión en el propio código o en el changelog para que no vuelva a leerse como "desviación del plan".
2. Aplicar el color de banda unificado de PR 1 al `scorePill` (hoy corte fijo en 5.0) y al tinte de nivel por ratio de puntos (hoy 4 bandas en 0.8/0.6/0.4).
3. Añadir una señal visual discreta (punto/borde, nunca fill) de "fila incompleta" por alumno, aprovechando que `calculateScore` ya sabe qué criterios faltan por evaluar — reusar `NotebookGridStyle.statePending`.
4. Heredar el tamaño de sheet corregido en PR 2.

**Aceptación**: puntuar 5 alumnos seguidos resulta obvio sin leer texto (criterio ya definido en el plan original); un vistazo a la matriz distingue alumnos incompletos sin abrir cada fila.

## PR 6 — `AssignRubricToTabView` y pasada de consistencia

**Archivos**: `AssignRubricToTabView.swift`, auditoría cruzada de PR 1-5.

1. Pase de tokens en `AssignRubricToTabView`; revisar su tamaño fijo (`720×560` en Mac) contra la misma política de sheets de la auditoría de layout.
2. Auditoría cruzada: mismo anillo de selección, mismo hover (0.04 en todos lados), mismos radios (escala resuelta en PR 1, sin huérfanos), mismo color de banda en las cuatro superficies (grid, banco/listado, evaluación individual, evaluación masiva).
3. Registrar como nota (no como acción de este plan) la doble vía de vinculación Rúbrica↔Cuaderno y la escritura duplicada `Grade.rubricSelections`/`RubricAssessment`, para una decisión de producto futura — fuera de alcance visual, toca `kmp/shared`.

**Aceptación**: Test del Bizqueo y Test del Aire en las cuatro pantallas; capturas light/dark Mac 14"/iPad 11" con una rúbrica real (6+ criterios, clase de 30 alumnos).

## Orden, estimación y riesgo

| PR | Alcance | Est. | Riesgo |
|---|---|---|---|
| 1 | Fundación `RubricsStyle` (renombrar + color semántico unificado) | 0,5-1 d | Bajo |
| 2 | Banco/gestión Mac + iPad (split real, tamaños de sheet, quitar inspector) | 1,5-2 d | Medio — colisiona con ramas de auditoría activas, ver "Coordinación" |
| 3 | Builder | 1 d | Bajo |
| 4 | Evaluación individual (cherry-pick scroll fix + ScoreBadge + sticky + Dynamic Type) | 1 d | Bajo |
| 5 | Evaluación masiva (matriz oficial + color + señal de incompleto) | 1-1,5 d | Bajo |
| 6 | AssignRubricToTabView + consistencia | 0,5-1 d | Bajo |

Total ≈ 5,5-7,5 días. Dependencias: 2-6 dependen de 1; 3, 4, 5 y 6 son independientes entre sí y paralelizables en sesiones distintas una vez cerrado 1 (convención del repo). 2 puede empezar en paralelo con 3/4/5 pero solo cerrarse tras resolver la coordinación con las auditorías activas.

## Verificación (todos los PR)

- Compilar ambas plataformas: `./scripts/verify_apple_builds.sh` (hay fallos preexistentes de CI documentados — comparar contra estado previo, memoria `apple-build-ci-chain-2026-07`).
- `xcodegen generate` tras cualquier archivo nuevo o renombrado (lección ya documentada en `docs/audit/INCIDENCIA_2026-07-14-build-roto-post-merge.md` y repetida en el PR 1 del plan del Cuaderno).
- Capturas light/dark por PR, Mac 14" e iPad 11", con una rúbrica real de 6+ criterios y una clase de 30 alumnos; changelog en `docs/CHANGELOG.md` por PR.
- Antes de PR 2: confirmar el estado real de `fix/auditoria-layout-2026-07`/`fix/auditoria-ui-2026-07` (ver "Coordinación con auditorías activas").
- Rama de cada PR: `feature/redesign-rubricas-<n>` desde `feature/redesign-cuaderno-12` (rebasar a `main` cuando esa rama aterrice).
