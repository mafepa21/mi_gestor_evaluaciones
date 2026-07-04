# Plan de Mejora — Cuaderno Docente (iPadOS · macOS)

Blueprint técnico-visual por componente. Base de código: `NotebookModuleView` y familia (`NotebookTopBar`, `NotebookTabStrip`, `NotebookDataGrid`, `NotebookInspectorPanel`, `NotebookCompactCommandBar`, `NotebookFocusMode`, sheets de columna/fórmula).

---

## 1. Barra superior (`NotebookTopBar` + `NotebookMacToolbarBinding`)

### 1.1 Reestructuración UI
- Una sola fila: selector de clase (menú con avatar de grupo) + segmento de evaluación + buscador colapsable. Todo lo demás sale de la barra.
- Acciones secundarias (organizar columnas, columnas ocultas, exportar) → menú único `ellipsis.circle` con secciones, no botones sueltos.
- Material: `.bar` con hairline inferior; sin fondos de color. Título de clase en `.headline`, evaluación en `.subheadline.secondary`.
- Estado de guardado/sincronización como icono transitorio (aparece 2 s, se desvanece), nunca texto permanente.

### 1.2 Adaptabilidad UX
| Interacción | iPadOS | macOS |
|---|---|---|
| Cambio de clase | Menú táctil (44 pt mínimo), swipe lateral en `NotebookTabStrip` | `Cmd+1…9`, picker en toolbar nativa (`ToolbarItem .principal`) |
| Búsqueda | Botón lupa → campo expandido a ancho completo | Campo persistente en toolbar, `Cmd+F` enfoca |
| Acciones | Menú `ellipsis` | Barra de menús de la app (`AppleAppCommands`) + toolbar customizable (`toolbar(id:)`) |

### 1.3 Funciones de alto valor
- **Cambio de contexto en un gesto**: mantener pulsado el selector de clase muestra las 3 clases con sesión hoy (según horario) para saltar directo.
- **Búsqueda que filtra filas en vivo** (alumno) y columnas (instrumento) con el mismo campo, con tokens (`alumno:`, `col:`).

---

## 2. Pestañas de módulo (`NotebookTabStrip`)

### 2.1 Reestructuración UI
- Reemplazar strip de pestañas con borde por segmentos "pill" flotantes sobre material, altura 32 pt, sin separadores.
- Máximo 5 visibles; overflow a menú. Icono + texto solo en la activa; el resto, solo icono con tooltip/label accesible.
- Indicador de datos pendientes (punto de 6 pt, `Color.accent`) en pestañas con celdas sin calificar de sesiones pasadas.

### 2.2 Adaptabilidad UX
- **iPadOS**: swipe horizontal de dos dedos sobre la rejilla cambia de pestaña; reordenación por drag largo.
- **macOS**: `Cmd+Shift+[ / ]` para ciclar; hover muestra recuento de columnas; reorden con drag directo (sin long-press).

### 2.3 Funciones de alto valor
- **Pestaña "Hoy"** virtual: agrega las columnas cuya fecha es la sesión actual de todos los módulos — el profesor abre y califica sin navegar.

---

## 3. Rejilla de datos (`NotebookDataGrid`, `NotebookGridContainer`, `NotebookEditableTableCell`)

### 3.1 Reestructuración UI
- Eliminar bordes de celda: solo hairlines horizontales (`separator` al 50 %) y bandas alternas sutiles opcionales.
- Columna de alumno fija (pinned) con nombre + foto 24 pt; resto desplaza horizontal con inercia.
- Tipografía numérica `monospacedDigit`, alineada a la derecha; notas suspensas en `secondary` + punto rojo, no fondos rojos de celda (menos ruido).
- Cabeceras de columna a dos líneas máx.: nombre truncado + fecha/peso en `caption2.secondary`.
- Densidades: cómoda (44 pt fila, iPad por defecto) y compacta (32 pt, Mac por defecto), conmutables.

### 3.2 Adaptabilidad UX
| Interacción | iPadOS | macOS |
|---|---|---|
| Editar celda | Tap → teclado numérico propio (`NotebookFormulaKeyboard` reducido: 0-10, +0.25, NP, exento) | Click → edición inline; teclear directamente sobre celda seleccionada la sobreescribe |
| Navegación | Tap; el teclado propio incluye ▲▼◀▶ | Flechas, `Tab`/`Enter` avanzan (Enter = bajar, configurable), `Esc` cancela |
| Selección múltiple | Tap con dos dedos y arrastrar (patrón listas iPadOS) | Click + `Shift`/`Cmd`, arrastre rectangular |
| Menú contextual | Long-press | Click derecho |
| Apple Pencil | Scribble en celda: escribir "7,5" a mano la rellena | — |

### 3.3 Funciones de alto valor
- **Modo racha (rapid entry)**: al confirmar una nota el foco baja solo; con teclado externo/Mac permite calificar una columna entera sin tocar el puntero.
- **Rellenar hacia abajo**: valor + `Cmd+D` (Mac) / botón "aplicar a seleccionados" (iPad) para poner la misma nota a un grupo (típico: trabajo grupal).
- **Pegado desde hoja de cálculo**: `Cmd+V` de un rango de Numbers/Excel mapea por orden de fila con previsualización de conflictos.
- **Deshacer real por celda** (`Cmd+Z` / shake / botón), con historial visible en el inspector.

---

## 4. Barra de comandos compacta (`NotebookCompactCommandBar`)

### 4.1 Reestructuración UI
- Convertir en barra flotante inferior tipo "toolbar capsule" (material grueso, sombra suave) que solo aparece con selección activa: n seleccionadas · nota rápida · limpiar · más.
- En Mac desaparece: sus acciones viven en menú contextual y barra de menús.

