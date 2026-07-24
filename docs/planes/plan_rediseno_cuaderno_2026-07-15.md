# Plan: Rediseño visual premium del Cuaderno (macOS 26 + iPadOS)

**Estado: aprobado, en ejecución.**

## Contexto

El usuario quiere que la pantalla de Cuaderno se vea más premium, alineada con las guías de estilo de Apple (HIG macOS Tahoe 26 / iPadOS 26, sistema Liquid Glass), en concreto: grid, cabeceras de columnas, pestañas, sheet de creación de columnas y las vistas de rúbrica que se abren desde el cuaderno. Es un plan **solo visual**: no toca lógica de negocio, ni rendimiento, ni la arquitectura de scroll de 3 paneles (regla de la skill `notebook-grid-performance`: nunca mezclar rendimiento y rediseño en el mismo PR). Complementa y supera la Fase 4 de `docs/plan_cuaderno_premium.md`.

### Investigación HIG aplicable (resumen)

- **Liquid Glass es chrome, no contenido**: navegación, toolbars, tab bars, footers de sheets. Las tablas/listas de datos van sobre fondos sólidos y planos. Coincide con la decisión de producto ya firme en `.agents/skills/liquid-glass-design/SKILL.md`: **glass jamás en el grid**.
- **Jerarquía por espacio y agrupación, no por decoración**: quitar fondos/bordes de barras custom, expresar estructura con layout; agrupar acciones relacionadas.
- **Superficies de datos densas calmadas**: color reservado a estados y semántica; una sola técnica de separación de filas (no zebra + bordes + chips a la vez); dígitos monoespaciados en datos numéricos.
- **Radios concéntricos** (R_int = R_ext − padding) y rejilla de 8 pt (filosofía interna `jobs-design-philosophy`, coincide con HIG).
- **Sheets macOS ≠ sheets iOS**: en Mac, formularios agrupados sin NavigationStack interno; en iPad, detents y drag indicator.

### Diagnóstico visual del estado actual

1. **Grid = "muro de píldoras"**: cada cabecera es un chip flotante (radio 12, fill+borde+sombra+cápsula decorativa 42×3), cada celda apila zebra + borde propio (`softBorder.opacity(0.26)`) + fills por columna. Tres técnicas de separación simultáneas → ruido; falla el Test del Bizqueo.
2. **Tokens impredecibles**: `NotebookStyle.softBorder = primary.opacity(0.04)` es casi invisible, así que los bordes reales son opacidades apiladas (`0.04 × 0.26`…) imposibles de razonar y que desaparecen en dark mode.
3. **Cabeceras sin jerarquía**: título y subtítulo ambos `.caption semibold`; el chip no se conecta visualmente con su columna.
4. **Tabs planas**: cápsulas correctas pero sin la calidad del Planner (que ya tiene `GlassEffectContainer` + morphing con `glassEffectID`); icono repetido en cada pestaña añade ruido.
5. **AddColumnSheet**: `EvaluationBackdrop` decorativo dentro de un formulario funcional, header de 48 pt + título `.title2.bold` + NavigationStack → en macOS se siente app iOS incrustada.
6. **Rúbricas**: `cardRadius = heroCardRadius = 40` en superficie de trabajo densa; backdrop con gradientes y círculo radial compitiendo con la tarea; tipografías locales (`size: 28 black rounded`) fuera de la escala de tokens.
7. **Estados de foco inconsistentes** entre celda seleccionada, columna resaltada y hover de fila.

### Restricciones duras (no negociables)

- Glass solo en chrome; nunca en grid/celdas. Sin tint azul del sistema en selecciones. Todo glass con fallback material digno para iOS < 26 (macOS target es 26.0; iOS es 16.0).
- No tocar `KmpBridge.swift`, `kmp/shared/`, `kmp/data/`, `desktopApp/`.
- **`EvaluationDesign.swift` está en la lista de "no tocar" de los planes de auditoría en curso** (`plan_auditoria_ui_2026-07-15.md`, `plan_auditoria_layout_2026-07-15.md`, ramas `fix/auditoria-*`): los tokens nuevos van a `NotebookStyle`/archivo nuevo, nunca editando ese archivo hasta que esas ramas aterricen.
- 1 PR por ítem, commits atómicos en español (`feat(cuaderno): …`), entrada en `docs/CHANGELOG.md` por PR, no batch-merge de ramas el mismo día.

