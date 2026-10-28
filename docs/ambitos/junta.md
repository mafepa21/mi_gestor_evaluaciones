# Ámbito: junta

## 1. Estado Actual
- **Objetivo del ámbito:** preparar y registrar la junta (sesión) de evaluación de un grupo: datos por alumno ya presentes en la app, suspensas de otras materias apuntadas a mano, acuerdos y acta en PDF.
- **Funcionalidades completadas:** ninguna todavía (ticket L aprobado el 2026-10-28, rama `codex/junta-evaluacion`).
- **Pendiente / Roadmap:** [ ] maqueta (puerta 1), [ ] tablas y migración 47 (puerta 2), [ ] lógica KMP, [ ] puente, [ ] pantalla SwiftUI, [ ] acta PDF.
- **Deuda técnica:** sin SyncLAN en la primera versión: la junta vive en el dispositivo donde se crea.

## 2. Terreno de Juego (Ficheros y Límites)
- **Maqueta:** `docs/maquetas/junta_evaluacion_2026-10-28.html`.
- **Archivos bajo propiedad (previstos):** paquete KMP propio `kmp/shared/src/commonMain/kotlin/com/migestor/shared/evaluationsession/`, puente `kmp/iosApp/App/Bridge/KmpBridge+EvaluationSession.swift`, vistas `kmp/iosApp/App/EvaluationSession*.swift`.
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
