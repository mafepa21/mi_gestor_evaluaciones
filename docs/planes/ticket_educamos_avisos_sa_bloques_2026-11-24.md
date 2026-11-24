# Ticket M: Avisos en Educamos, SA por bloque y nota de evaluación en la IA

Estado: aprobado por el docente el 2026-11-24. Maqueta: `docs/maquetas/educamos-avisos-sa/mockup/index.html`.
Rama: `codex/educamos-avisos-sa-bloques` (desde `main` en `02d104cc`).

## Objetivo y contexto

Tras la pestaña de evaluación con pesos (PR #430, ADR 003) quedan tres huecos que pueden llevar un dato equivocado al boletín:

1. «Exportar a Educamos» sube la nota parcial de un alumno al que le falta un bloque (la nota con *) sin avisar.
2. Cada «Media de SA» de Educamos se empareja con una pestaña solo por el nombre. Si en Educamos se llama «SA2 Hockey» y en la app «Hockey», a veces no la encuentra, y no se puede elegir a mano.
3. La IA del dispositivo cita en el comentario su propia media del trimestre, que puede no coincidir con la nota de evaluación del Resumen.

## Alcance

1. **Avisos antes de generar** (sección «Avisos» arriba de «Revisar exportación»):
   - Alumnos a los que les falta algún bloque, con nombres y el bloque.
   - Elección «Nota final de esos alumnos»: **Dejarla vacía** (por defecto) o **Exportar la nota parcial**. Se recuerda por grupo.
   - Alumnos sin comentario de evaluación (solo aviso).
   - Sin avisos: «Todo completo».
2. **Elegir la pestaña de cada SA**:
   - Cada «Media de SA» pasa a ser un menú de pestañas (los bloques muestran su evaluación: «Hockey (1.ª Evaluación)») y «Sin pestaña».
   - Propuesta por nombre como hoy, más tolerante: ignora prefijos tipo «SA2».
   - La elección se recuerda por grupo y por elemento de Educamos, igual que las columnas de instrumentos.
3. **Nota final siempre de la evaluación**:
   - La «Nota final» usa la nota de evaluación de la pestaña de evaluación del Excel, no la Media de la pestaña abierta.
   - La evaluación se deduce del título («1.ª Evaluación» ↔ evaluación del Excel) o, si no, de la pestaña abierta.
4. **La IA usa la nota de evaluación**:
   - `BuildLomloeCommentEvidenceUseCase` añade `evaluationAverage` (nota por bloques de la evaluación de ese trimestre, si existe).
   - El comentario LOMLOE la usa antes que la media del periodo o la del curso.

## Normas HIG (revisión de la maqueta)

- **Avisos:** `Label` con icono de aviso y etiqueta «Aviso: …» para VoiceOver, en colores del sistema.
- **Lista de alumnos:** dentro de un `DisclosureGroup` («Ver alumnos»), sin cortar con letra grande.
- **Menús de SA:** `Picker` de menú con etiqueta «Pestaña para <SA>» y 44 pt.
- **SA sin pestaña:** se avisa con texto e icono, no solo con la opción por defecto.
- **Nota final:** el `Picker` lleva una pista que explica qué pasa con la nota final.

## Fuera de alcance

- Nota final de curso, columnas antiguas de una raíz y sincronizar «Ya lo he subido».
- Límite de longitud del comentario en Educamos (no está documentado).

## Modelo de datos

- Sin migraciones.
- `LomloeCommentEvidence.evaluationAverage: Double? = null` (KMP, `usecase/`, no protegido).
- Preferencias en `UserDefaults` por grupo: emparejamiento SA ↔ pestaña (misma clave que las columnas) y elección de la nota final parcial.

## Plan

1. **KMP:**
   - `evaluationAverage` en la evidencia, con el título de la evaluación por `TeacherTermNoteKeys.fromLabel`.
   - Prueba con 60/40 y un bloque vacío.
2. **Swift, Educamos:**
   - Avisos.
   - Menú de SA.
   - Nota final de la evaluación.
   - Elección de nota parcial.
   - Pruebas XCTest de la lógica (sin vista).
3. **Swift, IA:** `KmpBridge+Students` prefiere `evaluationAverage`.
4. **Cierre:**
   - Compilar Mac e iPad.
   - Suite completa.
   - Revisión HIG del código.
   - CHANGELOG y ámbito.
   - PR.

## Agentes

- Implementación: agente principal.
- `ui-reviewer`: maqueta y código.
- XCTest y `:shared:desktopTest`.

## Criterios de aceptación

- Con un alumno sin notas en Ultimate, «Revisar exportación» lo avisa. Con «Dejarla vacía», su celda de nota final queda vacía en el Excel; con «Exportar la nota parcial», lleva la nota redondeada.
- «SA2 Hockey» propone «Hockey» solo. Una elección a mano se mantiene al volver a importar el mismo Excel.
- La nota final es la de la evaluación aunque el Cuaderno esté abierto en un bloque.
- El comentario LOMLOE de un alumno con Hockey 7,5 (60 %) y Ultimate 6,0 (40 %) cita 6,9.
- Cumple HIG en iPad y Mac.

## Validación

- `./gradlew :shared:desktopTest --tests "*LomloeCommentEvidenceBuilderTest*"`.
- XCTest nuevo de la lógica de Educamos.
- `xcodebuild` Mac e iPad y suite completa (comparada con el fallo conocido).
