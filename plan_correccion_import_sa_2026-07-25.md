# Plan de corrección: importación de documentos de Situaciones de Aprendizaje (2026-07-25)

## Contexto

La carpeta de trabajo `~/Desktop/Programaciones/output/Programación aula/Situaciones de aprendizaje/`
contiene 10 carpetas (6 SA + 4 documentos de cierre/evaluación inicial), cada una con tres
familias de documentos que la app sabe importar:

| Documento | Servicio Swift que lo importa |
|---|---|
| `01_PROGRAMACION_DIDACTICA/situacion_aprendizaje_*.docx` | `LearningSituationDocumentImportService` |
| `02_SESIONES/sesiones_secuenciadas*.docx` | `LearningSituationSessionSequenceDocumentImportService` |
| `05_EVALUACION/instrumentos_evaluacion*.docx` | `LearningSituationAssessmentInstrumentsImportService` |

(los tres primeros viven en `kmp/iosApp/AppleShared/LearningSituation*ImportService.swift`;
la materialización a evaluaciones/columnas/rúbricas está en `kmp/iosApp/App/KmpBridge.swift`).

Auditoría hecha el 2026-07-25 volcando el XML real de los 30 DOCX y contrastándolo, regla a
regla, con el parser. **Los tres importadores fallan sobre los documentos reales**: hay SA que
pierden el 100 % de sus instrumentos calificables, sesiones fantasma, títulos contaminados y
ponderaciones que no llegan a computar en la media. Este plan recoge cada fallo con su
evidencia concreta.

La guía de autoría `Knowledge/estructuras/GUIA_AUTORIA_DOCX_INSTRUMENTOS.md` (en la carpeta de
Programaciones, fuera del repo) describe un contrato que **no coincide** con el parser actual
en varios puntos; se actualiza como parte del trabajo.

---

## Bloque A — Importador de instrumentos de evaluación

### A1. Encabezado sin numerar con `CE X.X`: se descarta por el punto decimal (crítico)

`looksLikeHeadingProse` rechaza cualquier texto con `.`, `!` o `?` en el interior. Los
encabezados de SA 5 y SA 6 no van numerados:

```
Rúbrica técnico-táctica de torneo - CE 2.1 - 40%
Rejilla de observación sistemática Spirit of the Game - CE 2.1 - 25%
```

El `.` de `2.1` los invalida → **SA 5 pierde sus 4 instrumentos calificables (100 % del peso) y
SA 6 pierde los suyos (40+25+15+20)**. Las tablas quedan huérfanas (`currentHeading == nil`) y
`headingFromTable` tampoco las rescata, porque la primera celda es `Indicador`/`Criterio`.

**Fix**: antes de la comprobación de puntuación, neutralizar los números decimales y los
porcentajes (`\d+[.,]\d+`, `\d+\s*%`); solo entonces mirar si queda `.`/`!`/`?` interior.

### A2. Encabezado numerado sin palabra clave (crítico)

`isNumberedInstrumentHeading` exige una palabra clave. SA 3 tiene:

```
4. Mini-portafolio de datos y reflexión - CE 3.3 - 15%
```

Ninguna palabra está en `instrumentHeadingKeywords` → el instrumento se pierde **y además su
tabla se acumula en el instrumento 3** (la rejilla de fair-play), que acaba con dos tablas y
campos de observación inventados a partir de una rúbrica ajena.

**Fix**: aceptar como encabezado un párrafo numerado (`N.`/`N)`) que además lleve `NN%` y/o
`CE X.X`, aunque no tenga palabra clave. Ampliar también el vocabulario con
`cuestionario`, `test`, `portafolio`, `mini-portafolio`, `informe`, `proyecto`, `diario`,
`registro`, `rejilla`.

### A3. Título e identificador de criterio contaminados cuando hay varios criterios

`parseHeading` solo recorta **un** `- CE X.X` y **un** `- NN%`:

| Encabezado real | Título que se guarda hoy |
|---|---|
| `2. Rejilla de observación sistemática - CE 1.2 y 1.4 (proceso) - 35%` | `Rejilla de observación sistemática y 1.4 (proceso)` |
| `3. Quiz de hábitos y alimentación saludable - CE 1.4 y CE 1.3 - 15%` | `Quiz de hábitos y alimentación saludable y CE 1.3` |

