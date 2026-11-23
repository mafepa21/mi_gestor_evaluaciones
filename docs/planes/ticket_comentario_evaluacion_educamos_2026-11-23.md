# Ticket M: Comentario de evaluación en el Cuaderno

Aprobado por el docente el 2026-11-23. Maqueta aprobada: `docs/maquetas/comentario-evaluacion-educamos/mockup/index.html`.

## Objetivo

Cada evaluación del Cuaderno tiene su columna de comentario. Se rellena de golpe desde un Excel y se envía a Educamos junto con las notas.

## Alcance

1. Columna de texto «Comentario de evaluación» por pestaña de evaluación; no cuenta para la media; se crea sola al importar o con «Solo añadir la columna».
2. «Importar comentarios…» en el menú del Cuaderno (iPad y Mac): elegir .xlsx, columna propuesta (la de comentarios si es plantilla de Educamos), detección de fila de título, emparejamiento por orden, revisión «alumno ← comentario», avisos de recuento y sobrescritura, confirmación y deshacer.
3. «Exportar a Educamos»: fila «Comentarios» emparejada sola con «Comentario de evaluación» de la pestaña activa; escribe el texto en la columna TipoColumna=20.

## Fuera de alcance

- Generar los comentarios con IA dentro de la app.
- Emparejar por los códigos «Alumno 01» del informe anónimo.

## Modelo de datos

Sin cambios de esquema. Columna de texto normal del Cuaderno y celdas de texto existentes.

## Criterios de aceptación

- Cada comentario cae en su alumno, por orden; la fila de título no se importa.
- La revisión previa muestra a quién va cada comentario.
- Al exportar a Educamos, la columna de comentarios sale rellena con el texto correcto.
- Las notas se exportan igual que antes.

## Validación

- XCTest `EvaluationCommentImportTests` (lectura, orden, filas vacías, sobrantes, columna sugerida y plantilla de Educamos de ida y vuelta).
- Compilar Mac e iPad. Revisión HIG del código SwiftUI real.
- Solo datos inventados.
