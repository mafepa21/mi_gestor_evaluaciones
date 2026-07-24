# Plan: Rediseño desde cero de la evaluación de rúbricas (individual y masiva)

**Estado: dirección de diseño aprobada por el usuario tras revisar un mockup interactivo; plan de PR para revisión. Ningún PR de este plan está implementado todavía.**

## Contexto

Con los 6 PR de `docs/planes/plan_rediseno_rubricas_2026-07-20.md` ya mergeados en `feature/redesign-cuaderno-12` (unificación de tokens en todo el módulo Rúbricas), el usuario pidió ir más allá para las dos pantallas de evaluación: no un ajuste más, sino un rediseño **completo, desde cero**, "estilo Apple, muy minimalista, sin información superflua, con diseño premium".

El punto de partida fue una captura real de la evaluación individual actual (`RubricEvaluationView`) que expone cuatro redundancias concretas, no defectos de implementación sino de qué se decide mostrar:

1. **La nota aparece dos veces a la vez**: el badge "Nota actual" de la cabecera y el número del panel Resumen — mismo dato, mismo momento.
2. **La descripción del nivel elegido se repite hasta tres veces**: subtítulo de la tarjeta, popover al pasar el ratón, y una cita aparte debajo.
3. **Dos píldoras fijas explican lo obvio** ("1 criterios", "Selecciona el nivel") — la propia tarjeta ya lo muestra.
4. **"Siguiente paso" no sabe si ya se dio el paso**: texto estático que no cambia aunque la rúbrica esté completa.

Se propuso una dirección visual con cuatro reglas y se validó con un mockup interactivo (individual + masiva, misma rúbrica que la captura) antes de escribir una sola línea de Swift:

1. **Un dato, un sitio** — si ya se dijo, no se repite.
2. **El color es el único adorno** — nada de cajas/rellenos/sombras para destacar; el color de banda (ya unificado en el plan anterior) es la única señal con significado.
3. **El detalle se pide, no se impone** — progressive disclosure, no todo a la vez.
4. **Nada explica lo que ya se ve** — sin píldoras ni textos instructivos que no reflejan el estado real.

El usuario aprobó esa dirección. Este documento es el plan de PR para ejecutarla.

## Diferencia con el plan anterior

El plan de `plan_rediseno_rubricas_2026-07-20.md` (PR 1-6, ya mergeado) fue una **unificación de lo existente**: mismos componentes, mismos huecos de layout, tokens compartidos. Este plan es una **reescritura de la información y la interacción** de dos pantallas concretas — se espera borrar código (paneles, chips, tarjetas anidadas) tanto como añadirlo. Reutiliza la base de `RubricsStyle` (color de banda, radios, hairlines) en vez de rehacerla.

## Alcance

- `kmp/iosApp/App/RubricEvaluationView.swift` (evaluación individual).
- `kmp/iosApp/App/RubricBulkEvaluationSheet.swift` (evaluación masiva).
- `kmp/iosApp/App/RubricsStyle.swift` (tokens y componentes nuevos/retirados).
- No toca el banco/listado, el builder ni `AssignRubricToTabView` (ya rediseñados en el plan anterior, fuera de alcance aquí).
- No toca modelo de datos, `RubricEvaluationViewModel`/`RubricBulkEvaluationViewModel`/`RubricEvaluationBus`, ni la lógica de autoguardado — solo la capa visual e interactiva que la consume.

## Restricciones duras

