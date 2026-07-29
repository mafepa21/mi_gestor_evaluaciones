# Plan: onboarding guiado de primer uso y reubicación de "Cursos" (2026-07-29)

## Contexto y problema real

Abrir la app de cero deja al docente en un callejón. Hoy el orden obligado es:

1. `Cursos` (barra lateral) → crear Asignatura en `SubjectCatalogSheet`.
2. En la misma pantalla → crear el curso escolar (`AcademicYearWizardSheet`).
3. Crear los grupos uno a uno (`CourseClassEditorSheet`), **o** irse a `Ajustes → Horario docente`
   (o al Planner) donde el asistente `TeacherScheduleWizard` sí crea grupos solo al importar el `.xlsx`.

Tres problemas concretos, verificados en el código:

- **No hay ningún primer uso guiado.** No existe ninguna vista, flag ni estado de onboarding en
  `kmp/iosApp` (`grep` de onboarding/bienvenida solo devuelve un comentario en
  `PlannerSequenceGanttView.swift`). El usuario aterriza en `Cursos` con "Este curso escolar no
  tiene grupos" y sin ninguna indicación de por dónde empezar.
- **El camino manual del horario está roto de facto.** En `TeacherScheduleWizard.slotEditorForm`
  (`kmp/iosApp/App/TeacherScheduleWizard.swift:559`) el selector "Grupo" solo lista `vm.groups`, y
  el botón "Añadir franja" está deshabilitado si `scheduleFormGroupId == nil`. Es decir: **sin
  grupos previos no se puede crear ni una franja a mano**. Solo la importación de Excel crea grupos
  (`importSchedulePreview`). Ese es el nudo que hace que todo parezca "farragoso".
- **"Cursos" ocupa un puesto de primera fila que no merece.** Está en la barra lateral en los tres
  shells (`IOSFeatureRegistry.swift:22`, `MacFeatureRegistry.swift:13`,
  `IPadWorkspaceShell.swift:483`) como módulo diario. En la práctica es configuración: se toca al
  empezar el curso y casi nunca más.

Nada de lo que sigue inventa capas nuevas: el asistente de horario, la importación de horario,
la de alumnado (`StudentImportSheet`), la de situaciones (`LearningSituationDocumentImportService`)
y la de instrumentos (`LearningSituationAssessmentInstrumentsImportService`) **ya existen**. El
plan los cose en un recorrido único y los hace descubribles.

## Objetivo

1. Que la primera apertura de la app muestre un panel flotante que explique qué hace la app y
   ofrezca una configuración inicial guiada, en el orden que tiene sentido docente:
   **fechas del curso → horario → grupos → alumnado → situaciones e instrumentos**.
2. Que cada paso tenga siempre **dos caminos**: importar un documento, o hacerlo a mano de forma
   sencilla (hoy el manual del horario ni siquiera es posible).
3. Sacar `Cursos` de la barra lateral y llevarlo a `Ajustes`.

## Decisiones de diseño

**D1 — Onboarding en dos piezas, no una.** Un `sheet` de bienvenida (explicativo, 3 tarjetas, se
lee en 20 segundos) y una **lista de tareas persistente** ("Primeros pasos") que sobrevive al
cierre de la app y se puede reabrir. Un asistente monolítico de 5 pasos obligaría a completar todo
de una sentada; un docente configura esto en varias tardes. La lista de tareas es lo que hace el
recorrido reanudable.

**D2 — Los pasos abren las pantallas reales, no copias.** Cada tarea del checklist presenta el
componente que ya existe (`TeacherScheduleWizard`, `StudentImportSheet`, hoja de creación de SA…).
Cero duplicación de UI y cero riesgo de que el camino guiado y el normal diverjan.

**D3 — Progreso derivado de los datos, no de un contador.** Cada paso se marca como hecho
consultando el estado real vía `KmpBridge` (¿hay curso escolar con fechas? ¿hay franjas? ¿hay
grupos? ¿hay matrículas? ¿hay SA?). Si el docente hace una tarea por su cuenta, el checklist se
entera. Un booleano por paso mentiría en cuanto alguien restaure un backup o sincronice por LAN.