Ese título contaminado es el nombre de la evaluación **y de la columna del cuaderno**, y rompe
el emparejamiento con los términos de la fórmula de calificación.

**Fix**: cortar el encabezado en el primer separador que introduce metadatos
(` - CE …` o ` - NN%`) y quedarse con lo anterior como título; extraer **todos** los códigos de
criterio de la parte recortada (`CE 1.2`, `1.4`, `CE 1.3`) y guardarlos unidos (`CE 1.2 · CE 1.4`).

### A4. La sección "Nota para quien importe" no corta de verdad

Hoy `isImporterNoteSection` solo hace `flushCurrent()` y pone `currentHeading = nil`, pero el
bucle sigue evaluando los párrafos siguientes. En SA 1 el tercer párrafo de esa sección dice
"…más una quinta evaluación tipo fórmula con la línea de **calificación final** de la cabecera de
este documento." → `isGradingLine` lo acepta y **machaca `gradingFormula`** con una nota interna.

**Fix**: bandera `reachedImporterNotes`; a partir de ahí se ignora el resto del documento.

### A5. Las anotaciones narrativas se pierden

La guía de autoría promete (§9) que todo párrafo que no sea tabla/ítem/pregunta se conserva
como nota del instrumento. En el código, `pendingParagraphs` solo se usa para extraer ítems de
checklist y preguntas de quiz; `note` se rellena únicamente con la cadena fija
`"Auxiliar o sin puntuación computable detectada"`. Se pierden textos con información real de
momento de recogida ("Momento único: Sesión 2…", "Escala: 1-4 … la nota final es la media de los
3 momentos").

**Fix**: acumular los párrafos no consumidos como `note` (unidos con `\n`), anteponiendo el
aviso de "auxiliar" cuando corresponda.

### A6. Las checklists con peso no puntúan (crítico)

`defaultScoreStrategy` devuelve `.none` para `.checklist`, así que `countsTowardAverage` es
`false` aunque el documento les asigne peso. Impacto real:

- **SA 4 (Primeros Auxilios)**: `Comprehension Checklist 10%` + `Checklist PAS/RICE 25%` +
  `Checklist de vendaje 15%` = **50 % de la nota** no computa.
- **SA 4b**: `Autoevaluación individual 5%` + `Coevaluación de equipo 5%`.
- **SA 2**: `Technical Progress Passport 10%`.

**Fix**: si `kind == .checklist`, hay ítems y `weightPercent > 0` → `.checklistProportional`.
`submissionChecklist` y `teacherObservation` siguen en `.none` (son requisito de entrega y
registro de apoyo; en los documentos reales nunca llevan `%`).

### A7. Rejillas de observación sin la marca "1-4"

`hasObservationScale1To4` exige que la cabecera contenga "1" y "4". SA 2 usa `Note` y
`Final mark` como última columna → `Game Application Grid (15 %)` se queda sin estrategia de
puntuación.

**Fix**: si la rejilla tiene peso y su última columna de cabecera es de tipo nota
(`nota`/`note`/`mark`/`score`) sin escala explícita, asumir escala 1-4 y añadir un aviso
("Se asume escala 1-4 en «…»; revísalo si el documento usa otra escala").

### A8. El aviso de descuadre de pesos está desactivado en la práctica

```swift
if weightedTotal > 0, abs(weightedTotal - 100) > 0.5, gradingFormula == nil { … }
```

Todos los documentos reales llevan línea de calificación final, así que `gradingFormula != nil`
siempre y **el aviso nunca se emite**. Es exactamente el aviso que habría delatado A1/A2.

**Fix**: (a) emitir el aviso siempre que la suma se desvíe de 100; (b) añadir verificación
cruzada: cada término `Texto (NN%)` de la fórmula debe emparejar por substring normalizado con
el título de algún instrumento detectado; los que no emparejen se listan en un aviso
("La fórmula menciona «Proyecto de organización sostenible del torneo» pero no se ha detectado
ningún instrumento con ese nombre").

### A9. Quiz: opciones y detección

- SA 1: `Una bebida con mucha cafeína y azúcar antes de EF puede afectar a: sueño / FC /
  hidratación / todas.` → se reconoce como pregunta, pero `optionsFromSlashList` exige un `?`
  para extraer opciones, así que se importa **sin opciones**. Fix: si no hay `?`, usar el último
  `:` como punto de corte.
- SA 6: `Cuestionario de cierre y reflexión final - Sesión 8` no es encabezado (no hay palabra
  clave) → sus 4 preguntas se cuelgan del instrumento anterior (`Checklist final de entrega`) y
  se convierten en **ítems falsos de checklist**. Lo arregla A2 (palabra clave `cuestionario`).

---

## Bloque B — Importador de secuencia de sesiones

### B1. El parser es ciego a las tablas (crítico)

`LearningSituationSessionSequenceDocumentImportService.readParagraphs` usa `WordParagraphReader`,
que aplana **todos** los `w:p`, incluidos los de dentro de las celdas. Solo SA 1 usa el formato
de párrafos con etiquetas (`Objetivo:`, `Criterios:`, `Material:`, `Evidencia:`, `Bloque 1 (45’):`).
Las 9 carpetas restantes (SA 2, 3, 4, 4b, 5, 6 y los 4 documentos de cierre) usan tablas:

```
Session 1 — Introduction to Ultimate Frisbee & Basic Techniques
TABLA ficha 6x2:  Item | Detail
                  Specific objective | Understand Ultimate Frisbee as a non-contact…
                  Criteria worked | 2.1
                  Saberes básicos worked | …
                  Materials | 1 frisbee per pair, 8 cones…
                  Group organisation | …
SIMPLE version (30’ effective …)
TABLA horaria 7x6: Time | Phase | Activity | Teacher role | Student role | Evidence
DOUBLE version (90’ useful …)
TABLA horaria 5x6: …
```

Resultado actual: objetivo, criterios y material **vacíos** (las celdas no tienen `:`), y un
desarrollo troceado en secciones absurdas (una por celda de tiempo, con las celdas contiguas
como líneas sueltas).

**Fix**: leer bloques (párrafo/tabla) como hace el servicio de instrumentos y soportar los dos
formatos:

- **Formato A (SA 1)**: el actual, con etiquetas en párrafos. No debe romperse.
- **Formato B (resto)**: tabla ficha `etiqueta | valor` (sinónimos: `Specific objective`/
  `Objetivo específico`, `Criteria worked`/`Criterios`, `Saberes básicos worked`, `Materials`/
  `Materiales`, `Group organisation`/`Organización`) + tablas horarias, que se convierten en
  secciones de desarrollo con una línea legible por fila
  (`0’-3’ · Entry — Fast entry, name the day's focus… (Evidencia: —)`).
- Secciones finales del formato B que deben conservarse (como secciones de desarrollo o
  adaptaciones, según corresponda): `Guiding questions`, `Difficulty variants`, `Adaptations`
  (→ `adaptations`), `Evidence collected`, `Assessment instrument`, `Closure`.

### B2. Encabezados: separadores y tipo en plural

- `Session 1. Icebreakers, safety and healthy-habits quiz` → el `.` no está en el juego de
  separadores, así que el título se guarda como `. Icebreakers, safety and healthy-habits quiz`
  (punto inicial). Afecta a las 4 carpetas de cierre, SA 3, SA 4 y SA 6.
- `Sesiones 3 y 5 - Dobles: Entrenamiento…` → el recorte de tipo solo contempla
  `Simple|Double|Doble` en singular, así que el título queda como
  `Dobles: Entrenamiento de fuerza-resistencia y Coach`.
- `Session 7 (NEW) — Designing the Inclusive Tournament` → título `(NEW) — Designing…`.

**Fix**: aceptar `.`, `—`, `–`, `-`, `:` como separador tras el número; recortar
`Simple|Double|Doble` con plural opcional; limpiar marcas de anotación tipo `(NEW)`/`(nueva)`.

### B3. Sesión fantasma por falso positivo

En `00d - Cierre de Curso` el párrafo de prosa
`Session 3 finishes the panel and starts planning the final event.` matchea el patrón de
cabecera y genera una **sesión 3 duplicada** (6 fichas para 5 sesiones), robándole el cuerpo a
la sesión real.

**Fix**: exigir que tras el número aparezca un separador explícito (`.`/`-`/`—`/`–`/`:`) o que
la línea termine ahí; y descartar líneas que terminen en `.` y superen ~90 caracteres de prosa.

### B4. Criterios: troceo por comas y numeración valenciana

`Criterios: Criteri 1.1, Criteri 1.2, Criteri 3.2 (se trabajan, no se corrigen todavía).`
se parte por comas y produce los criterios falsos `Criteri 3.2 (se trabajan` y
`no se corrigen todavía)`. Además los documentos alternan `CE 1.1` (instrumentos), `Criterio 1.1`
(SA), `Criteri 1.1` (sesiones de SA 1) y `2.1` a secas (fichas en inglés).

**Fix**: extraer los códigos con expresión regular
(`(?:CE|Criteri|Criterio|Criterion)?\s*\d+\.\d+`) y normalizarlos siempre a `CE X.X`;
descartar el texto entre paréntesis.

### B5. Versiones SIMPLE y DOBLE de la misma sesión

En el formato B cada sesión trae dos versiones (el centro trabaja los grupos en espejo).
Decisión: **no** duplicar sesiones. Se generan dos secciones de desarrollo
`Versión simple (30′)` y `Versión doble (90′)`; `sessionType` refleja las versiones presentes y
`effectiveMinutes` toma la versión simple cuando existan las dos, con un aviso explícito
("La sesión N define versión simple y doble; se han tomado 30′. Ajusta el tipo si este grupo
tiene sesión doble."). Sin este cambio, `inferredMinutes` suma los tramos de **ambas** versiones
y devuelve minutos imposibles.

### B6. Minutos por tipo

`defaultMinutesByType` exige la palabra `minutos|minutes|min`. Los documentos usan
`Simple (30’ effective)` / `Double (90’ useful)`. **Fix**: aceptar `’`, `'`, `′` y las palabras
`effective`/`useful`/`útiles`/`efectivos`.

---

## Bloque C — Importador de la programación didáctica (SA)

### C1. Ficha técnica en tabla

SA 3 pone toda la ficha (`Etapa`, `Curso`, `Materia`, `Temporalización`, `Trimestre`, `Centro`)
en una tabla 12x2. `metadataValue` exige un `:` en el párrafo → **todos los metadatos vacíos**.
**Fix**: leer bloques y aceptar pares `etiqueta | valor` de tabla además de `Etiqueta: valor`.

### C2. Sinónimos que faltan

| Campo | Texto real que hoy no se reconoce |
|---|---|
| Justificación | `2. Justificación y pregunta guía` (la lista solo tiene `justification` en inglés) |
| Reto / pregunta | `Pregunta guía:` (SA 5), `Reto inicial` (SA 4b, SA 6) |
| Trimestre | `Evaluación: 2ª evaluación` (SA 4b) |
| Duración | ya funciona (`Duración:`), mantener |

### C3. Criterios en tabla y numeración

SA 3 y SA 5 ponen los criterios en tablas (3x3 y 4x3) → se pierden. Además `criterionDrafts`
mete como criterio el propio encabezado de sección (`Criterios de evaluación y evidencias`), y
`competencies` incluye el encabezado `Competencias específicas`. **Fix**: soportar criterios en
tabla, normalizar `Criteri`/`Criterion`/`Criterio` → `CE X.X` y descartar los párrafos que sean
encabezado de sección (sin código de criterio ni texto tras `:`).

### C4. Ponderaciones no detectadas

El filtro de `evaluationItems` exige que el párrafo con `%` contenga `criterio`, `criterion`,
`total`, `ce ` o `ce.`. SA 1 escribe su bloque de evaluación con la forma valenciana
`Criteri 1.1 Diseño del plan - 40%: …` → **ninguna ponderación se detecta** y salta el aviso
"No se han reconocido ponderaciones de evaluación". **Fix**: añadir `criteri` al filtro y aceptar
también los párrafos que estén bajo un encabezado `Sistema de evaluación`/`Evaluación (resumen)`.

---

## Bloque D — Mejoras de producto

### D1. Porcentaje de ponderación en la cabecera de la columna del cuaderno

`ensureNotebookColumnForAssessmentInstrument` guarda `weight = weightPercent / 100` (0,4 para un
instrumento del 40 %), y `columnWeightBadge` (`NotebookModuleGridCells.swift`) lo pinta como
`×0,4`, que para el docente no significa nada. **Fix**: cuando `0 < weight < 1`, mostrar el
badge como porcentaje (`40%`) en lugar de `×0,4`, manteniendo `×N` para los multiplicadores
enteros y `no cuenta` para las excluidas. Actualizar también la etiqueta de accesibilidad.

Dejar constancia en el changelog de la limitación conocida (no se cambia ahora): si en la misma
pestaña conviven columnas importadas con peso porcentual (0,4) y columnas manuales con peso ×1,
las importadas pesan mucho menos de lo que sugiere su porcentaje.

### D2. La fórmula de calificación se parsea y se tira

`gradingFormula` no se usa en ninguna vista. **Fix (alcance contenido)**: mostrarla en la hoja
de revisión de instrumentos (`LearningSituationsWorkspaceView`), junto al resumen de pesos, y
usarla para la verificación cruzada de A8. No se crea todavía la columna calculada.

### D3. Documentación del contrato de importación

- Actualizar `~/Desktop/Programaciones/Knowledge/estructuras/GUIA_AUTORIA_DOCX_INSTRUMENTOS.md`
  al comportamiento nuevo (hoy documenta una regla de "≤70 caracteres" que el código no aplica —
  usa ≤10 palabras—, promete palabras clave `test`/`cuestionario` que no existían y opciones de
  quiz por `/` sin `?` que no funcionaban).
- Añadir en el repo `docs/importacion_documentos_sa.md` con el contrato de los **tres**
  documentos (SA, sesiones, instrumentos), que hoy no está documentado en ningún sitio.

---

## Orden de trabajo y commits

Un commit atómico por bloque funcional, cada uno con su entrada en `docs/CHANGELOG.md`
(sección `## Unreleased`) dentro del **mismo** commit:

1. `fix(import): reconocer todos los instrumentos de evaluación de los DOCX reales` (A1-A4, A9)
2. `fix(import): hacer computables las checklists y rejillas con ponderación` (A6, A7)
3. `fix(import): avisar de pesos y términos de fórmula sin instrumento` (A5, A8, D2)
4. `feat(import): leer las sesiones en formato de tabla` (B1, B5, B6)
5. `fix(import): sanear cabeceras y criterios de la secuencia de sesiones` (B2, B3, B4)
6. `fix(import): leer la ficha técnica y los criterios en tabla de la SA` (C1-C4)
7. `feat(cuaderno): mostrar la ponderación como porcentaje en la cabecera de columna` (D1)
8. `docs(import): documentar el contrato de los DOCX de situaciones de aprendizaje` (D3)

## Verificación exigida

- `xcodegen generate` (si se toca `project.yml`) y build real del target macOS/iOS con
  `DEVELOPER_DIR` apuntando al Xcode de `~/Downloads` (ver memoria del proyecto). Si el build no
  se puede ejecutar, decirlo explícitamente en el PR — no marcar la casilla.
- Auditoría sobre los 30 DOCX reales de `~/Desktop/Programaciones/output/…`: dejar en el PR la
  tabla instrumento a instrumento (detectados / peso / tipo / estrategia) por SA, antes y después.
- Comprobar que SA 1 (formato de párrafos) **no** se degrada al añadir el soporte de tablas.

## Archivos que se van a tocar

- `kmp/iosApp/AppleShared/LearningSituationAssessmentInstrumentsImportService.swift`
- `kmp/iosApp/AppleShared/LearningSituationDocumentImportService.swift`
- `kmp/iosApp/App/LearningSituationsWorkspaceView.swift` (fórmula en la hoja de revisión)
- `kmp/iosApp/App/NotebookModuleGridCells.swift` (badge de porcentaje)
- `kmp/iosApp/App/KmpBridge.swift` — **archivo protegido por `AGENTS.md`**; se toca solo si hace
  falta para D1/A6, con autorización explícita del usuario en esta tarea.
- `docs/CHANGELOG.md`, `docs/importacion_documentos_sa.md`
- `~/Desktop/Programaciones/Knowledge/estructuras/GUIA_AUTORIA_DOCX_INSTRUMENTOS.md` (fuera del repo)
