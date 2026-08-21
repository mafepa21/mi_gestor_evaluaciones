# Contrato de importación de documentos de Situaciones de Aprendizaje

Este documento describe, para cada uno de los tres tipos de DOCX que la app sabe
importar desde una carpeta de Situación de Aprendizaje (SA), qué estructura espera el
parser real y qué produce. Es la referencia técnica que faltaba en el repo — la única
guía de autoría existente hasta ahora (`GUIA_AUTORIA_DOCX_INSTRUMENTOS.md`, fuera del
repo, en `Knowledge/estructuras/` de la carpeta de Programaciones) solo cubre
`instrumentos_evaluacion.docx`.

Auditoría de referencia: `plan_correccion_import_sa_2026-07-25.md` (raíz del repo),
volcando el XML real de los 30 DOCX de las 10 carpetas de
`Programación aula/Situaciones de aprendizaje/`.

Los tres servicios de importación viven en
`kmp/iosApp/AppleShared/LearningSituation*ImportService.swift`; la materialización a
evaluaciones/columnas/rúbricas del cuaderno está en `kmp/iosApp/App/KmpBridge.swift`.
Los tres leen el documento por **bloques** (párrafo o tabla, en orden de aparición),
usando el lector compartido `wordDocumentBlocks(from:)`.

## 1. `01_PROGRAMACION_DIDACTICA/situacion_aprendizaje_*.docx`

Servicio: `LearningSituationDocumentImportService`.

Metadatos de la ficha técnica (etapa, curso, materia, centro, trimestre, duración) se
reconocen en dos formas, probando primero la de párrafo y si no hay nada cayendo a la
de tabla:

- **Párrafo**: `Etiqueta: valor` en la misma línea (ej. `Etapa: Bachillerato.`).
- **Tabla**: dos columnas `Campo | Dato` (o similar), una fila por metadato (ej.
  `Etapa / curso | 1º de Bachillerato`); la etiqueta se busca por coincidencia de
  substring normalizado en la primera celda de cada fila.

Sinónimos reconocidos por campo (normalizados, sin tildes): etapa (`etapa`, `stage`),
curso (`curso`, `grade`), materia (`materia`, `subject`), trimestre (`trimestre`,
`term`, `evaluacion` — ej. `Evaluación: 2ª evaluación`), centro (`centro de
referencia`, `centro`, `center`, `context`, `contexto`), duración (`temporalización`,
`time allocation`, `duration`, `duración`).

Reto/pregunta motriz y producto final: párrafo con la etiqueta seguida de `:` en la
misma línea, o el párrafo siguiente si la etiqueta va sola. Etiquetas: `Pregunta
Motriz`, `Driving question`, `Pregunta guía`, `Reto inicial` (reto); `Producto Final`,
`Final product` (producto).

Justificación: texto que sigue a un encabezado de sección — `JUSTIFICACIÓN Y RETO`,
`CLIL justification and driving question`, `justification` o `Justificación` (ej.
`2. Justificación y pregunta guía`) — hasta el siguiente encabezado (`Pregunta
Motriz`/`Driving question`/`CLIL 4Cs`/`4Cs`).

Competencias: párrafos que empiezan por `CE.`/`CEn.`/`CE n` o contienen la palabra
"competencia" **junto con** un código de criterio o `:` (un encabezado de sección
como "Competencias específicas", sin código ni contenido propio, se descarta).

Criterios de evaluación: dos fuentes, con preferencia por párrafos si hay alguno:

- **Párrafo**: contiene "criterio"/"criterion" y, o bien lleva un código de criterio
  (`\d+\.\d+`, con o sin prefijo `CE`/`Criterio`/`Criteri`/`Criterion`), o bien tiene
  contenido tras `:`. Si el párrafo siguiente empieza por `Evidencia:`/`Evidence:`, se
  usa como evidencia asociada.
- **Tabla**: cabecera cuya primera columna contiene "criterio"/"criteri" (ej.
  `Criterio | Enunciado oficial (traducción de trabajo) | Rol en esta SA`); cada fila
  aporta un criterio (código normalizado a `CE X.X`) con la segunda columna como
  evidencia.

Saberes básicos y metodología: texto entre un encabezado de inicio y uno de fin (ver
`sectionText` en el código para la lista completa de sinónimos ES/EN).

Ponderaciones de evaluación (`evaluationItems`): párrafo con `%` que además contiene
"criterio", "criteri" (forma valenciana: `Criteri 1.1 Diseño del plan - 40%: …`),
"criterion", "total", "ce " o "ce.", **o** que cae dentro de las ~15 líneas siguientes
a un encabezado `Sistema de evaluación`/`Evaluación (resumen)` aunque no lleve ninguna
de esas palabras.