**D4 — Nunca molestar a quien ya tiene datos.** El onboarding se dispara solo si
`!onboardingCompleted && la base está vacía` (sin grupos y sin alumnado). Así una actualización de
la app no le lanza un tutorial en la cara a un docente con el curso a medias.

**D5 — El horario manual pasa a poder crear grupos.** Es el cambio funcional imprescindible.
Sin él, "opción manual fácil" es imposible.

**D6 — `Cursos` va a Ajustes, no se borra.** La pantalla `CoursesWorkspaceView` sigue siendo la
dueña del curso escolar, asignaturas, grupos y archivado. Solo cambia de sitio.

## Alcance

### Fase 1 · Onboarding de primer uso

Archivos nuevos (todos en `kmp/iosApp/AppleShared/`, para que iOS, iPadOS y macOS compartan una
sola implementación):

- `OnboardingModels.swift`
  - `enum OnboardingStep: course, schedule, groups, students, learningSituations, instruments`
    con `title`, `whyItMatters` (una línea en lenguaje de profesor), `systemImage`,
    `importHint` y `manualHint`.
  - `struct OnboardingProgress` con un `Bool` por paso.
  - `OnboardingStore: ObservableObject`
    - `@AppStorage("onboarding.completed.v1")` y `@AppStorage("onboarding.dismissedAt.v1")`.
    - `func refresh(bridge:) async` → recalcula el progreso real (D3).
    - `var shouldPresentWelcome: Bool` (D4).
- `OnboardingWelcomeSheet.swift` — bienvenida. Título, una línea de qué es la app, y tres tarjetas:
  *Planifica* (horario y sesiones), *Evalúa* (cuaderno, rúbricas, instrumentos), *Sigue* (asistencia,
  alumnado, informes). Dos botones: **"Configurar mi curso"** (primario) y **"Ahora no"**.
