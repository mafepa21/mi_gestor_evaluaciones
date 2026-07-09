# Guía de autoría: DOCX de instrumentos de evaluación

Instrucciones para el agente/proceso que redacta `instrumentos_evaluacion.docx` de cada
Situación de Aprendizaje, de forma que el importador de
`kmp/iosApp/AppleShared/LearningSituationAssessmentInstrumentsImportService.swift` lo
interprete sin errores y la app lo muestre perfectamente. Estas reglas reflejan el
parser real, no una interpretación libre: seguirlas al pie de la letra evita instrumentos
mal tipados, ítems fantasma o notas perdidas/duplicadas.

## 1. Título del documento

Primer párrafo del documento. Debe contener literalmente la frase
**"Instrumentos de evaluación"** (con o sin tilde). Se ignora automáticamente, úsalo
para dar contexto humano (ej. `SA 1: Pasaporte de Salud - Instrumentos de evaluación`).

## 2. Línea de calificación final (fórmula)

Un único párrafo que debe contener alguna de estas frases (sin importar mayúsculas/tildes):
`"calificación final"`, `"modelo de calificación"`, `"final SA grade"`, `"grading model"`.

Formato de cada término: `<Texto del término> (NN%)`, separados por `+`. Ejemplo real:

```
Calificación final de la SA: Nota SA = Rúbrica de diseño del plan (40%) + Rejilla de observación sistemática (35%) + Quiz de hábitos saludables (15%) + Rúbrica de Coach (10%)
```

**Regla crítica**: el `<Texto del término>` debe coincidir (contener o estar contenido)
con el **título exacto** de su instrumento correspondiente, o al menos compartir una
palabra distintiva con él. El emparejamiento se hace por substring normalizado
(sin tildes/mayúsculas); no hay IA en el matching. Si el término no comparte texto
reconocible con ningún título de instrumento, esa columna queda fuera de la fórmula
sin aviso visible. **La forma más segura es copiar literalmente el título del
instrumento (o su primera parte) dentro del paréntesis del término.**

## 3. Encabezados de instrumento

Dos formas válidas, **una por instrumento**, cada una en su propio párrafo:

**a) Numerado** (recomendado, más robusto):
```
N. Título del instrumento - CE X.X - NN%
```
- Debe empezar por `N.` o `N)` seguido de espacio.
- Debe contener al menos una palabra clave de instrumento (ver tabla del punto 4).
- `NN%` es el peso; se detecta el primer número seguido de `%` en la línea.
- `CE X.X` (opcional) es la etiqueta de criterio — **usa literalmente "CE"**, no
  "Criteri"/"Criterio" ni otra variante; solo "CE 1.1" o "CE1.2" se reconoce.
- El número, el `- CE X.X` y el `- NN%` se recortan automáticamente del título final.

**b) Sin numerar** (solo para instrumentos "especiales" tipo checklist final):
```
Título corto - Sesión N
```
- **Debe tener 70 caracteres o menos.** Es el límite que distingue un título de
  una frase de contexto; si lo superas, el párrafo se trata como texto narrativo
  normal (no como encabezado) y el instrumento se pierde.
- Debe contener una palabra clave (ver punto 4).

## 4. Palabras clave que activan un encabezado y su tipo (`kind`)

El tipo del instrumento se decide por estas palabras dentro del título (normalizado,
sin tildes, en minúsculas). Usa **una y solo una** familia por instrumento:

| Tipo final (`kind`) | Palabras que lo activan en el título |
|---|---|
| `submissionChecklist` (checklist de entrega, **no puntúa**) | `submission`, `entrega`, `producto final`, `final checklist` |
| `quizQuestions` (si el instrumento no tiene tabla) | `quiz`, `test`, `cuestionario` |
| `checklist` | `pasaporte`/`passport`, `checklist`, `lista de cotejo`, `lista de control`, `autoevaluación`, `coevaluación`, `safety`, `adjustment`, `tarea competencial` |
| `teacherObservation` | `docente`/`teacher`, `registro anecdótico`, `observación docente` |
| `observationGrid` (graduable, admite escala 1-4) | `rejilla`, `grid`, `observ...` (cualquier palabra con "observ", ej. **"observación sistemática"**), `log`, `record sheet`, `diagnóstic...`, `escala de valoración`, `diana de evaluación` |
| `rubric` (por defecto si nada de lo anterior encaja) | `rúbrica`/`rubric`, o simplemente no usar ninguna otra palabra clave |

Notas importantes:
- Para la **rejilla de observación graduable en 1-4**, usa literalmente
  **"Rejilla de observación sistemática"** (o "rejilla..."/"...observación...") en el
  título — **no** uses "observación docente", que es un tipo distinto (`teacherObservation`,
  sin nota automática).
- Para el **quiz**, no incluyas ninguna tabla junto al instrumento si quieres que se
  parsee como preguntas (`quizQuestions`); si añades una tabla, se interpretará como
  `checklist` en su lugar.
- Para la **checklist final de entrega** (no debe puntuar), usa un título corto (≤70
  car.) con "entrega" o "checklist final", **sin `%` de peso** en el encabezado.

## 5. Tabla de rúbrica (`rubric`)

- Fila 1 (cabecera): primera celda vacía o etiqueta; el resto son los **nombres de
  los niveles**, en orden ascendente (ej. `1-4 Insuficiente | 5-6 Suficiente | 7-8 Notable | 9-10 Sobresaliente`).