---

## PR 1 — Fundación: escala de tokens del grid (`NotebookGridStyle`)

**Archivos**: `kmp/iosApp/App/NotebookTopBar.swift` (ampliar `NotebookStyle`) o nuevo `kmp/iosApp/App/NotebookGridStyle.swift`.

Crear una escala **absoluta y predecible** (un solo nivel de opacidad, nada apilado), light/dark verificados:

- `gridLine = Color.primary.opacity(0.07)` — hairline única de filas (sustituye a softBorder×0.45).
- `gridLineStrong = Color.primary.opacity(0.14)` — límites de zonas (borde de columna fija, bajo cabecera, límites de categoría).
- `headerText = .primary` / `headerCaption = .secondary` con fuentes token: `columnTitle = .footnote.weight(.semibold)`, `columnMeta = .caption2` (fuera los `.caption semibold` duplicados).
- `cellFont = .body.monospacedDigit()` (mac `.callout.monospacedDigit()`) — token único para toda celda numérica y la Media.
- Estados (única fuente de verdad, usada por celda/columna/fila):
  - `rowHover = Color.primary.opacity(0.04)` (solo macOS, sin animación — nativo de NSTableView).
  - `cellSelected`: ring `Color.accentColor` 2 pt radio 6 **concéntrico dentro de la celda** + fill `accentColor.opacity(0.08)`.
  - `columnHighlight = tint.opacity(0.05)` (wash plano de columna).
  - `statePending = warningTint`, `stateError = danger` (punto/ring, nunca fills grandes).
- Radios: celda interactiva 6, chip 8, tarjeta 12 — documentar la regla concéntrica en comentario del token.

Sustituir usos en `NotebookModuleGridCells.swift`, `NotebookGridContainer.swift`, `NotebookDataGrid.swift` **sin cambiar aún el diseño** (mapeo 1:1 a los tokens nuevos). Así el PR 2 es solo diseño, no plomería.

**Aceptación**: cero opacidades literales nuevas en los archivos del grid; capturas light/dark idénticas o imperceptiblemente distintas a antes.

## PR 2 — Grid premium: celdas planas y separación única

**Archivos**: `NotebookModuleGridCells.swift` (`notebookColumnCellFill/Border`), `NotebookGridContainer.swift`, `NotebookDataGrid.swift` (fondos de paneles), `NotebookEditableTableCell.swift`.

Decisión recomendada: **patrón macOS nativo = filas alternas sutiles + hairlines horizontales, SIN bordes por celda ni gridlines verticales** (como `Table` de macOS; Numbers usa gridlines porque no tiene zebra — no ambos).

1. Eliminar el borde por celda (`notebookColumnCellBorder` por defecto → `.clear`; solo estados lo pintan).
2. Zebra: filas pares `NotebookGridStyle.zebra = primary.opacity(0.025)` plano (hoy `surfaceSoft.opacity(0.18)` = opacidad apilada); separador de fila hairline `gridLine` a ancho completo (quitar el `padding(.horizontal, 16)` que corta la línea y desalinea con la columna fija).
3. Tinte de columna con color propio: mantener wash `tint.opacity(0.035)` **solo si la columna tiene color custom**, como hoy, pero sin borde.
4. Columna fija (alumnos): fondo sólido `secondarySystemBackground` (quitar la mezcla .thinMaterial+opacity en macOS: el material bajo cientos de celdas no aporta y vibra al hacer scroll); borde derecho `gridLineStrong` de 1 pt en vez del gradiente actual; sombra solo cuando hay contenido desplazado debajo (scroll offset > 0), estilo `scrollEdgeEffect`.
5. Columna Media (derecha): debe leerse como **resumen destacado**: fondo `secondarySystemBackground`, borde izquierdo `gridLineStrong`, valor en `cellFont` semibold + tinte semántico solo en el texto (aprobado/suspenso), nunca fills.
6. `NotebookEditableTableCell`: `.textFieldStyle(.plain)` (fuera `RoundedBorderTextFieldStyle`, la caja-en-caja); estado edición = mismo ring que selección + fondo `background` elevado; feedback guardado como punto de 6 pt en esquina (ámbar→verde con `symbolEffect(.bounce)` una vez), sin badges.
7. Estados unificados: hover de fila (flat, sin animación) < wash de columna < selección de celda (ring). Solo la selección usa accent.

