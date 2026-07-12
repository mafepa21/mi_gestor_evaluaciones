# ADR 2026-07-12 - Medidas de apoyo Nivel III/IV (NEE/NESE)

## Estado

Aceptado.

## Contexto

La Comunidad Valenciana regula la respuesta educativa a la diversidad en el Decreto 104/2018 y la Orden 20/2019: Nivel I y II son medidas de centro/aula que ya gestiona el equipo docente sin registro individual; Nivel III son apoyos ordinarios adicionales sobre un alumno o grupo concreto; Nivel IV son apoyos especializados extraordinarios (ACIS, sesiones PT/AL, adaptaciones de acceso con materiales singulares) que requieren informe sociopsicopedagógico y un Plan de Actuación Personalizado (PAP) redactados por el orientador.

El docente de aula no redacta el informe ni el PAP. Su rol real es: conocer que el alumno tiene una medida activa, consultar en qué consiste, implementarla en su materia, evaluar según los referentes del ACIS si aplica, y dejar constancia de observaciones de progreso con revisión anual. La app no gestionaba nada de esto: `students` solo tenía identidad básica (nombre, foto, sexo, fecha de nacimiento, lesión).

Los datos de NEE/NESE son categoría especial bajo RGPD/LOPDGDD (salud y educación especial de menores), lo que condiciona qué se persiste y cómo.

## Decisión

Las medidas se modelan como entidad ligera propia, `student_support_measures`, con FK a `students(id) ON DELETE CASCADE` y el mismo patrón de sync (`updated_at_epoch_ms`/`device_id`/`sync_version`) que el resto de tablas sincronizadas por SyncLAN. Cuelga del alumno global, no del curso escolar: una medida Nivel IV no se archiva al cerrar el curso, igual que la identidad del alumno sobrevive a los cursos en el modelo `AcademicYear`/`StudentEnrollment` ya existente.

Reglas de contenido, no solo de esquema:

- **Nunca se guarda el informe sociopsicopedagógico ni diagnósticos clínicos como texto.** Solo una referencia/ruta al documento oficial (`document_ref`) y las notas de seguimiento propias del docente de aula (`follow_up_notes`).
- **`measure_type` es un enum cerrado**, no texto libre, para que el badge del Cuaderno y los filtros sean fiables. Nivel IV usa la lista cerrada de la Orden 20/2019 (`ACIS`, `EXENCION`, `FLEXIBILIZACION`, `PERMANENCIA_EXTRAORDINARIA`, `ESCOLARIZACION_ESPECIFICA`). **Nivel III usa el catálogo docente real del usuario** (18 medidas concretas agrupadas en Aprendizaje/Participación/Acceso/Flexibilización, cada una con su código de referencia ITACA), sustituyendo una primera versión con 5 categorías genéricas (`REFUERZO`/`ENRIQUECIMIENTO`/`ADAPTACION_ACCESO`/`APOYO_PT`/`APOYO_AL`) que no reflejaba cómo el docente trabaja realmente. Como Nivel III es un checklist de adaptaciones concretas (no una categoría única), el formulario permite seleccionar 1 o más medidas de golpe; cada selección se persiste como una fila independiente de `student_support_measures` (mismo nivel/fecha/responsable, un `measure_type` distinto cada una), así cada medida se puede retirar de forma independiente sin perder las demás. El catálogo (grupo, texto completo, código ITACA) vive en Swift (`SupportMeasureShared.swift`); Kotlin solo conoce los identificadores del enum, igual que ya trataba `measure_type` como opaco.
- **Retirar una medida no borra la fila** (`is_active = 0` + `end_date_iso`), conserva histórico igual que el resto del repo (`academic_years`, `students`).
- **Sin IA generativa.** Apple Foundation Models no interviene en ningún punto de esta feature: el riesgo de alucinación sobre datos legales y de salud de menores es inaceptable. El único mecanismo "inteligente" es una comprobación determinista de fecha (`review_due_iso` vencido o a menos de 30 días), sin generación de contenido.
- **Sync LAN normal**, igual que el resto del alumnado: la protección real de estos datos es que SyncLAN es solo-red-local del centro, no una decisión de excluir campos del payload.
- **El badge del Cuaderno no hace join en vivo por celda.** Se expone un flag precomputado (`Set<Int64>` de alumnos con medida activa, `ListActiveSupportMeasureStudentIdsUseCase`) que se carga una vez por cambio de clase junto al resto de señales del Cuaderno (`refreshNotebookSignals`), siguiendo el mismo patrón ya usado para `todayAttendanceByStudentId`/`incidentCountByStudentId`/`riskLevelCache`. No se toca el hot path de render de `NotebookModuleView.swift`.
- **La UI vive en la ficha de alumno existente**, no en una pantalla nueva de navegación principal: sección "Medidas de apoyo" dentro de `StudentProfilesWorkspaceView.swift` (iOS/iPadOS) y `MacStudentsView.swift` (macOS), con un único sheet de alta compartido entre ambas plataformas (`SupportMeasureFormSheet`, reutilizando el scaffold cross-platform `WorkspaceCreateSheetScaffold` ya existente).

## Consecuencias

- Cualquier ampliación futura que quiera resumir o sugerir contenido sobre estas medidas con IA debe justificarse explícitamente y probablemente requiere una revisión legal aparte, no solo una decisión de arquitectura.
- Si se añade exportación/informes que puedan incluir alumnado con estas medidas, hay que excluir `student_support_measures` por defecto y hacerlo opt-in explícito, no incluirlo en informes generales.
- Si se amplía `measure_type` con nuevas medidas de la normativa o del catálogo docente, mantener el enum cerrado en KMP (`kmp/shared/domain/Models.kt`) en vez de admitir texto libre, y añadir el metadato correspondiente (grupo, texto, código ITACA) en `SupportMeasureTypeUI` (Swift).
- Como no había datos reales persistidos con el enum anterior de 5 categorías genéricas (PR sin fusionar), el reemplazo por el catálogo de 18 medidas se hizo sin migración de datos ni compatibilidad hacia atrás; si en el futuro hay datos reales guardados, un cambio de enum equivalente sí necesitaría migración.
- El flag precomputado del Cuaderno debe seguir cargándose junto a `refreshNotebookSignals()`; no añadir una consulta por fila/celda para este dato.
