# Ticket L · Voz de Pista: «Hoy evalúo», rúbrica visible y grabaciones para analizar después

Maqueta: `mockup/voz-sesion-evaluacion.html` (5 estados, revisada contra HIG y con sus arreglos aplicados).

## 1. Objetivo / contexto

En pista el docente sabe qué está evaluando, pero hoy la app tiene que adivinarlo, y la rúbrica no se ve mientras se dicta. Además no puede dictar varias tandas seguidas y revisarlas más tarde con calma.

## 2. Alcance

1. **«Hoy evalúo»**: menú junto a Grupo y Fecha con los instrumentos con criterios de la clase (rúbricas, listas de cotejo, formularios), los de la sesión de hoy arriba, y «Detectar al dictar» (el comportamiento actual). Si hay uno elegido:
   - todas las evaluaciones del dictado van a ese instrumento, sin adivinar la columna;
   - el modo alumna a alumna está activo desde el principio;
   - una descripción de una alumna es evaluación de ese instrumento (no observación), salvo notas de actitud, asistencia o lesión;
   - la elección se recuerda por clase y se bloquea mientras se graba.
2. **Rúbrica visible**: la hoja crece (iPad «tamaño página»; Mac mínimo 1100 × 760; iPhone hoja grande). En iPad/Mac, columna derecha con la rúbrica completa: criterios × niveles con descriptores. Al tocar una alumna de la bandeja se marca su fila y el nivel sugerido («✦ Sugerido» en texto) y se puede cambiar el nivel tocando la celda. Con texto grande o poco ancho, una tarjeta por criterio con niveles apilados; en Mac estrecho, inspector ocultable; en iPhone, botón «Ver rúbrica» que abre hoja aparte.
3. **Bandeja compacta** cuando hay instrumento elegido: una fila por alumna con sus niveles en chips; la tarjeta completa al tocarla.
4. **Grabaciones**: cada dictado con el micrófono se guarda como archivo de audio en el dispositivo (clase, fecha, instrumento, duración). Control «Analizar al parar / Solo guardar». Lista «Grabaciones» por clase con selección múltiple, «Analizar N grabaciones» (transcripción una a una con progreso, la bandeja se va llenando), borrar con confirmación, vacío y errores (sin dictado sin conexión con botón a Ajustes, sin permiso de micrófono).

## 3. Fuera de alcance

- Ver quién falta por evaluar (siguiente ticket).
- Escuchar el trozo de audio de cada evaluación.
- Sincronizar grabaciones con el Mac (SyncLAN) o copias de seguridad de audio.
- Cambios en KMP, SQLDelight o `KmpBridge.swift`.

## 4. Modelo de datos (sin cambios de esquema)

- Instrumento elegido por clase: `UserDefaults` (`court.voice.focus.instrument.v1.<classId>` → `columnId`).
- Grabaciones: archivos `.m4a` en `Application Support/CourtVoiceRecordings/<classId>/` con protección de datos completa (`.completeUnlessOpen`) y excluidos de iCloud Backup. Índice JSON junto a ellos: `id`, `classId`, `createdAt`, `duration`, `instrumentColumnId?`, `title`, `transcript?` (se guarda al transcribir para no repetir).
- Borrado automático de la grabación al aplicar sus acciones; borrado manual en cualquier momento.

## 5. Plan

1. `CourtVoiceRecordingStore` (archivos + índice) y grabación: el mismo `AVAudioEngine` que ya alimenta el reconocimiento escribe a la vez un `AVAudioFile`.
2. Análisis por lotes: transcribir con `transcribeAudioFile` cada grabación seleccionada, unir los textos por grabación y pasar todo por el análisis actual (troceado ya preparado para textos largos).
3. «Hoy evalúo»: `Menu` con `Picker` inline por secciones; el servicio recibe `focusColumnId` y fuerza instrumento, modo alumna a alumna y conversión a evaluación.
4. Hoja grande y columna de rúbrica: `CourtVoiceRubricPanel` (archivo propio) con `Grid`, variante apilada (`ViewThatFits` / `dynamicTypeSize`), selección de alumna y cambio de nivel.
5. Bandeja compacta.
6. Accesibilidad: una fila accesible por criterio con valor y ajuste arriba/abajo, etiquetas de casillas, anuncios de inicio/fin de grabación y de errores.
7. Tests: foco de instrumento en el motor de reglas (con el dictado anonimizado), índice de grabaciones (crear, listar, borrar, borrar al aplicar), troceado y unión de varias grabaciones.

## 6. Criterios de aceptación

- Con «Hoy evalúo: Rúbrica de lanzamiento» y el dictado anonimizado, todas las evaluaciones van a esa rúbrica y no queda ninguna «observación» técnica.
- La rúbrica se ve entera en iPad horizontal y en Mac a 1100 de ancho, sin scroll horizontal; con texto XXL pasa a tarjetas.
- Tocar una alumna marca su fila y nivel; cambiar una celda cambia el nivel de esa alumna en la bandeja.
- «Solo guardar» deja la grabación en la lista sin analizar; «Analizar 2 grabaciones» crea una bandeja con las acciones de las dos.
- Las grabaciones no salen del dispositivo y se borran al aplicar.
- Los tests de Voz de Pista actuales siguen en verde.

## 7. Validación

- `xcodebuild test` de las suites de Voz de Pista + tests nuevos.
- Build `MiGestorKMPiOS` (simulador) y `MiGestorKMPMac`.
- Prueba manual en iPad y Mac con datos de prueba: elegir rúbrica, dictar, «Solo guardar», analizar dos grabaciones, VoiceOver en la rúbrica.

## 8. Agentes

- Esta sesión hace el trabajo. `reviewer` revisa el código y `ui-reviewer` las capturas reales.

## 9. Riesgos y puertas humanas

- **Audio del alumnado en el dispositivo.** Es dato sensible: archivos protegidos, fuera de iCloud Backup y borrado al aplicar. Puerta humana: confirmas que quieres guardar audio en el dispositivo con estas reglas.
- Espacio: unos 1 MB por minuto en AAC. Se muestra la duración y se puede borrar.
- `presentationSizing(.page)` necesita iPadOS 18; con sistemas anteriores, hoja grande actual.
- Hoja muy grande en iPad vertical: se usa la variante apilada.

## 10. Entregables

- Código Swift (`CourtVoiceCaptureSheet.swift`, servicio, `CourtVoiceRubricPanel.swift`, `CourtVoiceRecordingStore.swift`), tests, changelog, PR contra `develop` con capturas.
