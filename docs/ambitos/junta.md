# Ámbito: junta

## 1. Estado Actual
- **Objetivo del ámbito:** preparar y registrar la junta (sesión) de evaluación de un grupo: datos por alumno ya presentes en la app, suspensas de otras materias apuntadas a mano, acuerdos y acta en PDF.
- **Funcionalidades completadas:** tablas y migración 47 (esquema 48) con repositorio `EvaluationSessionRepositorySqlDelight`; casos de uso `EvaluationSessionUseCase` (crear, cargar, editar, cerrar, reabrir, borrar) expuestos en `KmpContainer.evaluationSessions`; puente `KmpBridge+EvaluationSession.swift` + `EvaluationSessionStore`; pantallas SwiftUI (lista de juntas, junta abierta/cerrada, panel de alumno, nueva junta, acta); módulo «Juntas» en la sección Evaluación (iPad, Mac, iPhone); acta PDF `EvaluationSessionActaPDF.swift`.
- **Pendiente / Roadmap:** [x] maqueta (puerta 1), [x] tablas y migración 47 (puerta 2), [x] lógica KMP, [x] puente, [x] pantalla SwiftUI, [x] acta PDF. Falta: QA manual en dispositivo/simulador con datos de prueba (no se ha abierto la app).
- **Deuda técnica:** sin SyncLAN en la primera versión: la junta vive en el dispositivo donde se crea.

## 2. Terreno de Juego (Ficheros y Límites)
- **Maqueta:** `docs/maquetas/junta_evaluacion_2026-10-28.html`.
- **Archivos bajo propiedad:** paquete KMP propio `kmp/shared/src/commonMain/kotlin/com/migestor/shared/evaluationsession/` (modelos, contrato, reglas, datos en vivo, caso de uso), `kmp/data/src/commonMain/sqldelight/com/migestor/data/db/EvaluationSession.sq` + `47.sqm`, `kmp/data/.../repository/EvaluationSessionRepositorySqlDelight.kt`, tests `EvaluationSessionRepositorySqlDelightTest.kt` (data) y `EvaluationSessionUseCaseTest.kt` (shared); puente `kmp/iosApp/App/Bridge/KmpBridge+EvaluationSession.swift`, vistas y estado `kmp/iosApp/App/EvaluationSession*.swift`, tests `kmp/iosApp/PlannerTests/JuntaProjectionTests.swift`.
- **Dependencias externas (solo lectura):** Media del Cuaderno (`NotebookRow.averageExplanation`), `getStudentAttendanceStats`, `listIncidents`, `listByStudent` (medidas de apoyo), `planner_evaluation_periods`.
- **Protegidos:** no tocar `kmp/shared/domain/` ni `KmpBridge.swift`. SQLDelight solo para las dos tablas nuevas, con permiso explícito del ticket.

## 3. Modelo de Datos y Dominio
- **Entidades:** `EvaluationSession` (grupo, evaluación, fecha, asistentes, acuerdos generales, cerrada) tiene muchas `EvaluationSessionStudent` (otras suspensas, acuerdo, revisado, Media y faltas congeladas al cerrar).
- **Máquina de estados:** `[Abierta] -> [Cerrada]`. Al cerrar se congelan Media y faltas; el acta lee lo congelado.
- **Invariantes:** una fila por alumno y junta; «otras suspensas» ≥ 0; el acta nunca incluye datos clínicos, solo el nivel de la medida.

