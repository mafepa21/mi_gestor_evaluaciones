# Plan Editorial para X (Twitter): Docencia & IA con Antigravity, Codex y Claude

Este documento es la hoja de ruta de contenidos para la cuenta de X. Recoge los hitos desarrollados en la app (desde el origen hasta hoy) identificando con qué agente de IA se trabajó cada descubrimiento o funcionalidad, y establece el orden para publicarlos antes de enlazar con el trabajo diario en tiempo real.

---

## 🧭 Hilo Conductor Permanente

Cada publicación debe reforzar, explícita o sutilmente, la premisa del proyecto:
> **Un docente de secundaria y Educación Física que decidió no atarse a apps comerciales de terceros y está creando su propia app nativa en Swift asistido por un equipo de asistentes de IA (Claude para diseño y UX pedagógica, y Codex / Antigravity para ingeniería y código nativo), compartiendo aprendizajes de aula y de desarrollo sin tecnicismos innecesarios.**

---

## 🤖 El "Equipo Docente Virtual" de IAs

- **Claude (Claude Code / Claude Design):** El diseñador de interfaz y consultor de experiencia de usuario. Analiza la legibilidad de la pantalla bajo el sol de la pista, audita los menús para no saturar al docente y ayuda a descifrar la estructura pedagógica de documentos Word oficiales.
- **Codex / Antigravity:** El arquitecto de software e ingeniero de sistemas. Pica el código nativo en Swift y Kotlin Multiplatform (KMP), conecta bases de datos (SQLDelight), implementa la sincronización local privada y asegura que los cálculos y calendarios se ejecuten al instante sin perder datos.

---

## 📊 Matriz de Publicaciones (Hitos ya desarrollados)

| # | Entrega / Tema | Gancho pedagógico | Agente(s) de IA | Hito en `memoria` / Git | Estado | Archivo borrador |
|---|---|---|---|---|---|---|
| **00** | **Manifiesto Fundacional** | Por qué decidí crear mi propia app nativa en Swift con IA en vez de usar las comerciales | Ecosistema completo | Origen del proyecto | ✅ Redactado | `2026-09-06-manifiesto-fundacional-app-docente.md` |
| **01** | **El laberinto del calendario y festivos** | Cuadrar festivos y exámenes de Bachillerato sin descuadrar la ESO | **Codex / Antigravity** | Avance 2026-09-04 (1º BAC y festivos) | ✅ Redactado | `2026-09-04-calendario-bachillerato-festivos.md` |
| **02** | **Mi equipo virtual: Claude para diseñar y Antigravity para construir** | Cómo coordino a dos IAs distintas según sus fortalezas en el aula | **Tándem Claude + Antigravity** | Workflow transversal (ramas `claude/*` y `codex/*`) | ⏳ Pendiente | Por redactar |
| **03** | **Del Word de 80 páginas a mi cuaderno en 1 clic** | Pasar la programación didáctica oficial (DOCX) sin teclear a mano | **Tándem Claude + Codex** | `claude/sa-import-formato` + Avance 2026-09-02 | ⏳ Pendiente | Por redactar |
| **04** | **Evaluar a 30 alumnos en una pista con un iPad** | Botones gigantes y atajos de teclado para condiciones de patio | **Tándem Claude + Codex** | `claude/ui-analysis` + Avance 2026-07-03 | ⏳ Pendiente | Por redactar |
| **05** | **El gran dilema de la media: ¿qué hacemos con la celda vacía?** | Explicar a las familias una nota justa cuando hay faltas justificadas | **Codex / Antigravity** | Avance 2026-06-05 (Desglose de la media) | ⏳ Pendiente | Por redactar |
| **06** | **Privacidad radical: las notas se quedan en mi red local** | Sincronizar iPad y Mac sin nubes privadas de terceros (RGPD) | **Codex / Antigravity** | Avance 2026-06-16 / 2026-06-28 (SyncLAN) | ⏳ Pendiente | Por redactar |
| **07** | **El miedo a que la tablet se apague en clase** | Guardado invisible e instantáneo celda a celda sin botón "Guardar" | **Codex / Antigravity** | Avance 2026-06-19 / 2026-08-13 (Debounce de celdas) | ⏳ Pendiente | Por redactar |
| **08** | **Grupos cooperativos en Educación Física sin duplicar listas** | Agrupar alumnos en equipos y calificar al vuelo en la pista | **Codex / Antigravity** | Avance 2026-06-01 / 2026-06-02 (Grupos de trabajo) | ⏳ Pendiente | Por redactar |
| **09** | **Medir la condición física para motivar, no para castigar** | Pruebas físicas con baremos de salud y superación personal | **Codex / Antigravity** | Avance 2026-06-11 (Módulo Condición Física) | ⏳ Pendiente | Por redactar |
| **10** | **Rúbricas LOMLOE que no te asfixian en burocracia** | Matrices de descriptores con toques rápidos y cálculo transparente | **Tándem Claude + Codex** | `claude/ui-analysis-menu` + Avance 2026-06-03 | ⏳ Pendiente | Por redactar |
| **11** | **La secuencia didáctica viva: cuando el trimestre se tuerce** | Arrastrar y adaptar sesiones planificadas sin romper criterios | **Codex / Antigravity** | Avance 2026-06-28 (Secuencia del Planificador) | ⏳ Pendiente | Por redactar |
| **12** | **IA local sin mandar datos de menores fuera del dispositivo** | Resúmenes de tutoría y tendencias usando Apple Intelligence en chip | **Codex / Antigravity** | Avance 2026-06-04 (Apple Intelligence LOMLOE) | ⏳ Pendiente | Por redactar |
| **13** | **"Oye Antigravity, no me gusta este botón": inmediatez docente** | De detectar una molestia en clase a tenerla resuelta esa misma tarde | **Codex / Antigravity** | Flujo diario de desarrollo | ⏳ Pendiente | Por redactar |
| **14** | **Consejos para docentes que quieren perder el miedo a crear con IA** | La verdadera habilidad no es programar, sino definir el problema de aula | **Ecosistema completo** | Balance de experiencia acumulada | ⏳ Pendiente | Por redactar |