## 2. `02_SESIONES/sesiones_secuenciadas*.docx`

Servicio: `LearningSituationSessionSequenceDocumentImportService`.

### Encabezado de sesión (común a los dos formatos)

Un párrafo que empieza por `Sesión`/`Sesiones`/`Session`/`Sessions` (con o sin tilde,
singular o plural), seguido del número (o de "N y M" para una ficha compartida entre
dos sesiones), y **inmediatamente** después — sin texto de prosa pegado — o bien nada
más, o bien una anotación entre paréntesis (`(NEW)`/`(nueva)`), o bien uno de estos
separadores: `.`, `-`, `–`, `—`, `:`. Ejemplos válidos: `Sesión 1 - Doble: Principios
de entrenamiento`, `Session 1. Rules, safety...`, `Sesiones 3 y 5 - Dobles: ...`,
`Session 7 (NEW) — Designing...`. Un párrafo de prosa que solo *empieza* pareciendo un
encabezado (`Session 3 finishes the panel and starts planning the final event.`) no
matchea porque tras el número no hay separador ni fin de línea.

El texto tras el separador es el título; se recorta el prefijo de tipo (`Simple`/
`Simples`/`Double`/`Doubles`/`Doble`/`Dobles`, con o sin plural) y cualquier anotación
entre paréntesis.

El **cuerpo** de la sesión es todo lo que hay entre un encabezado y el siguiente. Si
contiene alguna tabla, se usa el formato B (tablas); si no, el formato A (párrafos).

### Formato A — solo SA 1

Etiquetas en párrafos, cada una con su valor tras `:` en la misma línea:
`Objetivo:`/`Objetivos:`, `Criterios:`/`Criterio:` (los códigos se extraen con
`(?:CE|Criteri[oa]?|Criterion)?\s*\d+\.\d+`, normalizados a `CE X.X`, ignorando el
texto entre paréntesis), `Material:`/`Materiales:`, `Evidencia:`/`Evidencias:`.
Desarrollo: párrafos que empiezan por `Bloque N`, `Descanso`, `Desarrollo de la
sesión...` o contienen un rango horario (`0'-3': ...`) actúan como título de una
sección; las líneas siguientes son su contenido, hasta el siguiente título o hasta
`Adaptación al contexto...`/`Context adaptation...` (lo que sigue a esa etiqueta se
guarda como adaptaciones).

### Formato B — el resto de carpetas (SA 2 a SA 6, los 4 documentos de cierre)

Ficha de sesión con las mismas etiquetas que el formato A más sinónimos en inglés,
en dos posibles formas:

- **Tabla** `etiqueta | valor` (a veces con cabecera genérica `Item | Detail`).
- **Dos párrafos consecutivos**: uno con la etiqueta sola (≤6 palabras) y el
  siguiente con el contenido.

Etiquetas reconocidas (normalizadas): objetivo (`objetivo`, `objetivo específico`,
`specific objective`, `main objective`...), criterios (`criterios de evaluación`,
`criteria worked`, `evaluation criteria addressed`, `assessment focus`...), saberes
básicos (`saberes básicos trabajados`, `core knowledge addressed`...), material
(`material necesario`, `materials needed`...), organización del grupo (informativo,
no se guarda en un campo propio), evidencia, fecha (se ignora).

Cada sesión trae normalmente **dos versiones** de la misma sesión, marcadas por un
párrafo que contiene "version"/"versión" (o "session adaptation"/"sesión simple") y
"simple" o "doble"/"double" (ej. `SIMPLE version (30' effective)...`, `Timed
development — 90' version (Double session...)`, `Simple session adaptation (30'
useful)`). **No se duplica la sesión**: cada versión genera una sección de desarrollo
propia (`Versión simple (30′)` / `Versión doble (90′)`); `sessionType` refleja las
versiones presentes (`Simple`, `Doble` o `Simple y Doble`) y `effectiveMinutes` toma
la simple como referencia cuando hay las dos, con aviso explícito.

Cada versión trae una o más **tablas horarias**, con cabecera `Time | Phase | Activity
| Teacher role | Student role | Evidence` (o su equivalente en español: `Tiempo | Fase
| Actividad | Papel del docente/Profesorado | Papel del alumnado/Alumnado |
Evidencia`); cada fila se convierte en una línea legible de desarrollo (`Tiempo · Fase
— Actividad (Profesorado: ...; Alumnado: ...; Evidencia: ...)`).