**Aceptación**: Test del Bizqueo — al entrecerrar los ojos solo destacan los datos y la celda seleccionada; capturas antes/después light/dark en Mac 14" e iPad 11"; la línea de fila conecta visualmente los 3 paneles sin cortes.

## PR 3 — Cabeceras de columna y folder lane

**Archivos**: `NotebookModuleGridCells.swift` (headerChip, líneas 5-71), `NotebookModuleView.swift` (headerRow ~607, folder lane).

1. Sustituir el chip flotante por **cabecera plana integrada**: sin fill, sin sombra, sin cápsula superior. La identidad de columna pasa a una **barra inferior de 3 pt del ancho completo de la columna** pegada al borde inferior de la cabecera (conecta cabecera↔columna, patrón pestaña/regla).
   - Sin color custom: barra `gridLineStrong`; con color: barra `tint` (opacidad 0.9).
2. Jerarquía tipográfica: título `columnTitle` (.footnote semibold, primary), metadatos (peso/fecha/tipo) `columnMeta` (.caption2, secondary) en una sola línea con separador "·". Columnas de sistema: título .secondary regular.
3. Columna resaltada (menú abierto/inspector): wash `columnHighlight` que cubre cabecera + celdas (mismo token que PR 2), no borde grueso.
4. Fila de cabecera: mantener `.thinMaterial` (es chrome legítimo) + hairline inferior `gridLineStrong`; altura fija 56 → verificar alineación a rejilla 8 pt.
5. Folder lane (34 pt): chips de categoría a cápsulas de texto `.caption2 semibold` con tinte de categoría solo en un punto de 6 pt + texto, fondo `primary.opacity(0.03)`; chevron con rotación animada 0.2 s (ya previsto en plan previo, sin animar el grid).

**Aceptación**: la cabecera no compite con los datos; se identifica el color de columna a un vistazo; capturas con 12+ columnas de tipos mezclados.

## PR 4 — Tab strip con Liquid Glass y morphing

**Archivos**: `NotebookTabStrip.swift`; patrones de referencia: `App/PlannerFloatingTabBar.swift`, `AppleShared/PlannerLiquidGlassControls.swift`, `MacApp/MacLiquidGlassStyle.swift`.

1. Agrupar las pestañas en un `GlassEffectContainer` (rama macOS 26 / iOS 26) con la **selección como capa glass translúcida** que hace morphing entre pestañas vía `glassEffectID` estable (el `tab.id`, nunca índices). Fallback iOS < 26: cápsula `.ultraThinMaterial` con la misma geometría animada con `matchedGeometryEffect`.
2. Sin azul de sistema: pestaña activa con tint neutro (`.primary`) y peso tipográfico, no color de acento (regla corregida dos veces en el proyecto; no reintroducir).
3. Quitar el icono `rectangle.on.rectangle` de cada pestaña (ruido); dejar solo texto `.footnote semibold`; el estado activo lo dan el glass + el peso.
4. Fondo de la barra: quitar el `.ultraThinMaterial` a ancho completo; la barra flota sobre el fondo del módulo con el container glass solo alrededor de las pestañas (HIG: expresar agrupación por layout, no por franjas).
5. macOS: estado hover por pestaña (`primary.opacity(0.05)`); botón "+" alineado al mismo idioma (glass circle / material en fallback). Empty state: mantener el CTA pero con `.buttonStyle(.glass)` en 26.
6. Padding vertical 8, alturas múltiplo de 8.

**Aceptación**: cambiar de pestaña produce morphing fluido en Mac; en un iPad con iOS 16 el fallback es digno y equivalente; sin tint azul; compilan ambas plataformas (`./scripts/verify_apple_builds.sh`).

## PR 5 — AddColumnSheet nativo premium

**Archivos**: `AddColumnSheet.swift` (body 468-540, sheetHeader 542-574, blueprintSection, footerActions), presentación en `NotebookModuleView.swift` (~1704).

