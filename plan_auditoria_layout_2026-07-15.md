# Plan de corrección — Auditoría de LAYOUT de las pantallas macOS (2026-07-15)

Auditoría estática de maquetación de la app macOS (`kmp/iosApp/MacApp` + hojas compartidas de `kmp/iosApp/App`), motivada por la captura del módulo Alumnado con las columnas e información descuadradas (panel de filtros recortado por la izquierda, ficha del alumno recortada por la derecha). Complementa —no sustituye— a `plan_auditoria_ui_2026-07-15.md`, que cubre bugs de estado/ciclo de vida. Este plan cubre exclusivamente defectos **visuales/geométricos**: contenido que desborda y se recorta, columnas desalineadas, hojas que no caben en pantalla y código de layout muerto.

## Diagnóstico raíz de la captura

La ventana principal permite un mínimo de **900×600** (`MiGestorKMPMacApp.swift:24`), pero ningún módulo con paneles laterales cabe en ese ancho:

```
sidebar NavigationSplitView (~180-220)
+ contenido del módulo (suma de minWidth internos)
+ inspector del shell (320-440, MacRootView.swift:148-152)
```

En Alumnado (presentación `.content`, `MacRootView.swift:413-423`): filtros `minWidth 220` + lista `minWidth 560` (`MacStudentsView.swift:118-120`) + paddings + sidebar + inspector ≈ **1.300+ pt necesarios frente a 900 disponibles**. `HSplitView`/`HStack` no degradan: el contenido desborda centrado y se **recorta por ambos lados**, que es exactamente lo que muestra la captura ("os"→Filtros, "ueda"→Búsqueda, "miento"→Seguimiento cortados a la izquierda; "Sin g…", "Radar de riesg…" cortados a la derecha).

El mismo contrato roto se repite en Informes, Sync, Condición física y en las ventanas auxiliares. Además hay un descuadre real de columnas en el histórico de Asistencia y varias hojas modales con mínimos mayores que las pantallas de portátil.

## Pantallas auditadas

`MacRootView` (shell), `MacStudentsView`, `MacAttendanceView` (+`MacAttendanceDayRow`), `MacReportsView` (en `MacModuleStubs.swift`), `MacSyncView`, `MacPhysicalTestsView`, `MacRubricsView`, `MacDashboardView`, `MacPlannerView`/`PlannerMacLayout`, `MacBackupsView`, `MacSettingsView`, `NotebookMacLayout`/`NotebookDataGrid`, ventanas auxiliares y hojas modales de `MiGestorKMPMacApp.swift`.

**Descartes verificados (no son bugs):**
- Las "filas vacías" grises bajo los 2 registros de la captura son las franjas alternas nativas de `Table(.inset(alternatesRowBackgrounds: true))` rellenando el alto mínimo del contenedor; comportamiento estándar de macOS.
- `NotebookDataGrid` comparte las mismas variables de ancho entre cabecera y filas (columnas redimensionables con estado común): sin descuadre estructural.
- El breakpoint del Dashboard (`isWide = width >= 1040`, columna fija 380, `MacDashboardView.swift:46-150`) degrada correctamente a columna única.
- Ventana Backups: mínimo 820 vs contenido 520+300 (`MiGestorKMPMacApp.swift:89,158-164`): justo pero suficiente.

## Reglas de trabajo para el agente

- Rama `fix/auditoria-layout-2026-07` desde `main`.
- **Un commit atómico por ítem**, formato `fix(<ámbito>): <descripción>` en español. Changelog en `docs/CHANGELOG.md` por cada fix.
- Verificación tras cada cambio: compilar `xcodebuild -project kmp/iosApp/MiGestorKMPiOS.xcodeproj -scheme MiGestorKMPMac build` (hay fallos preexistentes de CI ajenos; compara contra el estado previo).
- No tocar `KmpBridge.swift`, `kmp/shared/`, `kmp/data/`, `EvaluationDesign.swift` ni `desktopApp/` (regla de oro de `AGENTS.md`).
- Cambios quirúrgicos: ajustar geometría, no refactorizar lógica. Coordinar con `plan_auditoria_ui_2026-07-15.md` (ver dependencia en L-2).

## Contrato de layout objetivo (aplica a todos los ítems ALTA)

Regla única y verificable que debe cumplir cada módulo tras el plan:

