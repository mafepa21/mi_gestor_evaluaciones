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