- **No tocar `EvaluationDesign.swift`**: sigue bloqueado por `fix/auditoria-ui-2026-07` (verificado de nuevo hoy — 10 commits desde `main`, sin mergear, sin tocar `MacRootView.swift` ni nada de Rúbricas). Overrides locales en `RubricsStyle.swift`, como ya se hizo.
- No tocar `KmpBridge.swift`, `kmp/shared/`, `kmp/data/`.
- **Componentes que este plan retira intencionadamente** (no son bugs, son la pieza que sustituyen): `RubricScoreBadge` y `RubricLevelTile` (ambos introducidos en el PR 4 del plan anterior, hace unos commits) quedan obsoletos frente al anillo de progreso y la nueva píldora de nivel. Retirarlos por completo al final de la fase que los sustituye, no dejarlos como código muerto.
- Rama base: `feature/redesign-cuaderno-12` (ya con los 6 PR anteriores mergeados). Cadena sugerida: `feature/redesign-rubricas-eval-<n>`.
- 1 PR por ítem, commits atómicos en español, entrada en `docs/CHANGELOG.md` por PR.
- **Riesgo más alto que el plan anterior**: aquí sí cambia comportamiento e interacción (no solo tokens/geometría) — cada PR necesita, más que nunca, verificación visual real en Xcode antes de mergear; este entorno de ejecución no tiene Xcode.app completo y solo puede verificar sintaxis (`swiftc -parse`).

## PR 1 — Fundación: utilidad de color compartida y limpieza de tokens obsoletos

**Archivos**: `RubricsStyle.swift`, `RubricBulkEvaluationSheet.swift`.

1. Extraer `levelColor(for:in:)` (hoy privada y duplicada en espíritu entre bulk y lo que necesitará individual) a `RubricsStyle.levelColor(points:maxPoints:) -> Color` — misma lógica de 4 bandas por ratio, un solo sitio. `RubricBulkEvaluationSheet` pasa a llamar a la versión compartida.
2. Documentar en el propio código que `RubricScoreBadge` y `RubricLevelTile` quedan pendientes de retirada (PR 3 y PR 4 los sustituyen); no se borran todavía porque `RubricEvaluationView` los sigue usando hasta esos PR.
3. Ningún cambio visual en este PR.

**Aceptación**: `swiftc -parse` limpio; `RubricBulkEvaluationSheet` compila con la función movida; cero lógica de color duplicada entre archivos.

## PR 2 — Individual: anillo de progreso, fuera cabecera vieja

**Archivos**: `RubricEvaluationView.swift`, `RubricsStyle.swift`.

1. Nuevo `RubricScoreRing` en `RubricsStyle.swift`: anillo circular compacto (probar primero `Gauge(...).gaugeStyle(.accessoryCircularCapacity)`, nativo desde iOS 16/macOS 13 y pensado exactamente para esto; si en la práctica no se comporta bien fuera de contexto de widget en alguna plataforma, alternativa de reserva con `Circle().trim(from:to:)` rotado -90°). Arco = criterios resueltos / total; número central = nota actual, coloreado con `RubricsStyle.gradeColor`.
2. Sustituye a `RubricScoreBadge` en la cabecera. Cabecera se reduce a: botón de cierre (icono solo, sin círculo de fondo), nombre del alumno grande, nombre de la rúbrica pequeño y secundario, el anillo a la derecha.
3. Elimina los chips `EvaluationChip` "N criterios" / "Selecciona el nivel" de `criteriaPanel`.
4. Elimina el bloque de `ProgressView` + "Progreso" + "N de M criterios resueltos" de `summaryPanel` — el arco del anillo ya es la señal de progreso; no se necesita una segunda.

**Aceptación**: cabecera con un único elemento de nota (el anillo); sin chips instructivos; capturas light/dark pendientes de QA real.

## PR 3 — Individual: lista plana de criterios y píldora de nivel

**Archivos**: `RubricEvaluationView.swift`, `RubricsStyle.swift`.

