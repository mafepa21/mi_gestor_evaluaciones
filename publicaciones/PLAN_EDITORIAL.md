# Plan Editorial para X (Twitter): Docencia & IA con Antigravity

Este documento es la hoja de ruta de contenidos para la cuenta de X. Recoge los hitos ya desarrollados en la app (desde el origen hasta hoy) y establece el orden para publicarlos antes de enlazar con el trabajo diario en tiempo real.

---

## 🧭 Hilo Conductor Permanente

Cada publicación debe reforzar, explícita o sutilmente, la premisa del proyecto:
> **Un docente de secundaria y Educación Física que decidió no atarse a apps comerciales de terceros y está creando su propia app nativa en Swift asistido por IA (Antigravity), compartiendo aprendizajes de aula y de desarrollo sin tecnicismos innecesarios.**

---

## 📊 Matriz de Publicaciones (Hitos ya desarrollados)

| # | Entrega / Tema | Gancho pedagógico | Hito técnico en `memoria` | Estado | Archivo borrador |
|---|---|---|---|---|---|
| **00** | **Manifiesto Fundacional** | Por qué decidí crear mi propia app nativa en Swift en vez de usar las comerciales | Origen del proyecto | ✅ Redactado | `2026-09-06-manifiesto-fundacional-app-docente.md` |
| **01** | **El laberinto del calendario y festivos** | Cuadrar festivos y exámenes de Bachillerato sin descuadrar la ESO | Avance 2026-09-04 (1º BAC y festivos) | ✅ Redactado | `2026-09-04-calendario-bachillerato-festivos.md` |
| **02** | **Del Word de 80 páginas a mi cuaderno en 1 clic** | Pasar la programación didáctica oficial (DOCX) sin teclear a mano | Avance 2026-09-02 (Importación DOCX Mislata) | ⏳ Pendiente | Por redactar |
| **03** | **Evaluar a 30 alumnos en una pista con un iPad** | Botones gigantes y atajos de teclado para condiciones de patio | Avance 2026-07-03 (Atajos rúbricas iPadOS) | ⏳ Pendiente | Por redactar |
| **04** | **El gran dilema de la media: ¿qué hacemos con la celda vacía?** | Explicar a las familias una nota justa cuando hay faltas justificadas | Avance 2026-06-05 (Desglose de la media) | ⏳ Pendiente | Por redactar |
| **05** | **Privacidad radical: las notas se quedan en mi red local** | Sincronizar iPad y Mac sin nubes privadas de terceros (RGPD) | Avance 2026-06-16 / 2026-06-28 (SyncLAN) | ⏳ Pendiente | Por redactar |
| **06** | **El miedo a que la tablet se apague en clase** | Guardado invisible e instantáneo celda a celda sin botón "Guardar" | Avance 2026-06-19 / 2026-08-13 (Debounce de celdas) | ⏳ Pendiente | Por redactar |
| **07** | **Grupos cooperativos en Educación Física sin duplicar listas** | Agrupar alumnos en equipos y calificar al vuelo en la pista | Avance 2026-06-01 / 2026-06-02 (Grupos de trabajo) | ⏳ Pendiente | Por redactar |
| **08** | **Medir la condición física para motivar, no para castigar** | Pruebas físicas con baremos de salud y superación personal | Avance 2026-06-11 (Módulo Condición Física) | ⏳ Pendiente | Por redactar |
| **09** | **Rúbricas LOMLOE que no te asfixian en burocracia** | Matrices de descriptores con toques rápidos y cálculo transparente | Avance 2026-06-03 (Consistencia de rúbricas) | ⏳ Pendiente | Por redactar |
| **10** | **La secuencia didáctica viva: cuando el trimestre se tuerce** | Arrastrar y adaptar sesiones planificadas sin romper criterios | Avance 2026-06-28 (Secuencia del Planificador) | ⏳ Pendiente | Por redactar |
| **11** | **IA local sin mandar datos de menores fuera del dispositivo** | Resúmenes de tutoría y tendencias usando Apple Intelligence en chip | Avance 2026-06-04 (Apple Intelligence LOMLOE) | ⏳ Pendiente | Por redactar |
| **12** | **"Oye Antigravity, no me gusta este botón": inmediatez docente** | De detectar una molestia en clase a tenerla resuelta esa misma tarde | Flujo continuo con Antigravity | ⏳ Pendiente | Por redactar |
| **13** | **Consejos para docentes que quieren perder el miedo a crear con IA** | La verdadera habilidad no es programar, sino definir el problema de aula | Balance de experiencia acumulada | ⏳ Pendiente | Por redactar |