Secciones finales que se conservan (por palabras clave, ES/EN, contains, no exact
match): `Guiding questions`/`Preguntas guía` → sección "Preguntas orientativas";
`Difficulty variants`/`Variantes de dificultad` → "Variantes de dificultad";
`Adaptations`/`Adaptaciones` → van al campo `adaptations`, no a `development`;
`Evidence collected`/`Evidencias recogidas` → "Evidencia recogida"; `Assessment
instrument`/`Instrumento(s) de evaluación` → "Instrumento de evaluación"; `Closure`/
`Cierre` → "Cierre". Cualquier otro párrafo o tabla no reconocido se conserva como
línea de una sección de desarrollo genérica ("Desarrollo"), nunca se descarta.

### Ficha operativa de actividad: autoría narrativa

Para que la ficha de sesión se pueda utilizar durante la clase, cada actividad debe
estar redactada como una instrucción operativa completa, no como una etiqueta o una
lista de palabras clave. El contenido se muestra en inglés en el detalle de la
actividad, mientras que las etiquetas de navegación de la app se mantienen en
español para que el docente encuentre rápidamente cada apartado.

La forma recomendada es una tabla `Activity Details` con una entrada por actividad.
El identificador estable (`Activity ID`, por ejemplo `W02-L-01`) debe coincidir con
la columna `Activity ID` de la tabla horaria. El importador combina ambos registros;
por tanto, la tabla horaria puede ser esquemática y la ficha de detalle puede llevar
la explicación completa.

Campos operativos admitidos (con sinónimos en inglés y español):

- `Purpose`: explica qué aprendizaje o evidencia se busca y por qué la actividad va
  en ese momento.
- `Organisation`: indica parejas, grupos, estaciones, roles y cómo se hacen los
  cambios con una clase numerosa.
- `Set-up`: describe qué deja preparado el docente antes de empezar y cómo se
  distribuyen espacio y materiales.
- `Teacher instructions`, `Teacher narrative` o `Teacher script`: redacta la
  secuencia docente en presente, incluyendo la señal de inicio, el modelado, las
  comprobaciones de seguridad y las intervenciones durante la práctica.
- `Instructions for students`, `Student narrative` o `Student actions`: explica lo
  que hace el alumnado paso a paso y qué debe producir o comunicar.
- `Timing breakdown`, `Transition cue` o `Transition`: reparte el tiempo real,
  incluyendo cambios de estación, entrega/recogida de material, desplazamientos y
  la señal para pasar a la siguiente actividad.
- `CLIL focus`: aporta objetivo lingüístico, vocabulario y estructuras modelo.
- `Evidence`, `Materials`, `Adaptations`, `If the group is slow` y `If the group is
  ahead`: completan la toma de decisiones y permiten ajustar la sesión sin inventar
  instrucciones en el momento.

Cada campo narrativo debería contener frases completas y observables. Por ejemplo,
`Teacher narrative` debe decir qué hace y qué comprueba el profesor, mientras que
`Student narrative` debe permitir que otro docente ejecute la actividad sin conocer
la intención original. La temporización debe ser conservadora para grupos de hasta
35 alumnos: se reserva tiempo explícito para formar parejas, repartir material,
escuchar la consigna y recoger evidencias. El importador conserva el texto completo,
incluidas las frases largas, sin resumirlo ni sustituirlo por una descripción
genérica.

### Minutos por tipo (`defaultMinutesByType`)

Se buscan en todo el documento (incluidas las celdas de tabla) frases como `Simple
sessions are designed for 30 effective minutes.` o `(30' útiles)`. Se acepta un
apóstrofo (`'`/`’`/`′`, con la palabra `effective`/`useful`/`efectivos`/`útiles`
opcional detrás) o esas mismas palabras seguidas de `minutos`/`minutes`/`min`.

## 3. `05_EVALUACION/instrumentos_evaluacion*.docx`

Servicio: `LearningSituationAssessmentInstrumentsImportService`. Contrato completo en
`GUIA_AUTORIA_DOCX_INSTRUMENTOS.md` (Knowledge/estructuras/, fuera del repo,
actualizada en la misma revisión que este documento). Resumen de los puntos que
cambiaron en la auditoría de 2026-07-25:

- Un encabezado sin numerar con un criterio decimal (`Rúbrica... - CE 2.1 - 40%`) ya
  no se descarta por el punto de "2.1".
- Un encabezado numerado sin palabra clave pero con `%` y/o `CE X.X` cuenta como
  encabezado igualmente.
- Con varios criterios en el mismo encabezado se extraen todos, no solo el primero.
- La sección "Nota para quien importe esto" corta de verdad el resto del documento.
- Los párrafos no consumidos como ítem/pregunta se conservan como nota del
  instrumento, no se descartan.
