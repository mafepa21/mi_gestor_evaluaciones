# Plan: unificar el Dashboard de iPad y Mac y hacer real el modo Clase/Despacho (2026-07-28)

## Contexto

El usuario observa que en iPad el Dashboard tiene un selector segmentado `Clase` / `Despacho`
que "cambia la información según la situación", y que en Mac ese selector no existe. Pregunta
qué versión es mejor para el día a día de un profesor, cómo unificar ambas y cómo mejorar la UI.

**Hallazgo de la exploración: el selector de iPad hoy no cambia la información.** Es la premisa
que hay que corregir antes que nada, porque explica el síntoma que reporta el usuario ("las veo
muy iguales"): son literalmente iguales salvo el orden de cinco tarjetas.

Evidencia concreta en el código actual (rama `main`, commit `7dbee7f`):

- `DashboardOperationalRepositoryDefault.getSnapshot(date:mode:filters:)`
  (`kmp/data/src/commonMain/kotlin/com/migestor/data/repository/DashboardOperationalRepositoryDefault.kt:51`)
  recibe `mode: DashboardMode` y **no lo usa en ninguna consulta ni filtro**. Lo único que hace
  con él es copiarlo al `DashboardSnapshot` devuelto (línea 318, `mode = mode`). Los dos modos
  producen exactamente el mismo snapshot: mismas sesiones, mismas alertas, mismos grupos, misma
  agenda, mismos ítems de EF.
- `DashboardView.dashboardSecondaryGrid` (`kmp/iosApp/App/DashboardView.swift:527`) es el único
  sitio de toda la app donde el modo produce una diferencia visible, y esa diferencia es el
  **orden** de la lista de bloques secundarios: en `.classroom` va
  `[groupSummary, agenda, physicalEducation, lomloeAudit, system]` y en `.office` va
  `[lomloeAudit, groupSummary, agenda, physicalEducation, system]`. Mismas cinco tarjetas, mismo
  contenido, distinto orden.
- El modo también se propaga a `DashboardQuickEvaluationSheet` (`DashboardView.swift:160`) y a
  la etiqueta del radar proactivo (`DashboardView.swift:1594`, `"Clase"` / `"Despacho"`), pero
  ninguno de los dos altera qué datos se muestran.
- El Mac (`kmp/iosApp/MacApp/MacDashboardView.swift:271`) fija `mode: .office` a mano y no
  ofrece selector. Es coherente: no promete una distinción que el backend no cumple.

Por tanto, la pregunta "¿qué versión es mejor?" se responde así: **hoy, la de Mac**, porque no
enseña un control que no hace nada, y además tiene una pieza que el iPad no tiene y que es la
más útil en el día a día (la tarjeta "Ahora" con la clase en curso o la siguiente,
`DashboardHeroNowCard`, alimentada por `CurrentClassDashboardContext`). Pero la **idea** de los
dos modos es buena y merece implementarse de verdad. Este plan hace las dos cosas: unifica sobre
la base del Mac y convierte el modo en una distinción real y automática.

## Decisión de diseño: qué debe distinguir a Clase de Despacho

La diferencia no puede ser el orden de las tarjetas. Debe ser **el alcance (cuántos grupos) y el
horizonte temporal (cuánto tiempo por delante)**. Con eso, cada modo pasa a tener una identidad
que el profesor reconoce sin leer la etiqueta.

### Modo Clase (estoy dando clase ahora)

- **Alcance**: una sola clase, la que está en curso según el horario. No hay vista global.
- **Horizonte**: la sesión actual, unos 50 minutos.
- **Contenido**: tarjeta "Ahora" (grupo, aula, unidad, hora), acciones grandes (Pasar lista,
  Observación, Evaluar) y alumnado a vigilar hoy **en ese grupo**.
- **Se quita**: fila de KPIs, auditoría LOMLOE, resumen por grupo, agenda semanal, estado de
  sincronización y copias. Nada de eso se consulta con el grupo delante.
- **Forma**: una columna, tipografía grande, objetivos táctiles grandes.

### Modo Despacho (estoy preparando o corrigiendo)

- **Alcance**: todos los grupos.
- **Horizonte**: la semana y el trimestre.
- **Contenido**: KPIs, pendientes acumulados, resumen por grupo, auditoría LOMLOE, agenda,
  estado de sincronización y copias.
- **Se quita**: las acciones inmediatas de aula (pasar lista, observación rápida), que ahí no se
  usan.
- **Forma**: dos columnas en pantalla ancha, densidad alta.

### Conmutación automática

El modo pasa a calcularse por defecto desde el horario: si hay una franja lectiva en curso →
`Clase`; si no → `Despacho`. El selector segmentado se mantiene, pero como **anulación manual**,
con un tercer estado `Automático` que es el valor por defecto. Así el profesor abre el iPad al
entrar en el aula y ya está donde necesita, sin tocar nada.

## Alcance

### Sí se toca

- `kmp/data/src/commonMain/kotlin/com/migestor/data/repository/DashboardOperationalRepositoryDefault.kt`
  — que `mode` filtre de verdad.
- `kmp/iosApp/App/DashboardSharedBlocks.swift` — ampliar la capa compartida.
- `kmp/iosApp/App/DashboardView.swift` — iPad.
- `kmp/iosApp/MacApp/MacDashboardView.swift` — Mac.
- `docs/CHANGELOG.md` — una entrada por fase.

### Archivos protegidos que este plan necesita tocar, y por qué

`AGENTS.md` marca como protegidos `kmp/shared/domain/` y `kmp/iosApp/App/KmpBridge.swift`. Este
plan requiere tocar el primero y **no** el segundo:

- **`kmp/shared/src/commonMain/kotlin/com/migestor/shared/domain/Models.kt` (protegido):** hay
  que añadir a `DashboardSnapshot` un campo nuevo para el contexto de "clase actual / siguiente"
  (`currentContext: DashboardSessionContext?`). Sin ese campo, la tarjeta "Ahora" del Mac no se
  puede compartir con iPad: hoy vive en `MacDashboardSnapshot`, un modelo Swift privado y
  paralelo (`MacDashboardView.swift:663`) que se deriva del horario fijo del profesor y no del
  snapshot del backend. Es un campo nuevo con valor por defecto `null`, aditivo, sin migración
  de datos ni cambio de firma en lo existente. **Se pedirá confirmación explícita al usuario
  antes de tocarlo**, según la norma de `AGENTS.md`.
- **`KmpBridge.swift` (protegido): no hace falta tocarlo.** Ya expone
  `refreshDashboard(mode: DashboardMode)` (`KmpBridge.swift:1532`) y `loadDashboard(mode:)`, que
  es todo lo que necesitan las dos plataformas. Si en la fase 2 apareciera la necesidad de un
  método nuevo, se para y se consulta antes.

### No se toca

- **El horario del profesor ni el Planner.** El cálculo de "qué clase toca ahora" ya existe en
  `MacDashboardView.nextContext(...)` / `context(...)` (líneas 456-523) y se reutiliza tal cual,
  moviéndolo a la capa compartida sin cambiar su lógica.
- **`kmp/desktopApp/`** (protegido, y su `DashboardScreen.kt` es la app Compose de escritorio,
  fuera de esta tarea, que va sobre las apps Apple).
- **Los cálculos de riesgo, alertas y auditoría LOMLOE.** Se reparten distinto entre modos, pero
  no se cambia cómo se calculan.
- **La rama `feat/data-management-planner-collapsible`**, que está en curso en el checkout
  principal con cambios sin commitear. Este plan se desarrolla en `git worktree` aparte.

## Fases

Cada fase es un commit propio con su entrada de changelog, y las fases 1 a 4 pueden ir en PRs
separados. Las fases están ordenadas para que cada una deje la app en estado usable.

### Fase 1 — Que el modo filtre de verdad (backend)

**Archivo**: `DashboardOperationalRepositoryDefault.kt`.

En `getSnapshot`, ramificar por `mode` después de calcular los datos base:

- `CLASSROOM`: `targetClasses` se restringe a la clase de la sesión en curso (si `filters.classId`
  es `null`, se deduce de la sesión con `sessionStatus == "in_progress"`). `groupSummaries`,
  `agendaItems` y los ítems de auditoría se devuelven vacíos (no son de este modo).
  `alerts` se limita a las de esa clase y a las de severidad alta.
- `OFFICE`: comportamiento actual, sin acciones de aula.

**Verificación**: tests en `kmp/data/src/desktopTest/` que llamen a `getSnapshot` con los dos
modos sobre el mismo fixture y comprueben que devuelven cosas distintas. Hoy ese test fallaría
por definición, que es justo el punto.

### Fase 2 — Subir la tarjeta "Ahora" al snapshot compartido

1. Añadir `DashboardSessionContext` y el campo `currentContext` a `DashboardSnapshot`
   (`Models.kt`, protegido, previa confirmación).
2. Rellenarlo en el repositorio desde el horario, con la misma lógica que hoy usa
   `MacDashboardView.context(...)`.
3. Mover `DashboardHeroNowCard` a `DashboardSharedBlocks.swift` y hacer que lea
   `snapshot.currentContext` en vez de `MacDashboardSnapshot`.
4. Borrar `MacDashboardSnapshot`, `CurrentClassDashboardContext` y `DashboardPendingItem` del
   Mac cuando ya no los use nadie. Eso elimina la doble carga que hace hoy el Mac (su snapshot
   ad-hoc **más** el operativo, `MacDashboardView.swift:184`).

### Fase 3 — Una sola composición para las dos plataformas

Un único `DashboardComposition(mode:isWide:)` en la capa compartida que decida qué bloques se
pintan y en qué columnas. iPad y Mac pasan a diferenciarse solo en `isWide` y en el cromado de
la barra de herramientas, no en qué tarjetas existen.

El Mac gana el selector de modo (hoy no lo tiene) y el iPad gana la tarjeta "Ahora" (hoy no la
tiene). A partir de aquí, misma pantalla en ambas.

### Fase 4 — Modo automático

- `@AppStorage("dashboard_operational_mode")` pasa a admitir un tercer valor, `auto`, que es el
  nuevo valor por defecto (hoy el defecto es `office`, `DashboardView.swift:100`).
- Con `auto`, el modo efectivo sale de `snapshot.currentContext.status`: `active` → `Clase`,
  cualquier otro → `Despacho`.
- El selector muestra tres opciones y una etiqueta pequeña que indica qué modo se ha resuelto
  cuando está en automático.

### Fase 5 — Aligerar la interfaz

- **Máximo tres tarjetas visibles en Clase.** El resto no se pliega: no se renderiza.
- **La fila de KPIs solo en Despacho** (hoy se pinta siempre, `DashboardView.swift:473`).
- **Los filtros de severidad y prioridad, dentro de la tarjeta que filtran**, no sueltos en la
  cabecera (hoy `dashboardFilterChips`, `DashboardView.swift:477`).
- **Bloques secundarios plegados por defecto**, reutilizando el patrón `DisclosureGroup` que ya
  se introdujo en `CollapsibleBulkDeleteSection` para Ajustes → Gestión de datos.
- **Un solo color por nivel de riesgo.** Hoy conviven `EvaluationDesign.accent`,
  `IOSAppStyle.warning` y `EvaluationDesign.success` en la misma pantalla y ninguno destaca.
- **Cabecera "Hoy" fija** al hacer scroll, con hora y grupo actual.

## Riesgos

- **El más serio: la fase 1 cambia qué ve el profesor en modo Clase.** Si el horario no está
  configurado o la sesión en curso no se detecta, el modo Clase se quedaría vacío. Mitigación:
  si no hay sesión en curso, el modo efectivo cae a Despacho en vez de mostrar una pantalla en
  blanco, y el estado vacío explica que falta configurar el horario (ya existe
  `MacDashboardEmptyReason.noScheduleConfigured`, `MacDashboardView.swift:657`).
- Tocar `Models.kt` (protegido) afecta al binario compartido de KMP: hay que recompilar el
  framework y comprobar que no rompe Mac, iPad ni la app Compose de escritorio.
- Borrar `MacDashboardSnapshot` toca ~200 líneas del Mac. Va en su propio commit, después de que
  la tarjeta compartida ya funcione, no a la vez.
- `DashboardView.swift` (2017 líneas) y `MacDashboardView.swift` (2156) son archivos grandes; la
  fase 3 mueve mucho código. Conviene que sea un commit de movimiento puro, sin cambios de
  comportamiento, para que el diff sea revisable.

## Verificación prevista

Se registrará honestamente qué se ejecuta y qué no:

- `./gradlew :data:desktopTest` para los tests nuevos de la fase 1.
- Compilación del framework KMP y de los esquemas `MiGestorKMPiOS` y `MiGestorKMPMac` (recordar
  `DEVELOPER_DIR`, ver `AGENTS.md`).
- Prueba manual: con horario configurado y una sesión en curso, comprobar que el modo automático
  entra en Clase; fuera de horario, que cae a Despacho.
- Prueba manual del caso sin horario configurado, que es el estado vacío de mayor riesgo.

## Estado

Plan aprobado por el usuario el 2026-07-28. Pendiente de confirmar el punto de `Models.kt`
(archivo protegido) antes de empezar la fase 2.