1. `criteriaPanel` deja de envolver en `PremiumCard.glass`: pasa a una lista plana (`VStack`) con hairline (`RubricsStyle.hairline`) entre criterios, sin tarjeta contenedora.
2. `RubricCriterionRow` pierde su propio `PremiumCard.glass(cornerRadius: rowRadius)`: cada fila es texto + píldoras, sin caja.
3. Nuevo `RubricLevelPill` en `RubricsStyle.swift`, sustituye a `RubricLevelTile`: cápsula compacta con el nombre del nivel + puntos en subíndice pequeño; seleccionada = fill con `RubricsStyle.levelColor` (del PR 1); resto = solo borde. Sin subtítulo de descripción permanente.
4. La descripción del nivel deja de mostrarse siempre debajo: se reutiliza `RubricLevelDescriptionPopover` (ya existe, hoy solo en `RubricBulkEvaluationSheet`) activado por `.help()` en macOS; en iOS/iPadOS (sin hover) se activa con un icono "ⓘ" pequeño dentro de la píldora seleccionada, tocable, o con pulsación larga — decidir cuál en la propia implementación probando ambos con contenido real.
5. Retirar `RubricLevelTile` de `RubricsStyle.swift` (ya sin usos tras este PR).

**Aceptación**: ningún criterio muestra descripción más de una vez a la vez; Test del Bizqueo con 6 criterios × 4 niveles sin fatiga visual; `RubricLevelTile` ya no existe en el código.

## PR 4 — Individual: columna única, sin panel lateral

**Archivos**: `RubricEvaluationView.swift`, `RubricsStyle.swift`.

1. Elimina `summaryPanel` por completo y la rama `isWide` (`HStack` con columna fija de 300pt) introducida en el PR 4 del plan anterior — con la nota ya en el anillo (PR 2) y sin bloque de progreso (también PR 2), no queda contenido propio para un panel separado.
2. `body` pasa a una sola columna centrada con `maxWidth` cómodo (probar 640pt) sobre cualquier ancho de ventana — en vez de decidir entre dos layouts según `proxy.size.width >= 720`, un único layout que no necesita ramificarse.
3. El pie pasa a ser la única superficie de "estado": la etiqueta del botón cambia según haya criterios pendientes ("Guardar · 3 de 4 criterios") o la rúbrica esté completa ("Guardar · 9,3", con el número en `RubricsStyle.gradeColor`).
4. Retirar `RubricScoreBadge` de `RubricsStyle.swift` (ya sin usos: sustituido por el anillo en PR 2).

**Aceptación**: `RubricEvaluationView.body` sin ramificación por ancho; ni `RubricScoreBadge` ni `RubricLevelTile` existen ya en el código; capturas Mac 14"/iPad 11" pendientes de QA real.

## PR 5 — Masiva: fila de alumno silenciosa

**Archivos**: `RubricBulkEvaluationSheet.swift`.

1. Sustituye el texto "N pendientes" / "Disponible" / "Lesionado" (en `studentRow` y en `compactEvaluationByCriterion`, portado en el plan anterior a ambos) por un único punto de estado junto al avatar: gris = pendiente, verde = completo, rojo = lesionado. Mismo dato (`cache.pendingCriteriaCount`, `isStudentInjured`), forma más silenciosa.
2. `scorePill` pierde el fondo relleno (`.opacity(0.12)` + `RoundedRectangle`): pasa a texto plano coloreado por `RubricsStyle.gradeColor`, más grande, sin caja.
3. Los tres botones de acción por fila (lesión/copiar/pegar) se colapsan en un único menú "···" (macOS: visible solo en hover de fila, reutilizando el patrón `.onHover` ya existente en el archivo; iOS/iPadOS: visible siempre pero mínimo, sin hover disponible).

**Aceptación**: cada fila muestra un único punto de estado, no tres frases posibles; la nota se lee sin caja; máximo un icono de acción visible por fila en reposo.

## PR 6 — Masiva: celda de criterio silenciosa

**Archivos**: `RubricBulkEvaluationSheet.swift`.

1. Sustituye `inlineCriterionCell` (hoy una fila de hasta 4 botones-píldora con check + relleno + borde, todos visibles a la vez) por un `Picker` de estilo `.segmented`, mostrando los niveles abreviados; el segmento activo se tiñe con `RubricsStyle.levelColor` (del PR 1) en vez del azul de sistema por defecto (`.tint(...)`).
   - **Decisión a validar con contenido real**: si los nombres de nivel no caben legibles en un segmento a la anchura de columna actual (~220pt / 4 niveles ≈ 55pt cada uno), alternativa de reserva: mostrar solo el nivel elegido como texto de color (igual que `scorePill` en PR 5) y abrir un `Menu`/popover con las opciones al tocar la celda. Probar el `Picker` primero — preserva la velocidad de "un clic, ya está" que la evaluación masiva necesita; el menú es más silencioso pero añade un toque.