1. **Con la ventana al mínimo (900 pt) y el sidebar visible**, el contenido del módulo SIN inspector debe caber sin recortes → presupuesto de detalle ≈ **680 pt**.
2. **El inspector (del shell o interno) solo se muestra si el detalle dispone de ≥ 1.000 pt**; por debajo se auto-oculta (conservando la preferencia del usuario para cuando vuelva a haber sitio).
3. Prohibido introducir `minWidth` duros nuevos en paneles laterales: usar `idealWidth` + `maxWidth` y dejar que `Table`/`ScrollView` compriman.

Implementación sugerida del punto 2 (una sola vez, en el shell): en `MacRootView.detailPane`, medir el ancho disponible con `onGeometryChange(for: CGFloat.self)` y derivar el binding del `.inspector` como `usuarioQuiereInspector && anchoDetalle >= 1000`, sin machacar `storedInspectorVisible`.

---

## Prioridad ALTA

### L-1 — Alumnado (la captura): suma de mínimos imposible + doble vía de inspector

**Archivos:** `kmp/iosApp/MacApp/MacStudentsView.swift:101-125`, `kmp/iosApp/MacApp/MacRootView.swift:148-152, 413-423, 497-507`.

**Problema:**
1. Presentación `.content` real: filtros `minWidth 220, max 300` + lista `minWidth 560` + `pagePadding`, y encima el shell añade su inspector `.inspector` (320-440) con `MacStudentsView(presentation: .inspector)` (min 330-430). Total ≈ 1.300 pt vs ventana de 900 → recorte por ambos lados.
2. La presentación `.full` (HSplitView con inspector interno de 320-420, mínimos 220+640+320=1.180) **no se usa desde ningún sitio** (solo `.content` y `.inspector` en `MacRootView:414/498`). Con ella mueren: el botón "Ocultar ficha / Mostrar ficha" del header (`MacStudentsView.swift:426-433`, condicionado a `presentation == .full`) y `store.isInspectorPresented`, que queda como segunda fuente de verdad desincronizada del `isInspectorVisible` del shell.

**Fix:**
1. Filtros: `frame(minWidth: 200, idealWidth: 240, maxWidth: 280)`. Lista: bajar a `frame(minWidth: 360)` — `Table` comprime columnas y el ancho útil lo gobiernan los `width(min:ideal:)` ya declarados por columna.
2. Aplicar el contrato de auto-ocultado del inspector (ver arriba) para que a 900 pt se muestre filtros+lista completos y la ficha aparezca solo con ventana ancha.
3. Eliminar la presentación `.full`, su rama del `switch` del `body`, el botón "Ocultar ficha" y `store.isInspectorPresented` (o, si se decide conservar `.full` para una ventana futura, dejar constancia en comentario de por qué y ocultar el botón igualmente; eliminar es lo coherente).

**Criterio de aceptación:** con la ventana a 900×600 y el sidebar visible, en Alumnado no hay ni un texto recortado; agrandar la ventana por encima del umbral hace aparecer la ficha; no queda ningún camino de código con dos inspectores simultáneos.

---

### L-2 — Informes: tres paneles fijos que suman 1.120 pt (+ inspector placeholder)

**Archivos:** `kmp/iosApp/MacApp/MacModuleStubs.swift:122-136` (`MacReportsView.body`), `MiGestorKMPMacApp.swift:76-83` (ventana "Informes" con mínimo 900×620), `MacRootView.swift:532-534`.

**Problema:** `HStack` **no ajustable** con `reportsSidebar` min 280 + `reportsCenter` min 560 + `reportsExportPanel` min 280 = 1.120 pt. Se recorta tanto dentro del shell (donde además recibe el inspector placeholder genérico de 320-440) como en la ventana auxiliar "Informes", cuyo mínimo es 900.

**Fix:**
1. Convertir el `HStack` en `HSplitView` y rebajar mínimos: sidebar `minWidth 240, max 320`; centro `minWidth 380`; panel de exportación `minWidth 260, max 340` y **colapsable** (botón en el header que lo oculte, persistido con `@SceneStorage`), de modo que el caso base quepa en 680 pt.
2. Subir el mínimo de la ventana auxiliar "Informes" a la suma real de sus mínimos (o dejarlo en 900 una vez el contenido quepa en 900).
3. Dependencia: excluir Informes del inspector genérico del shell es el ítem **UI-13** de `plan_auditoria_ui_2026-07-15.md`; si UI-13 aún no está hecho al ejecutar este plan, hacerlo aquí para este módulo.

**Criterio de aceptación:** Informes sin recortes a 900 pt en ambas superficies (shell y ventana auxiliar); el panel de exportación se puede colapsar y su estado persiste.