- `OnboardingChecklistView.swift` — la lista de tareas. Cada fila: número, título, por qué importa,
  estado (pendiente / hecho), y **dos botones explícitos: "Importar…" y "Hacerlo a mano"**. Los
  pasos posteriores aparecen deshabilitados con el motivo escrito ("Necesitas el horario antes de
  crear los grupos"), nunca en gris mudo.
- `OnboardingHost.swift` — modificador `.onboardingHost(bridge:)` que engancha welcome + checklist +
  las hojas de cada paso, para que los tres shells lo activen con una línea.

Puntos de enganche:
- `kmp/iosApp/App/IOSRootView.swift` (iPhone), `kmp/iosApp/App/IPadWorkspaceShell.swift` (iPad),
  `kmp/iosApp/MacApp/MacRootView.swift` (macOS): añadir `.onboardingHost(bridge:)` al contenedor raíz.
- Reapertura manual: fila **"Primeros pasos"** en `Ajustes → General`, siempre disponible.
- Dashboard vacío: si `progress` no está completo, `DashboardView` muestra una tarjeta
  "Continuar configuración" en vez del vacío actual (reutiliza `DashboardRecommendations`).

Contenido de los pasos (esto es lo que el usuario pidió que fuera "explícito y perfecto"):

| # | Paso | Importar | Manual |
|---|---|---|---|
| 1 | Fechas del curso | — | Presets "1 sept – 30 jun" ya existentes en `courseHeroCard` |
| 2 | Horario semanal | `.xlsx` vía `ScheduleExcelImportService` | Rejilla semanal: tocar una celda crea la franja |
| 3 | Grupos | Se crean solos desde el horario | Alta rápida desde el propio editor de franjas (Fase 2) |
| 4 | Alumnado | Excel vía `StudentImportSheet` | Pegar/teclear nombres, uno por línea |
| 5 | Situaciones de aprendizaje | DOCX vía `LearningSituationDocumentImportService` | Crear SA vacía |

**Decidido (2026-07-29): los instrumentos de evaluación quedan fuera de esta tanda.** No hacen
falta para empezar a dar clase y alargaban el recorrido justo donde el docente quiere cerrar. El
paso 6 se valorará en una segunda vuelta, con los cinco primeros ya rodados.

### Fase 2 · Hacer viable el horario manual (bloqueante para la Fase 1)

En `kmp/iosApp/App/TeacherScheduleWizard.swift`:

- En `slotEditorForm`, añadir al `Picker` de grupo una opción **"+ Grupo nuevo…"** que abre un campo
  en línea (nombre + nivel) y crea el `SchoolClass` vía el mismo camino que ya usa
  `CourseClassEditorSheet`. Al crearlo, queda seleccionado en el formulario.
- Si `vm.groups.isEmpty`, sustituir el formulario deshabilitado por una llamada a la acción clara:
  "Aún no tienes grupos. Impórtalos con tu horario, o crea el primero aquí."
- En `ScheduleWeekGridView`, permitir **tocar una celda vacía** para precargar día y hora en el
  formulario. Es la diferencia entre teclear cuatro campos y dar un toque.
- Paso 3 "Terminado" del asistente: cerrar el círculo con "Ya tienes N grupos. ¿Añadimos su
  alumnado?" enlazando al paso 4 del checklist.

### Fase 3 · Mover "Cursos" a Ajustes

- Quitar la entrada de las tres barras laterales:
  - `kmp/iosApp/App/IOSFeatureRegistry.swift:22` (borrar de `daily`).
  - `kmp/iosApp/MacApp/MacFeatureRegistry.swift` (borrar de `MacFeatureSection.evaluacion`).
  - `kmp/iosApp/App/IPadWorkspaceShell.swift:483` y su sección correspondiente.
- Añadirla como sección de Ajustes:
  - `SettingsWorkspaceView.swift`: nuevo `SettingsSectionDescriptor` `"courses"` → *"Cursos y grupos"*,
    subtítulo *"Curso escolar, asignaturas, grupos y archivado"*, justo detrás de `General`, y su
    rama en `settingsDetail(for:)` → `CoursesWorkspaceView`.
  - `MacSettingsView.swift`: fila `.courses` en la lista, mismo destino.
- **No romper los accesos existentes** (esto es lo que se rompería si solo se borra la entrada):
  - `IOSRootView.swift:524` y `IPadWorkspaceShell.swift:1767` ("Gestión de grupos" desde el menú del
    Cuaderno) y `MacRootView.swift:1369` deben navegar a `Ajustes → Cursos y grupos` en vez de a un
    módulo que ya no está en la barra.
  - El módulo `.courses` se conserva en los enums y en `KmpBridge.swift:776` / `:12682` (contexto de
    IA por pantalla). Solo deja de ser un destino de barra lateral.

## Fuera de alcance

- Rediseñar `CoursesWorkspaceView` por dentro. Se mueve, no se toca.
- Tocar `KmpBridge.swift`, `kmp/shared/domain/` o el esquema SQLDelight. El onboarding lee estado
  existente y reutiliza las altas ya implementadas; **no hace falta ninguna migración**.
- Onboarding en `kmp/desktopApp/` (Compose Desktop, target distinto).

## Riesgos

| Riesgo | Mitigación |
|---|---|
| El tutorial salta a docentes que ya usan la app | D4: doble condición (flag + base vacía). Probar con backup restaurado |
| Alta de grupo en dos sitios (asistente y Cursos) que diverjan | Ambos llaman al mismo método del bridge; nada de lógica nueva de creación |
| Quitar `Cursos` de la barra deja accesos huérfanos | Los tres puntos de entrada listados se redirigen en el mismo commit |
| Se rompe el flujo del Cuaderno en iPad | Verificación manual explícita del menú "Gestión de grupos" en los tres shells |
| Archivos nuevos no compilan en el target | Están en `AppleShared/`; regenerar con `xcodegen` (`kmp/iosApp/project.yml`) |

## Orden de trabajo (commits atómicos, ramas separadas)

1. `feat(horario): permitir crear grupos desde el asistente manual` — Fase 2. Aporta valor solo.
2. `feat(onboarding): panel de primer uso y lista de primeros pasos` — Fase 1.
3. `refactor(nav): mover Cursos de la barra lateral a Ajustes` — Fase 3.

Cada uno con su changelog, según `registrar-avance-app`.

## Verificación ejecutada (2026-07-29)

- `xcodegen generate` en `kmp/iosApp/`: OK. Se revirtió a mano el cambio incidental en
  `MiGestorKMPiOS.xcscheme` (ruido de versión de Xcode, no relacionado con este trabajo).
- `xcodebuild` esquema `MiGestorKMPiOS`, destino genérico de simulador iOS: **BUILD SUCCEEDED**.
- `xcodebuild` esquema `MiGestorKMPMac`, destino macOS: **BUILD SUCCEEDED**.
- **Prueba en vivo (iPad Pro 13", simulador, instalación limpia)**: se desinstaló la app, se instaló
  el build nuevo y se arrancó. La bienvenida sale sola en el primer arranque, y la barra lateral ya
  no tiene `Cursos`. Evidencia: captura del simulador tomada con `simctl io screenshot`.
- Durante esa prueba se detectó y corrigió un fallo real del criterio de arranque: `KmpContainer
  .seedDemoDataIfEmpty` siembra una clase de ejemplo ("3 ESO A", descripción "Clase demo") con dos
  alumnos en la primera ejecución, así que la base **nunca** habría parecido vacía y la bienvenida
  no habría salido jamás. El recuento de grupos y alumnado descuenta ahora esa clase sembrada.

## Verificación manual pendiente

No se ha podido automatizar la interacción con el simulador (el panel de control falla con este
Xcode beta: falta `SimulatorKit.framework` en su ruta), así que a partir de la bienvenida el
recorrido está sin probar en vivo:

- Bienvenida → "Configurar mi curso" → lista de primeros pasos → fechas con presets → **crear
  franja a mano sin grupos previos** → comprobar que el grupo queda creado → alumnado → SA.
- Arranque con base ya poblada (grupos y alumnado reales): comprobar que **no** aparece la
  bienvenida.
- Los tres shells (iPhone, iPad, macOS): "Gestión de grupos" desde el Cuaderno abre
  `Ajustes → Cursos y grupos`, y en iPhone además navega (push por estado).
- Reapertura desde Ajustes → General → Primeros pasos, con el contador de progreso al día.
- Comparar los fallos de CI contra el estado previo de `origin/main`; no se exigirá verde absoluto.

## Desviaciones respecto al plan durante la implementación

Se registran aquí para que el plan siga siendo fiel a lo que se hizo:

- **Orden de trabajo**: el usuario pidió implementar desde la Fase 1. Se hicieron las tres en el
  mismo pase, no en el orden 2→1→3 que proponía el plan.
- **`OnboardingHost` recibe el `KmpBridge` explícito** en vez de leerlo del entorno: la shell de
  macOS trabaja con el bridge de su `MacAppSessionController`, que no es la instancia del entorno.
- **Quién dispara la bienvenida**: no el modificador, sino cada shell al terminar su carga inicial
  (`IOSRootView.task`, `MacRootView` al pasar a `.ready`). Preguntar antes vería la base vacía
  siempre y le lanzaría el tutorial a un docente con el curso empezado.
- **Salto a una sección de Ajustes desde fuera**: hizo falta un `SettingsNavigationStore` nuevo
  (AppleShared) porque hay tres shells y dos pantallas de Ajustes distintas.
- **Ajustes en iPhone** pasa de `NavigationLink(destination:)` a `navigationDestination(item:)`,
  para que una petición externa también navegue en compacto.
- **Gancho en el dashboard**: en vez de una tarjeta nueva, el botón principal del estado vacío
  ("Crear clase") pasa a ser "Configurar mi curso" y abre la lista. Menos superficie, mismo efecto.
- **Paso 6 fuera** (ver arriba).