- Filas siguientes: una por criterio. Primera celda = nombre del criterio (puede
  incluir peso como `(25%)`, `(0.25)` o `(5 puntos)`, se detecta y se limpia del
  título automáticamente; si ningún criterio lleva peso explícito, se reparten
  a partes iguales). Resto de celdas = descriptor de ese criterio en cada nivel,
  en el mismo orden que la cabecera.

## 6. Tabla de rejilla de observación (`observationGrid`, graduable 1-4)

- Fila 1 (cabecera): primera celda = "Alumno/a" (o similar); resto = nombres de
  indicadores a observar; **la última columna debe contener literalmente "1-4"**
  en su nombre (ej. `Nota (1-4)`) — es la señal que activa la nota automática en
  escala 1-4. Sin esa marca, el instrumento se crea pero sin estrategia de puntuación.
- Filas siguientes: **una fila por "momento" de recogida** (ej. S3, S7, S9), con la
  primera celda (alumno) vacía en la plantilla y la **segunda celda con el nombre
  del momento** (ej. `S3 - inicio`) — ese texto es el que se usa como título del
  campo observado. No dejes la segunda celda vacía.

## 7. Preguntas de quiz (`quizQuestions`)

Cada pregunta es **un párrafo independiente** (no tabla) bajo el encabezado del quiz.
Debe cumplir **al menos una** de estas condiciones para reconocerse como pregunta
(si no cumple ninguna, se pierde como pregunta y pasa a ser solo una nota de contexto):

- Contiene `?` o `¿` → pregunta abierta o de opción múltiple.
- Contiene `____` (4 o más guiones bajos) → rellenar hueco.
- Contiene literalmente `"verdadero o falso"` (o `"true or false"`) → verdadero/falso.
- Termina en una lista de **2 o más opciones separadas por `/`** (ej.
  `"...puede afectar a: sueño / FC / hidratación / todas."`) → opción múltiple,
  aunque no lleve signo de interrogación.

Las opciones de respuesta se extraen automáticamente del texto separado por `/`.
No hay forma de indicar la respuesta correcta en el documento — el quiz se importa
como formulario, no con autocorrección real; no dependas de eso.

Frases puramente introductorias del quiz (ej. "Momento único: Sesión 8. Corrección
rápida...") deben ir en un párrafo aparte **antes** de las preguntas y sin cumplir
ninguna de las condiciones anteriores, para que queden como nota de contexto y no
como pregunta falsa.

## 8. Checklist (`checklist` / `submissionChecklist`)

Usa el marcador literal `- [ ] Texto del ítem.` para cada ítem, uno tras otro, en el
mismo párrafo o en párrafos distintos (ambas formas funcionan). Ejemplo real:

```
No puntúa por separado: es el requisito de entrega. - [ ] Diagnóstico inicial completo (S1). - [ ] Plan validado (S2).
```

- Todo el texto **antes del primer** `- [ ] ` se conserva como nota de contexto del
  instrumento (no se convierte en ítem).
- Cada `- [ ] ` seguido de texto hasta el siguiente marcador (o fin de párrafo) se
  convierte en un ítem independiente.
- También puedes usar tablas: la primera columna de cada fila (tras la cabecera)
  se toma como ítem.

## 9. Anotaciones narrativas (contexto, momento, aclaraciones)

Cualquier párrafo bajo un encabezado de instrumento que **no** sea tabla, ni ítem de
checklist, ni pregunta de quiz reconocida, se guarda tal cual como nota (`note`) visible
en la app junto al instrumento. Son bienvenidas y se preservan siempre.

**Advertencia clave**: si esa frase de contexto es corta (≤70 caracteres) y
menciona de pasada una palabra clave de la tabla del punto 4 (ej. "checklist",
"instrumento", "registro", "diagnóstico", "coevaluación", "observación"...), el
importador la confundirá con un **encabezado nuevo** y romperá el instrumento
completo (la tabla siguiente quedará mal asignada). Para evitarlo:
- Escribe las frases de contexto con normalidad, sin acortarlas artificialmente
  (una frase completa de 90+ caracteres es segura).
- Si necesitas una frase corta, evita esas palabras clave o añade contexto para
  superar los 70 caracteres.

## 10. Nota final para el importador (opcional, se ignora siempre)

Si quieres dejar comentarios dirigidos al desarrollador/importador que **no** deben
aparecer como anotación de ningún instrumento, empieza ese párrafo con:

```
Nota para quien importe esto...
```

(también válido: "Nota para el importador..."). A partir de ahí, todo el texto hasta
el final del documento se ignora por completo, sin arrastrarse al último instrumento.

## 11. Checklist rápido antes de entregar el documento

- [ ] El título del documento contiene "Instrumentos de evaluación".
- [ ] La línea de calificación final usa `Término (NN%) + Término (NN%) + ...` y
      cada término reutiliza literalmente parte del título de su instrumento.
- [ ] Los pesos suman 100% (o se acepta el aviso si no).
- [ ] Cada instrumento calificable tiene encabezado numerado con palabra clave y `%`.
- [ ] La checklist final de entrega tiene título corto (≤70 car.), sin `%`, con
      "entrega"/"checklist final" en el título.
- [ ] La rejilla de observación usa "rejilla de observación..." en el título y su
      tabla tiene "1-4" en la última columna de cabecera.
- [ ] El quiz no lleva tabla adjunta si quieres preguntas individuales, y cada
      pregunta cumple alguna de las 4 condiciones del punto 7.
- [ ] Las checklists usan `- [ ] item.` y el texto de contexto va antes del primer marcador.
- [ ] Ninguna frase de contexto corta (≤70 car.) contiene una palabra clave de instrumento.
- [ ] Si hay notas para el desarrollador, empiezan por "Nota para quien importe esto".