## 4. Trampas Encontradas (Gotchas y Lecciones Aprendidas)
- ⚠ **Nuevo módulo de navegación:** añadir un caso a `AppWorkspaceModule` obliga a tocar switches exhaustivos (`WorkspaceLayoutState+Extensions.swift`, `WorkspaceModuleSwitcher.swift`), igual que en Inclusión.
- ⚠ **Gradle en sandbox:** `./gradlew` falla dentro del sandbox por `~/.gradle`; ejecutarlo fuera. `:shared:test` falla por falta de Android SDK: usar `:shared:desktopTest`.
- ⚠ **xcodebuild:** reescribe `*.xcscheme`; restaurar antes de commitear.
- ⚠ **FK apagadas en producción:** `PRAGMA foreign_keys` = 0, las cascadas no corren. Las filas se leen con `INNER JOIN students` y `deleteSession` borra antes `evaluation_session_students`. Ambas tablas están en el borrado selectivo (Cursos; las filas también en Alumnado).
- ⚠ **DDL duplicado:** `47.sqm` y `EvaluationSession.sq` deben decir lo mismo letra por letra (defaults e índices); si no, falla `UpgradePathRegressionTest`. Cualquier cambio futuro va en una migración 48 nueva.
- ⚠ **Kotlin 1.9:** no hay `kotlin.uuid`; el id de la junta sale de `randomEvaluationSessionId()` (UUID v4 a mano).
- ⚠ **API para Swift sin argumentos por defecto:** Swift no los ve en Kotlin 1.9; todos los métodos de `EvaluationSessionUseCase` piden todos los parámetros.
- ⚠ **Media < 5 sin redondear:** mismo criterio que `countApproved` del Cuaderno. Un 4,96 que se pinta como «5,0» cuenta como suspensa; si la UI redondea, avisar o alinear.
- ⚠ **Alumnado que sale del grupo:** su fila se conserva en la junta (no se borra al dar de baja la matrícula); los datos en vivo pueden salir vacíos porque ya no está en el Cuaderno.
- ⚠ **Test de torneos:** fijaba `Schema.version == 47`; ahora comprueba `>= 47`. Los tests de migración nuevos deben evitar fijar la versión exacta salvo la suya.
- ⚠ **Frameworks KMP no se versionan:** en un worktree nuevo falta `kmp/iosApp/Frameworks/`. Se generan solos en el primer `xcodebuild` (script de preconstrucción `build_apple_framework.sh`) o a mano con `kmp/scripts/build_apple_framework.sh`.
- ⚠ **Excepciones de Kotlin en Swift:** llegan como `NSError`; el mensaje claro está en `userInfo["KotlinException"]` (`EvaluationSessionException` y subclases). `EvaluationSessionStore.message(for:)` lo usa; cualquier otro error muestra un texto genérico.
- ⚠ **`createSession` no recibe asistentes:** el puente los guarda con un `updateHeader` justo después. Si ese segundo paso falla, la junta existe sin asistentes.
- ⚠ **Media junto a 5:** `JuntaFormat.average` enseña dos decimales truncados entre 4,95 y 5 (4,96 y 4,999 -> «4,99») para que nunca se lea «5,0» siendo suspensa. Cualquier otra pantalla que pinte la media de la junta debe usar esa función.
- ⚠ **Guardado automático:** edición local al instante + espera de 700 ms + `updateStudent`/`updateHeader`; después se reconcilia con `loadBoard`, salvo que haya ediciones nuevas. Antes de cerrar la junta, salir o cambiar de grupo se llama a `flushNow()`; si añades otra salida, haz lo mismo o se pierde la última edición.
- ⚠ **Tabla solo en ancho regular:** `Table` se usa en Mac/iPad regular y sin tamaños de accesibilidad; en iPhone y AX se usan tarjetas. En compacto `Table` solo pinta la primera columna. Las flechas ↑↓ las da la propia `Table` (no hay atajo propio).
- ⚠ **Acta PDF:** Core Text + Core Graphics a mano (tabla con cabecera repetida), no `PlannerReportPDFRenderer.render` (solo texto corrido). Reutiliza su tamaño de página y margen. `JuntaActaContent` filtra alumnado con acuerdo o suspensas y solo lleva el nivel de medida.
- ⚠ **Calendario del Planner sin enlazar:** la hoja «Nueva junta» no propone la evaluación desde `planner_evaluation_periods` (pasa `plannerEvaluationPeriodId = nil`).
- ⚠ **Commits y pbxproj:** los archivos nuevos solo compilan con el registro de `project.pbxproj` (último commit de la rama); los commits intermedios no compilan solos en Xcode.