---

### L-3 — Sync LAN: mínimos 800 pt en ventana auxiliar de mínimo 780

**Archivos:** `kmp/iosApp/MacApp/MacSyncView.swift:64-92`, `MiGestorKMPMacApp.swift:94-101`.

**Problema:** `HSplitView` con panel izquierdo `minWidth 440` + derecho `minWidth 360` = 800 pt; la ventana auxiliar "Sync LAN" permite 780 → recorte garantizado de 20+ pt al mínimo; dentro del shell (sidebar + inspector placeholder) el desborde es mayor.

**Fix:** rebajar a izquierdo `minWidth 360` / derecho `minWidth 300, maxWidth 420` (ambos ya son `ScrollView`, toleran compresión) y alinear el mínimo de la ventana auxiliar con la suma real. Aplicar UI-13 (sin inspector genérico) a este módulo dentro del shell.

**Criterio de aceptación:** Sync sin recortes con la ventana auxiliar y el shell al mínimo.

---

### L-4 — Asistencia, histórico mensual: columnas desplazadas 20 pt respecto a la cabecera

**Archivo:** `kmp/iosApp/MacApp/MacAttendanceView.swift:523-556, 1191-1219`.

**Problema:** descuadre real de columnas (el síntoma exacto que denuncia el usuario). En `historyContent`, la celda de nombre de cada fila mide `frame(width: 220) + .padding(.horizontal, 10)` = **240 pt**, mientras su cabecera `historyHeaderCell("Alumno", width: 220)` mide **220 pt**. Todas las columnas de día (44 pt) quedan desplazadas 20 pt respecto a sus cabeceras, y el corrimiento se percibe más cuanto más días tiene el mes.

**Fix:** unificar el ancho real: en el botón de nombre, aplicar el padding **dentro** del frame (p. ej. `.padding(.horizontal, 10)` antes de `.frame(width: 220, …)`, o subir la cabecera a 240). Extraer el ancho a una constante privada (`nameColumnWidth`) usada por cabecera y fila para que no vuelva a divergir.

**Criterio de aceptación:** con un mes completo cargado, el borde derecho de la celda de nombre coincide al píxel con el de su cabecera y cada columna de día queda bajo su número.

---

### L-5 — Hojas modales más grandes que las pantallas de portátil

**Archivos y mínimos actuales:**
- `RubricBulkEvaluationSheet` → `minWidth 1320, minHeight 860` (`MacRubricsView.swift:289-291`).
- `RubricsBuilderScreen` → `1200×820` (`MacRubricsView.swift:239-242` y `MacDashboardView.swift:1504-1510`).
- `MacPlannerScheduleSettingsSheet` → `980×760`; `PlannerSessionComposerSheet` → `920×720` (`MacPlannerView.swift:95-113`).
- `QuickEvaluationSheet` → `760×680` (`MacDashboardView.swift:80`).
- `StudentImportSheet` → `720×620` (`MacStudentsView.swift:278-281`).

**Problema:** una hoja modal de 820-860 pt de alto no cabe en un portátil con resolución escalada (1280×800 efectivos, o menos con "texto más grande"): los botones Guardar/Cancelar quedan fuera de pantalla y la hoja desborda la ventana (mínimo 900×600). Los dos casos de rúbricas son los peores.

**Fix:** política única: **ninguna hoja con `minHeight > 600` ni `minWidth > 900`**. Bajar los mínimos a `ideal` (p. ej. `frame(minWidth: 860, idealWidth: 1200, minHeight: 560, idealHeight: 800)`), garantizando que el contenido interno scrollee (envolver en `ScrollView` lo que no lo esté) y que la botonera quede anclada fuera del scroll.

**Criterio de aceptación:** todas las hojas listadas se abren completas, con botonera visible, en una ventana de 900×600.

---

## Prioridad MEDIA

### L-6 — Condición física: panel fijo de 270 pt y pickers con mínimos rígidos

**Archivo:** `kmp/iosApp/MacApp/MacPhysicalTestsView.swift:521-549, 768-771, 797-845`.

**Problema:** en Baremos, `scaleTestsPanel` usa `frame(width: 270)` fijo (no cede nunca) y `scaleContextSelector` alinea dos pickers con `minWidth 260` y `minWidth 320` en un `HStack` → 580 pt solo de pickers. En Asignaciones, el formulario impone `minWidth 360-480`. Con sidebar + inspector propio del módulo, a 900 pt se recorta.