---

## 📝 Fichas Detalladas de Contenido (Hitos destacados)

### Entrega 02: Mi equipo virtual: Claude para diseñar y Antigravity para construir
- **Gancho:** «En un centro educativo no le pides lo mismo al profesor de Plástica que al de Matemáticas. Con la IA aprendí que pasa exactamente igual: no uso una sola herramienta mágica para todo.»
- **El rol de cada agente:**
  - *Claude:* Diseña pantallas limpias, analiza la saturación de los menús y cuida que la app se entienda a golpe de vista en el patio.
  - *Codex / Antigravity:* Escribe el código Swift, asegura la base de datos, conecta la sincronización y garantiza que la app nunca se cuelgue.
- **Impacto docente:** Desmitificar la IA: cómo coordinar asistentes especializados para tener un equipo de desarrollo completo al servicio de tu aula.
- **Llamada a la acción:** ¿Usáis distintas IAs para tareas diferentes en vuestro trabajo docente?

---

### Entrega 03: Del Word de 80 páginas al cuaderno en 1 clic
- **Gancho:** «¿Cuántas horas pasamos a principio de curso copiando y pegando criterios y sesiones desde el documento Word de la programación oficial al cuaderno de notas?»
- **El rol de cada agente:**
  - *Claude:* Analizó la estructura de los documentos de Situaciones de Aprendizaje de Mislata para entender cómo ordenar las actividades y los itinerarios pedagógicos.
  - *Codex / Antigravity:* Implementó el motor de importación en código nativo para procesar el DOCX en segundos sin errores.
- **Impacto docente:** Una tarea burocrática que antes llevaba días de inicio de curso se resuelve en 30 segundos.
- **Llamada a la acción:** ¿Cuánto tiempo tardáis en volcar la programación didáctica a vuestras herramientas de clase?

---

### Entrega 04: Evaluar a 30 alumnos en una pista con un iPad
- **Gancho:** «Las apps comerciales están pensadas para una mesa de despacho. En Educación Física hay reflejos de sol, 30 chicos botando balones y cero tiempo para menús desplegables diminutos.»
- **El rol de cada agente:**
  - *Claude:* Auditó la ergonomía táctil de la interfaz para rediseñar los selectores de rúbricas con botones grandes y claros.
  - *Codex / Antigravity:* Habilitó los atajos de teclado físicos en la funda del iPad para evaluar pulsando teclas sin mirar la pantalla.
- **Impacto docente:** Ergonomía y usabilidad real adaptada a la actividad motriz del aula.
- **Llamada a la acción:** ¿Qué interfaz de las apps educativas que usáis os parece menos práctica para vuestra materia?

---

## 🔄 Cómo incorporar los avances diarios futuros

A medida que vayamos realizando sesiones de trabajo en el proyecto:
1. Al terminar la tarea, se invoca la skill `post-x-docente`.
2. El asistente identifica explícitamente el agente utilizado en el descubrimiento/cambio.
3. Se genera el archivo `publicaciones/YYYY-MM-DD-slug.md` con las dos opciones (tweet directo y mini-hilo) y su campo de atribución.
4. Se añade una nueva fila a la tabla de este plan editorial.
