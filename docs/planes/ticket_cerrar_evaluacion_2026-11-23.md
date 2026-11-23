# Ticket L: «Cerrar evaluación» y datos cualitativos sin esfuerzo

Estado: aprobado por el docente el 2026-11-23. Maqueta: `docs/maquetas/cerrar-evaluacion/mockup/index.html`.
Origen: `docs/planes/analisis_flujo_boletin_educamos_2026-11-23.md` (secciones 4 y 5).
Rama: `codex/flujo-boletin-arreglos-hig` (se fusiona junto al Ticket 1, PR #428).

## 1. Objetivo y contexto

Hoy cerrar una evaluación obliga a recorrer 4 pantallas de 2 módulos sin hilo común. Además, el informe anónimo no aprovecha lo cualitativo que la app ya guarda. Objetivo: un único recorrido guiado en el Cuaderno, y comentarios mejores sin pedir más trabajo al docente.

## 2. Alcance

1. **«Cerrar evaluación…»** sustituye a «Revisar cierre» en el menú del Cuaderno (iPad y Mac). Es una hoja con resumen de 4 pasos con estado, y cada fila abre su paso:
   - **Notas**: la revisión actual de «Revisar cierre», sin cambios de lógica.
   - **Comentarios**: «X de N». Acciones: *Redactar con la IA del dispositivo* (principal; abre «Generar lote» con la pestaña ya elegida), *Preparar texto anónimo para otra IA* (abre «Base para boletín» con grupo y trimestre) e *Importar comentarios…*. Lista filtrable (sin comentario / pocos datos / todos).
   - **Excel de Educamos**: abre «Exportar a Educamos». Recuerda fecha y recuento del último archivo generado.
   - **Subir a Educamos**: archivo generado («Mostrar en Finder» / «Compartir»), pasos a seguir e interruptor «Ya lo he subido».
   - El trimestre se deduce del título de la pestaña («1.ª Eval» → 1er Trimestre) y se puede cambiar con un selector.
2. **«Valoración rápida»** por alumno (desde el paso Comentarios): tres grupos de fichas (*Fortaleza*, *A mejorar*, *Orientación*). Las primeras salen de lo registrado: sellos del trimestre con su recuento, nivel de los criterios de rúbrica y días sin material. Le siguen frases fijas. Un toque añade la frase a «Tu valoración» (privada, la usa la IA), que se puede editar o dictar.
3. **«Base para boletín» ampliado** con los mismos datos que usa la IA del dispositivo (`BuildLomloeCommentEvidence`): nivel y descriptor de cada criterio de rúbrica, notas de celda, sellos con recuento y «Tu valoración». Todo pasa por el borrado de nombres. Los acuerdos de tutoría **no** salen en el texto anónimo.
4. **Periodo común**: el informe anónimo usa las fechas del trimestre del horario docente cuando están configuradas (igual que la IA) y, si no, las fechas fijas actuales.

## 3. Fuera de alcance

- Subir el archivo a Educamos desde la app: no hay API pública. La app solo guía al docente.
- Cambiar cómo redacta la IA del dispositivo (prompts) o su modelo.
- Sincronizar la marca «Ya lo he subido» entre iPad y Mac.
- Editar el catálogo de frases fijas desde la app.

## 4. Modelo de datos

- Sin migraciones ni tablas nuevas.
- «Tu valoración»: la tabla existente de notas del docente por alumno y trimestre (`TeacherTermNoteKeys`).
- Sellos: `annotation.icon` de las celdas, traducido con `NotebookCellStampCatalog`.
- «Ya lo he subido» y el último archivo generado: `UserDefaults` por grupo y pestaña (solo en ese dispositivo).
- KMP: nueva función por lotes `BuildLomloeCommentEvidenceUseCase.invokeForClass(classId, termKey)`, que carga los datos del grupo una vez en lugar de una por alumno.

## 5. Plan

1. KMP: `invokeForClass` + prueba en `LomloeCommentEvidenceBuilderTest`.
2. Swift: modelo del recorrido (`EvaluationClosingFlow`, sin vista) con estado de cada paso, trimestre de la pestaña y catálogo de fichas; pruebas XCTest.
3. Vista `EvaluationClosingSheet` (NavigationStack, 4 pasos) que reutiliza la revisión de notas actual; se sustituye la entrada del menú en iPad y Mac.
4. «Valoración rápida» (`QuickTermNoteSheet`) sobre `TeacherTermNoteStore`.
5. «Base para boletín» sobre la evidencia por lotes + sellos + valoración; pruebas de que no se cuelan nombres ni tutoría.
6. Conectar «Generar lote» y «Base para boletín» con grupo, pestaña y trimestre ya elegidos.
7. Compilar, probar y hacer la revisión HIG del código; registro y PR.

## 6. Agentes

- Implementación: agente principal (Opus).
- `ui-reviewer`: maqueta (hecho) y código final.
- `tests`/XCTest y `./gradlew :shared:desktopTest`: KMP y Swift.
- `reviewer` antes de abrir la PR.

## 7. Riesgos y puertas humanas

- **Privacidad**: «Tu valoración» y las notas de celda pueden traer nombres o datos de salud. Los nombres del grupo se borran; el resto, el docente debe revisarlo antes de pegar. Los acuerdos de tutoría se excluyen.
- **Rendimiento**: la evidencia de 30 alumnos tiene que salir de la carga por lotes. Hay que medir con un grupo inventado de 30.
- **Archivos sensibles**: `NotebookModuleDialogs.swift`, `NotebookModuleView.swift` e `IPadWorkspaceShell.swift` solo cambian la entrada del menú y la hoja que se abre.
- **La marca «Ya lo he subido»** no comprueba nada en Educamos. Es un recordatorio y lo dice en pantalla.
- **Puertas humanas**: aprobación de maqueta y ticket, QA manual en iPad y Mac con datos inventados, y fusión de la PR.

## 8. Criterios de aceptación

- Desde el Cuaderno, «Cerrar evaluación…» muestra los 4 pasos con su estado real, y cada paso lleva a su pantalla.
- El paso Comentarios cuenta bien quién tiene comentario en «Comentario de evaluación» de la pestaña y filtra «sin comentario» y «pocos datos».
- «Valoración rápida» propone fichas con los sellos y niveles de rúbrica del alumno en ese trimestre, y guarda en «Tu valoración».
- «Base para boletín» incluye rúbricas, sellos, notas de celda y valoración, sin nombres ni tutoría.
- «Redactar con la IA del dispositivo» guarda en «Comentario de evaluación» de la pestaña del recorrido.
- Funciona igual en iPad y Mac. Cumple HIG: barra nativa, VoiceOver, letra grande, 44 pt y modo oscuro.

## 8 bis. Normas HIG que se aplican en código (revisión de la maqueta)

- Filas del resumen como `NavigationLink` nativo, leídas como un solo elemento: título, detalle y estado en texto (no solo color); iconos decorativos y ocultos a VoiceOver.
- Botón Atrás del sistema en los pasos. «Valoración rápida» con «Cancelar» y «Guardar», «Guardar» desactivado sin cambios, y confirmación al cancelar con cambios.
- Fichas como `Toggle` con estilo botón: marca ✓ al elegir, origen en `accessibilityValue` y disposición que salta de línea con letra grande.
- Selectores cortos («1.º/2.º/3.º», «Sin comentario/Pocos datos/Todos») que pasan a menú con tamaños de accesibilidad.
- «Redactar con la IA del dispositivo» con progreso y motivo visible si no está disponible. En iPad, «Compartir» en lugar de Finder.
- Carga con `ProgressView` y anuncio para VoiceOver; error con `ContentUnavailableView` y «Reintentar»; colores semánticos del sistema.

## 9. Validación

- `./gradlew :shared:desktopTest --tests "*LomloeCommentEvidenceBuilderTest*"`.
- XCTest: modelo del recorrido, fichas, informe ampliado (sin nombres ni tutoría) y lectura real con alumnado inventado.
- `xcodebuild` de Mac e iPad. Suite completa de `MiGestorPlannerTests`, comparada con el fallo conocido.
- Revisión HIG del código por `ui-reviewer`.

## 10. Entregables

- Código y pruebas en la rama de la PR #428.
- Maqueta aprobada y este ticket en `docs/`.
- CHANGELOG, `docs/ambitos/informes.md` y `docs/ambitos/cuaderno.md` actualizados.
- Ruta del `.xcodeproj` de la carpeta de trabajo para probarlo.
