# Ámbito: junta

## 1. Estado Actual
- **Objetivo del ámbito:** preparar y registrar la junta (sesión) de evaluación de un grupo: datos por alumno ya presentes en la app, suspensas de otras materias apuntadas a mano, acuerdos y acta en PDF.
- **Funcionalidades completadas:** tablas y migración 47 (esquema 48) con repositorio `EvaluationSessionRepositorySqlDelight`; casos de uso `EvaluationSessionUseCase` (crear, cargar, editar, cerrar, reabrir, borrar) expuestos en `KmpContainer.evaluationSessions`.
- **Pendiente / Roadmap:** [x] maqueta (puerta 1), [x] tablas y migración 47 (puerta 2), [x] lógica KMP, [ ] puente, [ ] pantalla SwiftUI, [ ] acta PDF.
- **Deuda técnica:** sin SyncLAN en la primera versión: la junta vive en el dispositivo donde se crea.

## 2. Terreno de Juego (Ficheros y Límites)
- **Maqueta:** `docs/maquetas/junta_evaluacion_2026-10-28.html`.
- **Archivos bajo propiedad:** paquete KMP propio `kmp/shared/src/commonMain/kotlin/com/migestor/shared/evaluationsession/` (modelos, contrato, reglas, datos en vivo, caso de uso), `kmp/data/src/commonMain/sqldelight/com/migestor/data/db/EvaluationSession.sq` + `47.sqm`, `kmp/data/.../repository/EvaluationSessionRepositorySqlDelight.kt`, tests `EvaluationSessionRepositorySqlDelightTest.kt` (data) y `EvaluationSessionUseCaseTest.kt` (shared); previstos: puente `kmp/iosApp/App/Bridge/KmpBridge+EvaluationSession.swift`, vistas `kmp/iosApp/App/EvaluationSession*.swift`.
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