- Una checklist con ítems y peso se detecta como computable (`checklistProportional`)
  en vez de "Auxiliar", y **desde entonces la nota automática sí se calcula y se
  guarda**: `NotebookInstrumentsRepositorySqlDelight.saveResponses` deriva
  `ítems marcados / ítems totales × 10` en `deriveProportionalChecklistScore` y la
  persiste vía `gradesRepository.saveGrade`, así que la columna suma a la media.
  Solo se aplica a los ítems `CHECK` con clave `chkp_<n>` (la que genera el importador
  Apple para `CHECKLIST_PROPORTIONAL`); las checklists de requisito de entrega
  (`check_<n>`, sin peso) y las de todo/nada siguen sin generar nota automática.
- Una rejilla con peso cuya última columna es de nota (`Nota`/`Note`/`Final mark`) sin
  escala explícita asume escala 1-4 y avisa.
- El aviso de descuadre de pesos se emite siempre (antes solo si no había fórmula de
  calificación), y se añade verificación cruzada entre los términos de la fórmula y
  los instrumentos detectados.
- Una pregunta de quiz con opciones por `/` pero sin `?` se importa con sus opciones,
  cortando en el último `:` cuando no hay `?`.

Cambio de 2026-07-31, instrumento mixto que rellena el alumnado:

- Un instrumento cuyo título contiene `autoevaluación`/`coevaluación` (o `autoavaluació`,
  `coavaluació`, `self-assessment`, `peer assessment`) **y** lleva debajo una tabla de rúbrica de
  4 niveles deja de tiparse como `checklist` y pasa a `selfAssessment`/`peerAssessment`. Sin esa
  tabla, el comportamiento histórico no cambia.
- Ese instrumento genera **dos clases de ítems** en una única plantilla estructurada:
  los indicadores de la rúbrica con clave `rub_<n>` y tipo `SCALE_1_4` (los cuatro descriptores
  del nivel viajan en `helpText`, así que se ven también en el formulario web publicado), y las
  preguntas de reflexión con clave `open_<n>` y tipo `TEXT`.
- La nota se deriva en `NotebookInstrumentsRepositorySqlDelight.deriveStudentRubricScore`: media
  de los ítems `rub_<n>` respondidos, en escala 1-4, persistida con `gradesRepository.saveGrade`.
  La columna es `NUMERIC` con `scaleKind = FOUR_LEVEL`, así que la media del cuaderno la normaliza
  a 0-10 igual que la de una rejilla de observación. Los ítems `open_<n>` quedan **fuera** del
  cálculo a propósito: no se pueden ponderar solos y los revisa el profesorado.
- Como la plantilla existe (no hay rúbrica guardada en `rubricsRepository` para este tipo), el
  instrumento **se puede publicar como formulario web** para el alumnado, y la entrega importada
  pasa por `saveResponses`, que calcula la nota.
- Límite de diseño, no técnico: la rúbrica ponderable debe valorar a **quien la rellena**. La app
  atribuye cada respuesta a quien la escribe, así que una valoración sobre otro alumno/a acabaría
  en la fila equivocada; ese caso sigue haciéndose en papel con una rúbrica normal del docente.

## Limitaciones conocidas (no resueltas por la auditoría de 2026-07-25)

- ~~**Checklist proporcional sin nota automática**~~: **resuelto**. El cálculo ya está
  implementado en `NotebookInstrumentsRepositorySqlDelight.deriveProportionalChecklistScore`
  y la columna cuenta hacia la media. Ver el punto correspondiente de §3.
- **Quiz sin autocorrección**: `QuizQuestionDraft` importa `questionText` y `options`,
  pero no la respuesta correcta, y `saveResponses` solo deriva nota para la rejilla de
  observación 1-4 y la checklist proporcional. Un quiz se guarda como respuestas, sin
  nota automática de % de aciertos: haría falta clave de respuestas, puntuación por
  pregunta y versionado de la clave.
- **Peso importado (0,4) vs. peso manual (×1) en la misma pestaña**: las columnas
  importadas de una SA guardan `weight = weightPercent / 100`, mientras que las
  columnas manuales usan multiplicadores enteros (`×1`, `×2`...). Si conviven en la
  misma pestaña, las importadas pesan mucho menos de lo que sugiere su porcentaje en
  el cálculo real de la media. La cabecera de columna del cuaderno ya muestra el peso
  como porcentaje en vez de `×0,4` (más legible), pero el cálculo subyacente no
  cambia.
