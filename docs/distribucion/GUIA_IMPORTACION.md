# Cómo preparar tus documentos para Cuaderno Vivo

Cuaderno Vivo puede leer tus documentos y rellenar la app por ti: el horario, las listas de alumnado, las situaciones de aprendizaje (SA), sus sesiones y sus instrumentos de evaluación.

Para que funcione, cada documento tiene que seguir una estructura concreta. Aquí la tienes explicada, con un ejemplo y un **prompt listo para copiar** en cualquier IA (ChatGPT, Claude, Gemini...) para que adapte tus documentos.

> Antes de importar, la app siempre te enseña una vista previa. Nada se guarda hasta que lo confirmas.

## Índice

1. [Horario](#1-horario)
2. [Lista de alumnado](#2-lista-de-alumnado)
3. [Correos del alumnado (opcional)](#3-correos-del-alumnado-opcional)
4. [Situación de aprendizaje](#4-situación-de-aprendizaje)
5. [Sesiones de la SA](#5-sesiones-de-la-sa)
6. [Instrumentos de evaluación](#6-instrumentos-de-evaluación)
7. [Consejos para usar la IA](#7-consejos-para-usar-la-ia)

---

## 1. Horario

**Dónde se importa:** en los primeros pasos o en la configuración del horario docente, botón **Importar horario**.
**Archivo:** Excel (`.xlsx`) o `.csv`. Puedes combinar hasta 3 archivos.

### Estructura

- Una fila de cabecera con una columna **Horas** (también vale `Hora`, `Franja`, `Hores`) y las cinco columnas **Lunes, Martes, Miércoles, Jueves, Viernes** (también en valenciano: `Dilluns`... `Divendres`). Tienen que estar los cinco días.
- Debajo, una fila por franja. En la columna Horas, el tramo escrito así: **`De 8:00 a 8:55`**.
- En cada celda, **`MATERIA:GRUPO`**, por ejemplo `EFI:1ESOA`.
  - Dos clases a la vez en la misma franja: sepáralas con `/`, por ejemplo `EFI:1ESOA / EFI:1ESOB`.
  - Celda vacía = hora libre.
  - Si el código de materia empieza por `TUT`, la franja cuenta como tutoría.
- Al final, opcional, una leyenda: una fila con la palabra **Materias** y debajo una línea por código, `EFI: Educación Física`.

### Ejemplo

| Horas | Lunes | Martes | Miércoles | Jueves | Viernes |
|---|---|---|---|---|---|
| De 8:00 a 8:55 | EFI:1ESOA | | EFI:2ESOB | | TUT:2ESOB |
| De 8:55 a 9:50 | EFI:1ESOB | EFI:1ESOA | | EFI:2ESOB | EFI:1ESOB |
| De 11:00 a 11:25 | | | | | |
| Materias | | | | | |
| EFI: Educación Física | | | | | |
| TUT: Tutoría | | | | | |

### Prompt

```text
Convierte mi horario docente en una tabla con esta estructura EXACTA, para importarla en una app:

- Primera fila (cabecera): Horas | Lunes | Martes | Miércoles | Jueves | Viernes
- Una fila por franja horaria. En la columna Horas escribe el tramo así: "De 8:00 a 8:55" (con "De" y "a", horas en formato HH:mm).
- En cada celda escribe MATERIA:GRUPO, sin espacios dentro del grupo. Ejemplo: EFI:1ESOA.
  - Usa un código corto de materia en mayúsculas (EFI, MAT, LEN...).
  - Si en la misma franja hay dos grupos, sepáralos con " / ".
  - Las tutorías empiezan por TUT (ejemplo TUT:2ESOB).
  - Si no tengo clase, deja la celda vacía. No escribas "Libre", "Guardia" ni nada parecido.
- Al final añade una fila que diga solo "Materias" y debajo una fila por código con el formato "CÓDIGO: Nombre completo".

No inventes clases. Si algo no se entiende, márcalo con [REVISAR].
Devuélvelo como tabla que pueda pegar en Excel.

Mi horario:
[PEGA AQUÍ TU HORARIO]
```

---

## 2. Lista de alumnado

**Dónde se importa:** Alumnado > **Importar alumnado** (o en los primeros pasos).
**Archivo:** Excel (`.xlsx`) o `.csv`. También puedes escribir los nombres a mano en los primeros pasos.

### Estructura

- **Las 8 primeras filas con texto son la cabecera** y no se leen como alumnos. Úsalas para el nombre del centro y estas dos líneas, en la columna A:
  - `Clase: 1º ESO A`
  - `Curso escolar: 2026-2027`
  - Rellena el resto de filas de cabecera con cualquier texto. Las filas vacías no cuentan: si dejas huecos, la app se come alumnos.
- **Desde la fila 9**, un alumno por fila:
  - Columna A: el número de lista con punto, `1.`, `2.`, `3.`...
  - Columna B: **APELLIDO1 APELLIDO2 NOMBRE**, en ese orden.
- La app toma las **dos primeras palabras como apellidos** y el resto como nombre. Si alguien tiene un solo apellido o un apellido compuesto («De la Fuente»), corrígelo en la vista previa.

### Ejemplo

| | A | B |
|---|---|---|
| 1 | IES Ejemplo | |
| 2 | Listado de clase | |
| 3 | - | |
| 4 | - | |
| 5 | Clase: 1º ESO A | |
| 6 | Curso escolar: 2026-2027 | |
| 7 | - | |
| 8 | Nº | Alumno/a |
| 9 | 1. | GARCÍA LÓPEZ ANA MARÍA |
| 10 | 2. | PÉREZ MARTÍN JUAN |

### Prompt

> **No pegues listas reales de alumnos en una IA en la nube.** Son datos personales de menores. Usa este prompt para que la IA te explique cómo transformar tu lista en Excel, sin enseñarle los nombres.

```text
Tengo en Excel una lista de alumnado con este formato: [DESCRIBE LAS COLUMNAS, POR EJEMPLO: "columna A nombre, columna B primer apellido, columna C segundo apellido"].

Necesito convertirla a este formato para importarla en una app:
- Filas 1 a 8: cabecera. En la fila 5, columna A: "Clase: [GRUPO]". En la fila 6, columna A: "Curso escolar: [CURSO]". El resto de filas de cabecera con un guion "-" (no pueden quedar vacías).
- Desde la fila 9: columna A el número de lista con punto ("1.", "2."...), columna B "APELLIDO1 APELLIDO2 NOMBRE" en mayúsculas y separado por espacios.

Explícame paso a paso cómo hacerlo en Excel con fórmulas (CONCAT, MAYUSC...), sin que tenga que enviarte los nombres.
```

---

## 3. Correos del alumnado (opcional)

Sirve para enviar enlaces de entrega a cada alumno.

**Dónde se importa:** Alumnado > **Importar correos de alumnos**.
**Archivo:** Excel (`.xlsx`) o `.csv`.

### Estructura

- Columna A: el correo, con la forma **`nombre.apellido@dominio`** (vale con prefijo `a.` delante y con dos apellidos: `a.ana.garcia.lopez@centro.es`). La app empareja cada correo con el alumno por el nombre que lleva dentro.
- Columna B (opcional): el grupo, por ejemplo `1º ESO A`, para afinar el emparejamiento.
- Las filas cuya columna A diga «correo» o «listado» se tratan como cabecera.

---

## 4. Situación de aprendizaje

**Dónde se importa:** Situaciones de aprendizaje > botón **Importar** (documento Word). Puedes elegir varios a la vez.
**Archivo:** Word (`.docx`).

### Estructura

La app lee el documento de arriba abajo, párrafo a párrafo y tabla a tabla. Reconoce estas partes por su etiqueta:

- **Ficha técnica.** Cada dato como `Etiqueta: valor` en su línea, o en una tabla de dos columnas `Campo | Dato`:
  - `Etapa:`, `Curso:`, `Materia:`, `Centro:`, `Trimestre:` (o `Evaluación: 2ª evaluación`), `Temporalización:` (o `Duración:`).
- **Justificación.** Un título `Justificación` y el texto debajo.
- **Reto.** `Pregunta motriz:` y el texto en la misma línea. Ponlo justo después de la justificación: es lo que marca dónde acaba.
- **Producto final.** `Producto final:` y el texto.
- **Competencias específicas.** Una por párrafo, empezando por el código: `CE1. Resolver situaciones motrices...`
- **Criterios de evaluación.** Mejor en una tabla con cabecera `Criterio | Enunciado | Rol en esta SA`; o un párrafo por criterio: `Criterio 1.1: ...`, y si quieres, debajo, `Evidencia: ...`.
- **Saberes básicos.** Un título `Saberes básicos` y la lista debajo.
- **Metodología.** Un título `Metodología y estrategias activas` (con esas palabras) y el texto debajo.
- **Atención a la diversidad.** Un título con ese nombre y el texto. Marca dónde acaba la metodología.
- **Evaluación.** Un título `Sistema de evaluación` y una línea por criterio con su peso: `Criterio 1.1 - 40%: rúbrica del producto final`.

Escribe los códigos de criterio como `1.1`, `CE 1.1` o `Criterio 1.1`: la app los entiende todos.

### Prompt

```text
Reescribe esta situación de aprendizaje con esta estructura EXACTA, para importarla en una app. Mantén mi contenido; no inventes nada. Si falta un apartado, escribe [COMPLETAR].

1. Ficha técnica, una línea por dato con el formato "Etiqueta: valor":
   Etapa: / Curso: / Materia: / Centro: / Trimestre: / Temporalización:
2. Un título "Justificación" y debajo el texto.
3. "Pregunta motriz:" seguido del reto en la misma línea.
4. "Producto final:" seguido de la descripción en la misma línea.
5. Un título "Competencias específicas" y debajo un párrafo por competencia que empiece por su código: "CE1. ...".
6. Un título "Criterios de evaluación" y una tabla con cabecera: Criterio | Enunciado | Rol en esta SA. En la columna Criterio, solo el código (1.1, 2.3...).
7. Un título "Saberes básicos" y debajo la lista.
8. Un título "Metodología y estrategias activas" y debajo el texto.
9. Un título "Atención a la diversidad" y debajo el texto.
10. Un título "Sistema de evaluación" y debajo una línea por criterio con este formato: "Criterio 1.1 - 40%: instrumento con el que se evalúa". Los porcentajes deben sumar 100 %.

Devuélvelo listo para pegar en Word, con los títulos como encabezados.

Mi situación de aprendizaje:
[PEGA AQUÍ TU SA]
```

---

## 5. Sesiones de la SA

**Dónde se importa:** en la SA, al **programar las sesiones** (botón para elegir el Word de sesiones).
**Archivo:** Word (`.docx`), uno por SA.

### Estructura

- **Un título por sesión** que empiece por `Sesión` y el número, seguido de un separador (`.`, `-`, `:`) y el título:
  - `Sesión 1 - Normas, seguridad y calentamiento`
  - `Sesión 2: Juegos de cooperación`
  - Si una ficha vale para dos sesiones: `Sesiones 3 y 4 - ...`
- **Ficha de la sesión**, debajo del título, en una tabla de dos columnas `Etiqueta | Valor`, con una fila por dato:
  - `Objetivo`
  - `Criterios`, con los códigos (`1.1, 2.3`)
  - `Saberes básicos`
  - `Material`
  - `Evidencia`
- **Desarrollo**, en una tabla con esta cabecera:

  | Tiempo | Fase | Actividad | Papel del docente | Papel del alumno | Evidencia |
  |---|---|---|---|---|---|
  | 0'-10' | Calentamiento | Juego de persecución por parejas... | Explica y modela... | Corren y cambian de rol... | Participa con seguridad |

  O, sin tabla, un párrafo por bloque que empiece por el tramo de tiempo: `0'-10': Calentamiento. ...`
- **Sesión simple y doble (opcional).** Si tienes dos versiones de la misma sesión, pon antes de cada tabla un párrafo como `Versión simple (30' útiles)` y `Versión doble (90' útiles)`. La app las guarda juntas, sin duplicar la sesión.
- **Cierre (opcional).** Títulos que se conservan: `Preguntas guía`, `Variantes de dificultad`, `Adaptaciones`, `Evidencias recogidas`, `Instrumento de evaluación`, `Cierre`.

Cuanto más completa sea cada actividad (qué hace el docente, qué hace el alumnado, cuánto dura), más útil será la ficha durante la clase. La app guarda el texto completo, sin resumirlo.

### Prompt

```text
Reescribe las sesiones de esta situación de aprendizaje con esta estructura EXACTA, para importarlas en una app. Mantén mi contenido; no inventes actividades. Si falta algo, escribe [COMPLETAR].

Para cada sesión:
1. Un título: "Sesión N - Título de la sesión" (N es el número; usa siempre el guion como separador).
2. Debajo, una tabla de dos columnas (Etiqueta | Valor) con estas filas:
   Objetivo / Criterios (solo códigos, por ejemplo 1.1, 2.3) / Saberes básicos / Material / Evidencia
3. Una tabla de desarrollo con esta cabecera exacta:
   Tiempo | Fase | Actividad | Papel del docente | Papel del alumno | Evidencia
   - Tiempo en formato 0'-10', 10'-25'...
   - En Actividad, Papel del docente y Papel del alumno escribe frases completas que otro docente pueda seguir sin conocer la sesión.
   - Reserva tiempo para formar grupos, repartir material y recoger.
4. Si la sesión tiene versión simple y doble, pon un párrafo "Versión simple (30' útiles)" antes de su tabla y "Versión doble (90' útiles)" antes de la otra.
5. Al final de la sesión, si los tengo, apartados con estos títulos: Adaptaciones / Variantes de dificultad / Cierre.

Devuélvelo listo para pegar en Word.

Mis sesiones:
[PEGA AQUÍ TUS SESIONES]
```

---

## 6. Instrumentos de evaluación

**Dónde se importa:** en la SA, en **Evaluación** (botón para elegir el Word de instrumentos). La app crea las columnas y las rúbricas en el Cuaderno.
**Archivo:** Word (`.docx`), uno por SA.

### Estructura

- **Un título numerado por instrumento**, con el tipo, los criterios y el peso, separados por guiones:
  - `1. Rúbrica del producto final - CE 2.1 - 40%`
  - `2. Lista de cotejo de seguridad - CE 1.1 - 20%`
  - `3. Escala de valoración de la participación - CE 3.2 - 20%`
  - `4. Autoevaluación - CE 4.1 - 20%`
- **El tipo sale de las palabras del título:**
  - `Rúbrica` → rúbrica con niveles.
  - `Lista de cotejo` o `Checklist` → lista de sí/no. La nota es el porcentaje de casillas marcadas.
  - `Escala de valoración`, `Observación sistemática` o `Diana` → rejilla de observación (escala 1-4).
  - `Autoevaluación` o `Coevaluación` con una tabla de rúbrica de 4 niveles → la rellena el alumnado y puntúa.
  - `Quiz` → preguntas.
  - `Producto final` o `Entrega` → lista de requisitos de entrega, sin nota.
- **Debajo del título, una tabla.** Para una rúbrica:

  | Criterio | Insuficiente | Suficiente | Notable | Sobresaliente |
  |---|---|---|---|---|
  | Planificación (30%) | No planifica... | Planifica con ayuda... | Planifica solo... | Planifica y mejora... |
  | Ejecución (70%) | ... | ... | ... | ... |

  - La primera fila son los niveles: sus nombres pasan a la app tal cual.
  - Cada fila siguiente es un criterio. Si pones el peso entre paréntesis (`(30%)`), la app lo usa; si no, todos pesan igual.
- **Lista de cotejo:** una tabla con una primera fila de cabecera (`Ítem`) y debajo un ítem observable por fila.
- **Escala de valoración:** una tabla con cabecera `Indicador | 1 | 2 | 3 | 4` y un indicador por fila.
- **Calificación final (opcional):** una línea `Calificación final: Rúbrica del producto (40%) + Lista de cotejo (20%) + ...`. La app comprueba que cuadra con los instrumentos.
- Los pesos de todos los instrumentos deben **sumar 100 %**. Si no, la app te avisa.

### Prompt

```text
Reescribe los instrumentos de evaluación de esta situación de aprendizaje con esta estructura EXACTA, para importarlos en una app. Mantén mi contenido; no inventes descriptores. Si falta algo, escribe [COMPLETAR].

Para cada instrumento:
1. Un título numerado con este formato: "N. Tipo y nombre - CE X.X - NN%".
   - El tipo debe aparecer con una de estas palabras: Rúbrica, Lista de cotejo, Escala de valoración, Autoevaluación, Coevaluación, Quiz.
   - Si evalúa varios criterios: "- CE 1.2 y 1.4 - 35%".
2. Debajo, una tabla:
   - Rúbrica, autoevaluación o coevaluación: primera fila "Criterio | Insuficiente | Suficiente | Notable | Sobresaliente" (4 niveles). Una fila por criterio. Si los criterios tienen peso distinto, ponlo entre paréntesis en la primera columna, por ejemplo "Planificación (30%)".
   - Lista de cotejo: primera fila "Ítem" y debajo un ítem observable por fila.
   - Escala de valoración: primera fila "Indicador | 1 | 2 | 3 | 4" y una fila por indicador.
3. Al final, una línea: "Calificación final: nombre del instrumento (NN%) + nombre del instrumento (NN%) + ...".

Los porcentajes de todos los instrumentos deben sumar 100 %.
Devuélvelo listo para pegar en Word, con las tablas como tablas.

Mis instrumentos:
[PEGA AQUÍ TUS INSTRUMENTOS]
```

---

## 7. Consejos para usar la IA

- **Pide que no invente.** Los prompts ya lo dicen; si aun así añade cosas, repíteselo.
- **Revisa los `[COMPLETAR]` y `[REVISAR]`** antes de importar.
- **Pega el resultado en Word** con «Mantener formato de origen» para que las tablas sigan siendo tablas.
- **Un documento por cosa:** la SA, las sesiones y los instrumentos van en tres archivos Word distintos.
- **Nunca pegues datos reales del alumnado** (nombres, notas, informes) en una IA en la nube.
- Si la vista previa de la app muestra algo raro, corrige el Word y vuelve a importarlo: no se guarda nada hasta que confirmas.
