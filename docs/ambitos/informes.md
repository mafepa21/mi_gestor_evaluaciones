# Ámbito: Informes

## Estado actual

- Pantalla Informes (iPad y Mac comparten vista): lista lateral de tipos de informe y panel de detalle. Tipos: grupo, individual, resumen de evaluación, resumen operativo, comentario LOMLOE y «Base para boletín».
- «Base para boletín» genera un texto anónimo con asistencia, notas evaluables, autoevaluaciones y observaciones de cada alumno del grupo en un trimestre, para pegarlo en una IA externa. La clave código → nombre solo se ve en una hoja de la app.

## Terreno de juego

- Vista: `kmp/iosApp/App/RubricsReportsWorkspaceViews.swift` (`ReportsWorkspaceView`). Tocar solo la sección afectada: el archivo es grande.
- Tipos de informe: `KmpBridge.ReportKind` en `App/Bridge/KmpBridgeModels.swift`; contexto narrativo en `buildReportGenerationContext` (`KmpBridge+Students.swift`).
- Base para boletín: `App/BulletinBaseReport.swift` (anonimizado y texto, sin KMP), `App/Bridge/KmpBridge+BulletinBase.swift` (lectura de datos), `App/BulletinBaseReportView.swift` (detalle y hoja de clave). Pruebas: `PlannerTests/BulletinBaseReportTests.swift`.

## Trampas

- `ReportKind.allCases` pinta la lista lateral: un tipo nuevo aparece solo, pero hay que cubrirlo en `reportContextDescription` y en el `switch` de `buildReportGenerationContext`.
- `bulletinBase` no usa `buildReportGenerationContext` (lanza error a propósito): `reloadPreview` sale antes y sube `bulletinReloadToken` para que la vista recargue.
- Los códigos «Alumno NN» siguen un orden por hash de clase + alumno: estables al recargar y no alfabéticos. Si cambia la lista del grupo, pueden moverse: la clave debe leerse en la misma sesión en que se copia el texto.
- El borrado de nombres trabaja con el alumnado del grupo: palabras de 3 letras o más de nombre y apellidos, sin tildes ni mayúsculas. Un apellido que sea palabra común («Rosa», «Cruz») también se tapa en el texto. Un nombre ajeno al grupo no se detecta: por eso el aviso de revisar antes de pegar.
- Una palabra de nombre que comparten varios alumnos se cambia por «[nombre]», nunca por un código.
- Notas evaluables = columna que cuenta para la media, no oculta, tipo numérico/rúbrica/calculada y valor entre 0 y 10. Así quedan fuera los datos brutos (metros, segundos).
- La nota de diario guarda `studentName`: no se usa nunca en este informe.
- Trimestres: `ReportTerm.rawValue` coincide con `AttendanceMatrixRange`, que da las fechas del curso actual.
- «Generar lote» (LOMLOE por lotes) guarda por defecto en «Comentario de evaluación» de una pestaña del Cuaderno (`saveApprovedDraftsToEvaluationComment`). La pestaña propuesta es la última usada del grupo (`restoredSelectedNotebookTab`), no la del trimestre: los títulos de pestaña («1.ª Eval») no coinciden con los trimestres («1er Trimestre»).
- El icono `text.bubble` de «Comentario de evaluación» es contrato con KMP (`LomloeCommentEvidenceBuilder.EVALUATION_COMMENT_ICON`): si cambia en Swift, la IA volverá a leer el comentario como observación.
- Asistencia del informe anónimo: «sin material» y «exento» son presencia. Un estado no reconocido no cuenta en el porcentaje.
- «Base para boletín» usa `BuildLomloeCommentEvidenceUseCase.invokeForClass` (una carga para todo el grupo) para rúbricas y notas de celda; las incidencias siguen saliendo del puente y los acuerdos de tutoría se descartan a propósito. El periodo es el del horario docente (`resolveTermPeriod`) y, si no hay, las fechas fijas de `AttendanceMatrixRange`.
- Enviar notas (Mac): `ShareLink` en el Mac solo comparte (AirDrop, Mail…), no guarda en el disco. Para guardar, `fileExporter` con `GradeReportPDFDocument`. Va en un `.background` aparte del `fileImporter` de carpeta: dos paneles de archivo en la misma vista se pisan.
- En las hojas del Mac, un botón en `.primaryAction` de la barra puede no verse: lo importante va también en el contenido (la columna de la izquierda).
- El detalle enseña primero al alumno elegido. «Has terminado» solo sale sin nadie elegido: si no, tapa el informe de los alumnos sin correo.
