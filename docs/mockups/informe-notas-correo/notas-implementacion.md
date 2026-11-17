# Informe de notas por correo · notas para la implementación

Salen de la revisión de diseño (HIG y accesibilidad) de la maqueta. Se aplican al programar la hoja en SwiftUI.

- Barra: «Cerrar» con `.cancellationAction` y «Enviar siguiente» con `.confirmationAction`.
- Fila de alumno: `.accessibilityElement(children: .combine)`; lee «Nombre, nota, estado, correo». Fila elegida con `.isSelected`.
- Texto con estilos del sistema (`.caption` como mínimo). Nada de tamaños fijos ni de 11 pt.
- Con tamaños de accesibilidad (AX3 o más) las dos columnas pasan a una (`ViewThatFits` u `horizontalSizeClass`). Las filas crecen en alto, sin cortar el nombre.
- Colores semánticos (`.secondary`); `.tertiary` solo decorativo. «Sin correo» con texto normal e icono de aviso.
- «Para»: `Picker(.segmented)` nativo en su propia fila. «Evaluación»: `Picker`/`Menu`. «Instrumentos»: hoja con casillas y `.accessibilityHint`.
- Confirmación: destinatario primero (`.headline`), tipo (Alumno o Familia), asunto y botón «Abrir Mail para <nombre>». Cancelar es la acción por defecto.
- Iconos con SF Symbols (`tray`, `checkmark.circle.fill`) y `.accessibilityHidden(true)`.
- Carga: `ProgressView` con etiqueta «Preparando informes, 3 de 8». Sin pulso si está activo Reducir movimiento.
- Texto de IA en `TextEditor` con etiqueta; la marca «Redactado con IA de Apple» se lee antes del texto.
- Tras enviar, anunciar el cambio con `AccessibilityNotification.Announcement`.
- Rejilla de 8 pt entre bloques.