**Fix:** panel de pruebas a `frame(minWidth: 220, idealWidth: 270, maxWidth: 300)`; pickers a `idealWidth` (o `.frame(maxWidth:)`) dejando que trunquen con `lineLimit(1)`; formulario de asignaciones `minWidth 320, ideal 420`. Aplicar el contrato de auto-ocultado al inspector del módulo.

**Criterio de aceptación:** las tres pestañas del módulo sin recortes a 900 pt.

### L-7 — Rúbricas: tabla con mínimo 400 + detalle sin presupuesto

**Archivo:** `kmp/iosApp/MacApp/MacRubricsView.swift:117-124, 314-342`.

**Problema:** `rubricsTable` exige `minWidth 400-560` en un `HStack` no ajustable junto al panel de detalle; con sidebar + inspector placeholder del shell, a 900 pt el detalle queda estrangulado o recortado. Las `TableColumn` internas ya tienen mínimos (120/160/140/160 = 580) que contradicen el `maxWidth 560` del contenedor.

**Fix:** contenedor a `HSplitView`; tabla `minWidth 340, ideal 460`; revisar los mínimos de columnas para que su suma quepa (p. ej. 100/140/120/140). Excluir del inspector genérico (UI-13).

**Criterio de aceptación:** lista + detalle visibles sin recortes a 900 pt.

### L-8 — Contrato de las ventanas auxiliares

**Archivo:** `MiGestorKMPMacApp.swift:76-101`.

**Problema:** los mínimos de las tres ventanas auxiliares no derivan del contenido: Informes 900 < 1.120 requeridos (L-2), Sync 780 < 800 (L-3), Backups 820 = 820 justo.

**Fix:** tras L-2/L-3, dejar documentado en cada `Window` (comentario de una línea) de qué suma sale su mínimo, y añadir 40 pt de holgura sobre la suma de mínimos de sus paneles.

**Criterio de aceptación:** ninguna ventana auxiliar permite un tamaño donde su contenido se recorte.

---

## Prioridad BAJA

### L-9 — Guardarraíl de regresión: checklist de geometría en el repo

Añadir a `docs/` (junto al registro de auditorías) una checklist breve "Geometría macOS" con las tres reglas del contrato (presupuesto 680 pt, inspector ≥ 1.000 pt, `ideal` en vez de `min` duros) y la matriz de QA de abajo, para que cualquier módulo nuevo se valide igual. Referenciarla desde `AGENTS.md` si procede.

### L-10 — Barrido final de `frame(width:)` fijos en paneles

Con L-1…L-7 hechos, repasar el resto de `frame(width:)` ≥ 200 en `MacApp/` (p. ej. `MacSettingsView.swift:29` sidebar 224 — correcto por ser patrón estándar de Ajustes; `MacDashboardView.swift:150` columna 380 — correcto por breakpoint) y dejar en el commit final una nota de cuáles se revisaron y por qué se conservan.

---

## Orden de ejecución sugerido

| Fase | Ítems | Motivo |
|---|---|---|
| 1 | Contrato en el shell + L-1 | Reproduce y cierra el bug de la captura |
| 2 | L-4 | Descuadre de columnas visible en uso diario |
| 3 | L-2, L-3 | Módulos completos recortados + ventanas auxiliares |
| 4 | L-5 | Hojas inutilizables en portátiles |
| 5 | L-6, L-7, L-8 | Mismos síntomas, menor exposición |
| 6 | L-9, L-10 | Prevención de regresiones |

## Verificación global al cerrar (matriz de QA manual)

Para **cada módulo** del sidebar (Dashboard, Cuaderno, Asistencia, Cursos, Alumnado, Planner, Diario, Situaciones, Rúbricas, Informes, Cond. física, Sync, Backups, Ajustes):

1. Ventana a **900×600** con sidebar visible → sin ningún texto/control recortado.
2. Ventana a **1280×800** con sidebar + inspector abiertos → sin recortes; el inspector aparece solo si cabe.
3. Redimensionar en continuo de 900 a 1600 pt → nada "salta" ni se solapa.
4. Asistencia → pestaña histórico con mes completo: cabeceras alineadas al píxel con sus columnas.
5. Abrir todas las hojas de L-5 con la ventana a 900×600: botonera visible y contenido scrolleable.
6. Ventanas auxiliares (Informes, Backups, Sync) a su tamaño mínimo: sin recortes.
7. Compila el scheme Mac sin errores nuevos; changelog actualizado; `registrar-avance-app` como capa final.