### 4.2 Adaptabilidad UX
- **iPadOS**: anclada sobre el teclado numérico cuando este está abierto; accesible con el pulgar.
- **macOS**: no se renderiza; equivalentes por atajo (`Cmd+Backspace` limpiar, etc.).

### 4.3 Funciones de alto valor
- **Nota rápida por voz** (iPad): botón micrófono en la cápsula; dictar "seis y medio" rellena la celda activa — útil calificando en el gimnasio/laboratorio con el iPad en una mano.

---

## 5. Inspector (`NotebookInspectorPanel`, `NotebookStudentInspector`)

### 5.1 Reestructuración UI
- Panel derecho de 320 pt (Mac: `inspector(isPresented:)` nativo; iPad: mismo API en regular, sheet en compact).
- Jerarquía: foto+nombre → media de evaluación con sparkline → desglose por módulo (barras finas) → últimas 5 notas → observaciones.
- Sin cajas anidadas: secciones separadas solo por espaciado (24 pt) y `caption` uppercase.

### 5.2 Adaptabilidad UX
- **iPadOS**: se abre con tap en la foto del alumno; swipe vertical dentro del inspector cambia de alumno (mantiene contexto).
- **macOS**: sigue a la selección de fila automáticamente; `Cmd+Opt+I` conmuta; flechas ↑↓ en la rejilla actualizan el inspector en vivo.

### 5.3 Funciones de alto valor
- **Comparativa instantánea**: la nota seleccionada se muestra contra la media del grupo en esa columna (percentil) — responde "¿es normal este 4?" sin salir.
- **Observación con timestamp en un tap**: chips predefinidos ("no trae material", "falta entrega") que registran incidencia fechada; alimentan el comentario de evaluación (`NotebookAICommentSheet`).

---

## 6. Gestión de columnas (`AddColumnSheet`, `NotebookColumnOrganizerSheet`, `NotebookFormulaEditorSheet`)

### 6.1 Reestructuración UI
- `AddColumnSheet` en dos pasos → un paso: plantillas primero (Examen, Rúbrica, Actitud, Fórmula) como grid de tarjetas; detalles con defaults inteligentes (fecha = hoy, peso = heredado).
- Organizador de columnas: lista plana con drag handles, agrupación por sección colapsable; eliminar el modo edición explícito.
- Editor de fórmulas: pills de referencia a columnas (no texto libre), resultado de ejemplo en vivo con un alumno real.

### 6.2 Adaptabilidad UX
- **iPadOS**: sheets con detent medio; crear columna desde botón `+` fijo al final del scroll horizontal de la rejilla.
- **macOS**: popover anclado a la cabecera `+`; doble click en cabecera renombra inline; `Opt+drag` de cabecera duplica columna.

### 6.3 Funciones de alto valor
- **Duplicar columna con estructura** ("otro examen igual, fecha nueva") desde el menú contextual de cabecera — la operación más repetida del trimestre en un gesto.
- **Columna desde el Planner**: al crear una sesión con actividad evaluable en el planificador, ofrecer "crear columna en Cuaderno" enlazada (cierra el bucle planificación→evaluación).

---

## 7. Modo enfoque y plano de clase (`NotebookFocusMode`, `NotebookSeatingPlanView`)

### 7.1 Reestructuración UI
- Focus Mode: una columna a pantalla completa, fila de alumno grande (foto 40 pt), entrada centrada; progreso "12/26" en la parte superior. Cero chrome.
- Seating plan: tarjetas de alumno con la nota de la columna activa superpuesta como badge; misma paleta neutra que la rejilla.

### 7.2 Adaptabilidad UX
- **iPadOS**: Focus Mode es el modo estrella de pie en el aula — swipe vertical entre alumnos, gestos de nota (swipe arriba +0.5, abajo −0.5); soporta Stage Manager a media pantalla.
- **macOS**: Focus Mode secundario (ventana auxiliar opcional); seating plan con hover que muestra tooltip de historial.

### 7.3 Funciones de alto valor
- **Calificar sobre el plano de clase**: seleccionar columna → tap en cada pupitre abre stepper de nota. Coincide con cómo el profesor barre el aula visualmente, no alfabéticamente.
- **Aleatorio ponderado**: botón "preguntar a alguien" que elige alumno priorizando a quienes tienen menos registros en la columna de participación.

---

## 8. Estados vacíos y carga (`NotebookSkeletonGridView`, `NotebookSupportViews`)

### 8.1 Reestructuración UI
- Skeleton con shimmer solo en la zona de rejilla; barra y pestañas se renderizan reales de inmediato (percepción de velocidad).
- Vacíos accionables: "Sin columnas en esta evaluación" + botón primario "Crear desde plantilla" + secundario "Copiar estructura de la 1.ª evaluación".

### 8.2 Adaptabilidad UX
- Idénticos en ambas plataformas; en Mac el CTA recibe foco de teclado por defecto.

### 8.3 Funciones de alto valor
- **Copiar estructura de evaluación anterior** (columnas, pesos, fórmulas — sin notas): elimina el mayor cuello de botella del arranque de trimestre.

---

## Prioridad de implementación

| Fase | Entregables | Impacto |
|---|---|---|
| 1 | Rejilla: edición inline Mac + modo racha + navegación teclado (§3) | Diario, todos los usuarios |
| 2 | Barra superior unificada + toolbar Mac nativa (§1) + pestañas pill (§2) | Percepción premium |
| 3 | Inspector reactivo + comparativa (§5) | Valor analítico |
| 4 | Duplicar columna, copiar evaluación, pegado desde hoja (§6, §8) | Picos de trimestre |
| 5 | Focus Mode gestual + plano de clase calificable + voz (§4, §7) | Diferenciación en aula |