---

## 📝 Fichas Detalladas de Contenido (Por desarrollar)

### Entrega 02: Del Word de 80 páginas al cuaderno en 1 clic
- **Gancho:** «¿Cuántas horas pasamos a principio de curso copiando y pegando criterios y sesiones desde el documento Word de la programación oficial al cuaderno de notas?»
- **El reto con Antigravity:** «Le pedí a la IA: 'Construye un importador que lea el DOCX oficial del departamento, identifique las Situaciones de Aprendizaje y las coloque en su sitio en mi app'.»
- **Impacto docente:** Una tarea que antes llevaba 3 tardes se resuelve en 30 segundos, sin errores de transcripción.
- **Llamada a la acción:** ¿Cómo gestionáis vosotros el paso de la programación oficial a vuestro día a día?

---

### Entrega 03: Evaluar a 30 alumnos en una pista con un iPad
- **Gancho:** «Las apps comerciales están pensadas para una oficina o una mesa con tranquilidad. En Educación Física tienes el sol reflejando en la pantalla, 30 chicos botando balones y cero tiempo para menús desplegables diminutos.»
- **El reto con Antigravity:** «Rediseñamos la vista de rúbricas para que con un toque o un atajo de teclado hardware en la funda del iPad califiques al vuelo sin desviar la mirada de la pista.»
- **Impacto docente:** Ergonomía y usabilidad real adaptada al contexto del aula activa.
- **Llamada a la acción:** ¿Qué interfaz de las apps que usáis os parece menos práctica para vuestra asignatura?

---

### Entrega 04: El gran dilema de la media y las celdas vacías
- **Gancho:** «Un alumno falta con justificante médico a una prueba. Si le pones un 0 es injusto; si dejas la celda vacía en Excel, a menudo la fórmula se descuadra o divide mal.»
- **El reto con Antigravity:** «Enseñé a mi app a distinguir entre celda sin calificar, ausencia justificada y suspenso, y añadí un panel que desglosa la media de forma explicable y pedagógica.»
- **Impacto docente:** Transparencia total en tutorías y reuniones con familias.
- **Llamada a la acción:** ¿Cómo gestionáis en vuestro centro las ausencias a pruebas evaluables?

---

### Entrega 05: Privacidad radical y soberanía de datos
- **Gancho:** «¿Alguna vez habéis leído la letra pequeña de dónde se guardan las notas, observaciones y fotos de vuestros alumnos en las apps comerciales que usamos?»
- **El reto con Antigravity:** «En lugar de pagar servidores externos en la nube, creamos SyncLAN: sincronización directa entre mi Mac y mi iPad en red local. Cero datos en servidores ajenos.»
- **Impacto docente:** Cumplimiento estricto del RGPD y tranquilidad ética total.
- **Llamada a la acción:** ¿Os preocupa la privacidad de los datos de vuestro alumnado en las plataformas en la nube?

---

## 🔄 Cómo incorporar los avances diarios futuros

A medida que vayamos realizando sesiones de trabajo en el proyecto:
1. Al terminar la tarea, se invoca la skill `post-x-docente`.
2. Se genera el archivo `publicaciones/YYYY-MM-DD-slug.md` con las dos opciones (tweet directo y mini-hilo).
3. Se añade una nueva fila a la tabla de este plan editorial en la sección de entregas en curso.