1. **Quitar `EvaluationBackdrop`** del formulario: fondo `windowBackground`/`systemGroupedBackground` plano.
2. **macOS**: eliminar el `NavigationStack` interno; estructura de sheet Mac: título `.headline` + subtítulo `.caption` compactos arriba (sin icono 48 pt), contenido, footer con Cancelar/Crear alineados a la derecha (Crear = `.borderedProminent` / `.glassProminent` en 26). Mantener frame 520-640×560.
3. **iPad**: conservar NavigationStack + `presentationDetents([.large])`, pero header compacto vía `IOSSheetHeader` existente; mostrar drag indicator.
4. **Blueprint cards** (elección de tipo): grid 2-4 por fila, tarjetas radio 12 con icono en tinte semántico sobre `tint.opacity(0.12)` radio 8 (concéntrico: 12 − 4), título `.callout semibold`, subtítulo `.caption2`; seleccionada = ring accent 2 pt + fill `accentColor.opacity(0.06)` (mismo idioma de selección que las celdas del grid, PR 1). Separar "Básicos" / "Avanzados" con `NotebookSectionLabel` existente, no con Divider.
5. Footer: `.ultraThinMaterial` → en 26 glass; una sola acción prominente (Crear); el resto plano.
6. Auditar espaciados a rejilla 8 (hoy hay 20/16 mezclados: footer `.padding(.horizontal, 20).padding(.vertical, 16)` → 16/16 o 24/16).
7. Aplicar el mismo tratamiento (header compacto, sin backdrop, footer) a los sheets hermanos con mínimo esfuerzo: `NotebookColumnOrganizerSheet`, `NotebookFormulaEditorSheet`, `NotebookAverageEditorSheet` — solo si es sustituir componentes compartidos; si no, dejarlos para un PR posterior.

**Aceptación**: en macOS el sheet pasa por nativo (comparar con sheet de Numbers/Calendario); en iPad conserva detents; foco visual único en la elección de tipo → nombre → Crear.

## PR 6 — Rúbricas desde el cuaderno

**Archivos**: `RubricEvaluationView.swift`, `RubricBulkEvaluationSheet.swift`. **No editar `EvaluationDesign.swift`** (bloqueado por auditorías en curso): definir overrides locales `RubricEvaluationStyle` en archivo del cuaderno y migrar a tokens compartidos cuando aterricen las ramas `fix/auditoria-*`.

1. Radios: tarjetas de trabajo 40 → 16 (criterios, resumen); solo el contenedor raíz del fullScreenCover puede permitirse 20+.
2. Backdrop: sustituir `EvaluationBackdrop` (gradiente+círculo radial) por fondo plano `systemGroupedBackground` con, como máximo, un tinte del 3 % arriba. La rúbrica es tarea de concentración.
3. Header: bajar `size: 28 black rounded` a `.title2.weight(.semibold)`; el ScoreBadge como único elemento destacado (Bizqueo: la nota es el foco).
4. `EvaluationLevelTile`: estados nítidos — reposo: fondo `secondarySystemBackground` radio 10, sin borde; hover (mac): `primary.opacity(0.04)`; seleccionado: ring 2 pt en tinte semántico del nivel + fill `tint.opacity(0.08)` + checkmark `symbolEffect(.bounce)`; mismo idioma de selección que grid y blueprint cards.
5. Panel resumen (300 pt): fijarlo visualmente como tarjeta pinned (en layout ancho, `sticky` visual con su propio scroll si hace falta), botón Guardar prominente único abajo.
6. `RubricBulkEvaluationSheet`: heredar exactamente los mismos componentes/estados; navegación entre alumnos con control segmentado o stepper del sistema, no botones custom.

**Aceptación**: capturas light/dark; con 6 criterios × 4 niveles la pantalla se lee sin fatiga; puntuar 5 alumnos seguidos en bulk resulta obvio sin leer textos.

## PR 7 — Pasada de consistencia y QA visual

