# Análisis del flujo: del grupo al boletín en Educamos

Fecha: 2026-11-23 · Base: `main` en `dd7b48ca` (PR #427 fusionada).
Alcance: informe del grupo → comentarios → Excel de Educamos → subida a Educamos. Incluye auditoría HIG de las pantallas.

---

## 1. Resumen

El flujo funciona, pero está repartido en cuatro sitios que no se conocen entre sí. El docente tiene que saber en qué orden usarlos.

Hay tres fallos reales y una pantalla que no cumple HIG (Exportar a Educamos).

La mejora con más impacto y menos esfuerzo para el docente es doble:

1. **Aprovechar los datos cualitativos que la app ya guarda** (descriptores de rúbrica, notas de celda, sellos, «Tu valoración», tutorías). Hoy el informe anónimo no los usa.
2. **Juntar todo en «Revisar cierre»** como un recorrido de 4 pasos: Notas → Comentarios → Excel de Educamos → Subir.

---

## 2. Cómo es el flujo hoy

| Paso | Dónde está | Qué hace | Problema |
|---|---|---|---|
| A. Datos del grupo | Informes › «Base para boletín» | Texto anónimo con asistencia, notas, autoevaluaciones y observaciones. Clave solo en pantalla. | No usa la mayor parte de lo cualitativo. Cuenta «sin material» como ausencia. |
| A'. Comentario con IA local | Informes › «Comentario LOMLOE» › «Generar lote» | Redacta con Apple Intelligence y guarda en una columna `LOMLOE IA - 1er Trimestre`. | Escribe en otra columna distinta de «Comentario de evaluación». Educamos no la encuentra sola. |
| B. Comentarios al Cuaderno | Cuaderno › Más › «Importar comentarios…» | Excel por orden o por código «Alumno NN». Revisión, avisos, deshacer. | Bien. Detalles de VoiceOver. |
| C. Excel de Educamos | Cuaderno › Más › «Exportar a Educamos SM» | Rellena instrumentos, SA, nota final y comentario. | No cumple HIG. El mensaje final solo habla de notas. Sin «Atrás». |
| D. Subir a Educamos | Fuera de la app | El docente sube el archivo en Educamos. | La app no dice qué hacer después. |

Recorrido real hoy: **Informes → (IA externa) → Cuaderno › Importar → Cuaderno › Exportar → Educamos web.** Son 4 pantallas en 2 módulos, sin hilo que las una.

---

## 3. Fallos encontrados (código)

1. **Los comentarios vuelven a entrar como «observaciones» en la IA.**
   `BuildLomloeCommentEvidence` (`kmp/shared/.../usecase/LomloeCommentEvidence.kt`, `isAiGeneratedColumn`) solo excluye columnas con icono `apple.intelligence`. La columna «Comentario de evaluación» (icono `text.bubble`) sí entra. Al regenerar, la IA lee el comentario anterior como si fuera una observación del docente.
   Arreglo: excluir también la columna de comentario de evaluación (por icono o por título).

2. **«Sin material» y «Exento» bajan el % de asistencia del informe anónimo.**
   `KmpBridge+BulletinBase.swift` los cuenta como «otros» dentro del total, pero no como presentes. Un alumno sin equipación aparece como si hubiera faltado. En EF es un dato importante, y además se pierde.
   Arreglo: contarlos como presentes y mostrarlos aparte («2 días sin material»).

3. **Dos columnas de comentario que no se hablan.**
   «Generar lote» (IA local) crea `LOMLOE IA - <trimestre>`. La importación y Educamos usan «Comentario de evaluación». Si el docente usa la IA local, al exportar a Educamos tiene que elegir la columna a mano.
   Arreglo: que «Generar lote» escriba por defecto en «Comentario de evaluación» de la pestaña activa.

4. **Riesgos menores**
   - Exportar a Educamos empareja alumnos por nombre y, si falla, **por orden en silencio**. Si el orden no coincide, la nota va a otro alumno sin avisar.
   - El lector de la plantilla de Educamos (`EducamosSMXMLParser`) numera las filas por orden y no por su número real. Con una plantilla que tenga filas omitidas, las notas irían a la fila equivocada. No ha pasado con las plantillas reales, pero no está protegido.
   - El informe anónimo duplica en Swift una lógica que ya existe mejor en KMP (`BuildLomloeCommentEvidence`). Va contra la regla del proyecto de dejar la lógica en KMP.

---

## 4. Información cualitativa sin esfuerzo para el docente

### 4.1 Lo que la app ya guarda y el informe anónimo NO usa (esfuerzo cero)

| Dato | Dónde se captura | Esfuerzo hoy | ¿Lo usa el informe anónimo? | ¿Lo usa la IA local (LOMLOE)? |
|---|---|---|---|---|
| Nivel y descriptor de cada criterio de rúbrica | Evaluar con rúbrica | Ya hecho al poner la nota | **No** | Sí |
| Notas de celda (anotaciones) | Toque largo en una celda | 1 gesto + texto | **No** | Sí |
| Sellos («Cooperación», «Superación», «Necesita refuerzo»…) | Sello en celda | 1 toque | **No** | No |
| Columnas de seguimiento (ordinal, Sí/No, icono) | Cuaderno | 1 toque | **No** | Parcial |
| «Tu valoración» del trimestre | Informes › Comentario LOMLOE | 1 frase por alumno | **No** | Sí |
| Acuerdos de tutoría | Tutoría | Ya registrado | **No** | Sí |
| «Sin material» / «Exento» | Asistencia | Ya registrado | Mal contado | — |
| Coevaluación | Instrumentos | Ya registrado | **No** | No |
| Diario de aula, incidencias, autoevaluación | Varios | Ya registrado | Sí | Sí |

Conclusión: **el informe anónimo debe construirse sobre `BuildLomloeCommentEvidence`** (KMP), que ya junta rúbricas, notas de celda, tutorías e incidencias por periodo, y añadirle sellos, columnas de seguimiento y «sin material». Así se gana información cualitativa sin pedir nada nuevo al docente, y hay una sola fuente de verdad.

### 4.2 Captura rápida durante el trimestre (1 toque)

- **Sellos como vocabulario cualitativo.** Ya existen 15 sellos con significado («Cooperación», «Progresando», «Entrega pendiente»…). Si el informe los resume («Cooperación ×4, Superación ×2»), cada toque en clase se convierte en una frase del boletín. Es lo que más rinde por segundo invertido.
- **Columnas de seguimiento por sesión** (Actitud: Excelente/Bien/Mejorable). Un toque por alumno y día da una tendencia cualitativa.
- **Dictado** en notas de celda y diario. El teclado de Apple ya dicta. Basta con recordarlo en el campo («Toca el micrófono para dictar»). No hace falta construir nada.

### 4.3 Cierre de trimestre (30 segundos por alumno, opcional)

- **«Tu valoración» con atajos.** Hoy es un campo libre. Se pueden ofrecer 3 filas de fichas: *Fortaleza*, *A mejorar* y *Orientación*, con frases sacadas de los sellos y de los criterios de rúbrica del trimestre. Son 3 toques por alumno, con texto libre opcional.
- **Solo donde hace falta.** «Revisar cierre» puede listar primero los alumnos con **pocos datos** (ya lo calcula el informe anónimo) para que el docente solo complete esos.

### 4.4 Redactar sin copiar y pegar

- **Camino corto (recomendado): IA del dispositivo.** «Generar lote» ya redacta con Apple Intelligence sin que los datos salgan del dispositivo, así que no hace falta anonimizar. Si escribe directo en «Comentario de evaluación», el flujo queda: *Generar → revisar → Exportar a Educamos*. No hay Excel intermedio.
- **Camino alternativo: IA externa.** Para cuando la IA del dispositivo no esté disponible o el docente prefiera otra. Informe anónimo → IA externa → Excel con códigos → «Importar comentarios» por código. Ya funciona.

---

## 5. Flujo propuesto: «Cerrar evaluación»

Punto de entrada único: **Cuaderno › Más › Revisar cierre** (ya existe y ya revisa notas vacías, Media y columnas ocultas). Se amplía a un recorrido de 4 pasos dentro de la misma hoja:

1. **Notas.** Lo que ya hace hoy: notas vacías, Media, criterios sin nota.
2. **Comentarios.** «Comentarios: 24 de 30». Acciones:
   - «Redactar con la IA del dispositivo» (principal), que escribe en «Comentario de evaluación».
   - «Preparar texto anónimo para otra IA», que abre «Base para boletín» con grupo y trimestre ya elegidos.
   - «Importar comentarios…»
   - Lista de alumnos sin comentario y de alumnos con pocos datos.
3. **Excel de Educamos.** Abre «Exportar a Educamos» con notas y comentarios.
4. **Subir a Educamos.** Pantalla final con:
   - «Mostrar en Finder» (Mac) o «Compartir» (iPad).
   - Pasos a seguir: *Sube este archivo en la misma evaluación de Educamos de la que descargaste la plantilla. No le cambies el nombre ni lo abras para editarlo en Excel.* El archivo lleva dentro los identificadores de esa evaluación (`EvaluacionId`, `FicheroId`).
   - Casilla «Ya lo he subido», que marca el cierre de esa pestaña como hecho.

Nota sobre Educamos: no hay documentación pública del importador de SM. No he podido comprobar sus pantallas ni si limita la longitud del comentario. La guía del paso 4 debe ser genérica o redactarla el docente una vez.

---

## 6. Auditoría HIG (código real)

| Pantalla | Veredicto |
|---|---|
| Base para boletín (`BulletinBaseReportView`) | Cumple con cambios |
| Importar comentarios (`EvaluationCommentImportSheet`) | Cumple (detalles) |
| **Exportar a Educamos (`EducamosSMExportSheet`)** | **No cumple** |
| Revisar cierre (`NotebookClosingReviewSheet`) | Cumple como punto de entrada (revisión superficial) |

### Bloqueantes (Exportar a Educamos)

1. **Estado del alumno solo por color e icono.** «Sin coincidencia» va en rojo con un icono sin etiqueta. Faltan `accessibilityLabel` en el icono y `children: .combine` en la fila. El texto debe ir en `.primary` y el color solo en el icono.
2. **Botón principal fuera de la barra.** «Generar archivo» está en un `safeAreaInset` y en la barra solo hay «Cerrar». Debe tener «Cancelar» (`.cancellationAction`) y «Generar» (`.confirmationAction`), como en Importar comentarios. Con letra grande, el inset tapa filas.
3. **Mensaje final falso.** Dice «Se han rellenado N calificaciones…» aunque también se escriben comentarios, y vale 0 si solo hay comentarios. Hay que usar el resumen «N notas y M comentarios».

### Mejoras

4. Exportar a Educamos: no hay «Atrás» ni «Cambiar archivo». El título no cambia por paso. «Hecho» debería ir en la barra.
5. «Matching de alumnos» es un anglicismo: «Emparejamiento de alumnos».
6. Los errores de generar o guardar no se ven en el paso 2 (fallo silencioso). `saveToDownloads` solo hace `print`.
7. El menú de columna mide menos de 44 pt, usa letra `caption` y recorta el texto con `lineLimit(1)`.
8. El progreso de «Generando archivo» no tiene etiqueta ni anuncio al terminar.
9. Base para boletín: el aviso naranja y la insignia verde no llegan a 4,5:1 de contraste. Texto en `.primary`, color solo en el icono.
10. Base para boletín: los tres botones en fila se salen con letra grande, así que hace falta `ViewThatFits`. El «Compartir» desactivado está vacío.

### Detalles

11. Base para boletín: la tarjeta de texto pone `accessibilityLabel` y VoiceOver deja de leer el contenido. El aviso «Copiado» debe llevar `allowsHitTesting(false)`.
12. Importar comentarios: el icono de códigos desconocidos no tiene etiqueta.

---

## 7. Propuesta de trabajo

**Ticket 1 (M): Arreglos y HIG del flujo actual.** Poco riesgo y efecto inmediato.
- Fallos 1, 2 y 3 de la sección 3, y aviso cuando Educamos empareje por orden.
- Los 12 hallazgos HIG de la sección 6.
- Toca `LomloeCommentEvidence.kt` (lógica KMP, no protegido), `KmpBridge+BulletinBase.swift`, `EducamosSMExportSheet.swift`, `BulletinBaseReportView.swift`, `EvaluationCommentImportSheet.swift` y la hoja de «Generar lote».

**Ticket 2 (L): «Cerrar evaluación» y datos cualitativos.** Más valor, necesita maqueta.
- Informe anónimo sobre `BuildLomloeCommentEvidence` + sellos + seguimiento.
- Recorrido de 4 pasos en «Revisar cierre».
- Fichas rápidas en «Tu valoración».

Orden recomendado: primero el Ticket 1, porque arregla errores que hoy pueden poner datos equivocados en el boletín.