2. Aplicar el mismo tratamiento a las dos superficies que ya comparten esta celda (matriz ancha y `compactEvaluationByCriterion`).

**Aceptación**: puntuar 5 alumnos seguidos sigue siendo obvio sin leer texto (mismo criterio que el plan anterior); ninguna celda muestra más de un color de relleno a la vez.

## PR 7 — Masiva: autoguardado ambiental y consistencia final

**Archivos**: `RubricBulkEvaluationSheet.swift`, auditoría cruzada de PR 2-6.

1. La evaluación masiva ya autoguarda cada celda (debounce 400ms, confirmado en el código). Sustituir el botón visible "Guardar rúbrica masiva" por un indicador ambiental mínimo ("Guardado" / "Guardando…", punto + texto pequeño, mismo lenguaje que ya se usaba). Mantener `⌘S` como atajo de teclado (sin botón que lo represente) para quien lo busque por costumbre.
2. Auditoría cruzada PR 2-6: mismo `RubricsStyle.levelColor`/`gradeColor` en las dos pantallas, ninguna caja/relleno decorativo que no sea semántico, ninguna descripción mostrada dos veces a la vez.

**Aceptación**: Test del Bizqueo y del Aire en ambas pantallas; ninguna acción de guardado explícita visible en la evaluación masiva salvo el atajo de teclado; capturas light/dark Mac 14"/iPad 11" con una rúbrica real (6+ criterios, clase de 30 alumnos) — pendiente de entorno con Xcode.app completo.

## Orden, estimación y riesgo

| PR | Alcance | Est. | Riesgo |
|---|---|---|---|
| 1 | Fundación: `levelColor` compartido | 0,5 d | Bajo |
| 2 | Individual: anillo, fuera cabecera vieja | 1 d | Medio (componente nuevo, `Gauge` a verificar) |
| 3 | Individual: lista plana + píldora de nivel | 1,5 d | Medio (retira 2 componentes, cambia popover a `.help()`/táctil) |
| 4 | Individual: columna única | 1 d | Medio (retira una rama de layout entera) |
| 5 | Masiva: fila silenciosa | 1 d | Bajo |
| 6 | Masiva: celda silenciosa | 1,5 d | **Alto** — cambia el control de interacción principal de la pantalla de uso más intensivo del módulo |
| 7 | Masiva: autoguardado ambiental + consistencia | 0,5-1 d | Medio (quita una acción explícita; confirmar que el autoguardado es percibido como fiable) |

Total ≈ 7-8 días. Dependencias: 2-4 son secuenciales entre sí (todas sobre `RubricEvaluationView`); 5-7 son secuenciales entre sí (todas sobre `RubricBulkEvaluationSheet`); el bloque individual (2-4) y el bloque masivo (5-7) son independientes y paralelizables en sesiones distintas una vez cerrado el PR 1.

## Verificación (todos los PR)

- `swiftc -parse` en los archivos tocados, como en el plan anterior — no sustituye una build real.
- **Más que en ningún plan anterior de este módulo, cada PR necesita compilación y QA visual real en Xcode antes de mergear** (`./scripts/verify_apple_builds.sh` + revisión manual): PR 3, 4 y 6 cambian interacción, no solo geometría o color, y no se pueden validar leyendo código.
- Capturas light/dark por PR, Mac 14" e iPad 11", con una rúbrica real de 6+ criterios y una clase de 30 alumnos.
- Changelog en `docs/CHANGELOG.md` por PR.
- Antes de mergear la cadena a `main`: confirmar que `fix/auditoria-ui-2026-07` sigue sin tocar `EvaluationDesign.swift`/Rúbricas (mismo chequeo que en el plan anterior).