1. Auditoría cruzada: mismo idioma de selección (ring accent 2 pt), hover (`primary.opacity(0.04-0.05)`), hairlines y radios en grid, tabs, sheets y rúbricas.
2. Sesión de capturas comparativas antes/después: Mac 14" y iPad 11", light y dark, con clase real (35 alumnos, 25+ columnas). Test del Aire y del Bizqueo documentados en el PR.
3. Verificar Dynamic Type básico (AX1-AX2) en cabeceras y celdas: `minimumScaleFactor` ya existente, comprobar que los tokens nuevos no lo rompen.

### Resultado de la ejecución (2026-07-15)

Este entorno solo tiene Xcode Command Line Tools (sin `Xcode.app`), igual que en la ejecución previa documentada en `docs/plan_cuaderno_premium.md` Fase 0: no se puede lanzar el simulador, hacer capturas reales ni medir Dynamic Type end-to-end aquí. Lo ejecutado en su lugar:

1. **Auditoría cruzada completada**: se encontró y corrigió un chip suelto que PR3 no cubrió — la cabecera especial de la columna "Nombre" (con el menú de agrupación embebido, en `NotebookModuleGridCells.swift`, rama `if fixed == .name`) seguía teniendo su propia caja (fill/borde/sombra, radio 12) porque no pasa por la función compartida `headerChip(title:subtitle:...)`. Se aplanó con el mismo idioma (tipografía `columnTitle`/`columnMeta`, sin fill/sombra/borde). Confirmado por grep que no quedan `RoundedBorderTextFieldStyle` en `NotebookEditableTableCell.swift`, ni chips con sombra `Color.black.opacity(0.03)` en los archivos del grid, ni usos de `EvaluationBackdrop` en las vistas de rúbrica (las coincidencias de grep eran falsos positivos de `RubricEvaluationBackdrop`, el nuevo componente).
2. **Verificación de sintaxis**: `swiftc -parse` sobre los 12 archivos Swift tocados en el plan — todos limpios.
3. **Registro en Xcode**: `xcodegen generate` para dar de alta `NotebookGridStyle.swift` y `RubricEvaluationStyle.swift` en el proyecto (`project.yml` usa `path:` por carpeta, así que XcodeGen los recoge solos; sin este paso no compilarían en ninguna build, el mismo bug documentado en `docs/audit/INCIDENCIA_2026-07-14-build-roto-post-merge.md`).
4. **Pendiente para el dev**: `./scripts/verify_apple_builds.sh` (requiere Xcode.app completo) y la sesión real de capturas antes/después en Mac e iPad, light/dark, con una clase de 35 alumnos y 25+ columnas — no se puede sustituir por una revisión estática del código.

---

## Orden, estimación y riesgo

| PR | Alcance | Est. | Riesgo |
|---|---|---|---|
| 1 | Tokens NotebookGridStyle (plomería) | 0,5-1 d | Bajo |
| 2 | Grid plano (celdas/zebra/paneles) | 1-1,5 d | Medio (visual, no estructural) |
| 3 | Cabeceras + folder lane | 1 d | Bajo |
| 4 | Tab strip glass + morphing | 1 d | Bajo |
| 5 | AddColumnSheet | 1-1,5 d | Bajo |
| 6 | Rúbricas | 1-1,5 d | Bajo |
| 7 | Consistencia + QA | 0,5 d | Nulo |

Dependencias: 2 y 3 dependen de 1; 4-6 son independientes entre sí (paralelizables en sesiones distintas, convención del repo). Total ≈ 6-8 días.

## Verificación (todos los PRs)

- Compilar ambas plataformas: `./scripts/verify_apple_builds.sh` (hay fallos preexistentes de CI documentados — comparar contra estado previo, memoria `apple-build-ci-chain-2026-07`).
- Checklist manual `NotebookManualVerification.md` (puntos de alineación de los 3 paneles) tras PR 2 y 3: el rediseño no debe desalinear cabecera/filas/Media.
- Capturas light/dark por PR adjuntas a la descripción del PR; changelog en `docs/CHANGELOG.md` por PR.
- Ramas: `feature/redesign-cuaderno-<n>` desde `main`; coordinar con `fix/auditoria-ui-2026-07` y `fix/auditoria-layout-2026-07` (evitar tocar en paralelo `MacRootView.swift` y `EvaluationDesign.swift`).
