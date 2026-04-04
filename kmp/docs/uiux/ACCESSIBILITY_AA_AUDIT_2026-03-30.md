# Auditoría Accesibilidad AA (Desktop + iOS)
Fecha: 2026-03-30
Alcance: Shell, Cuaderno, Rúbricas, Planificación, Informes y Backups.

## Método
- Revisión estática de controles interactivos (icon-only, tamaños mínimos, labels).
- Revisión de contrastes potencialmente bajos por alpha en iconos de acciones.
- Revisión de motion para `Reduce Motion` y fallback para transparencia.
- Verificación de compilación:
  - `:desktopApp:compileKotlin`
  - `xcodebuild ... -destination 'generic/platform=iOS Simulator' build`

## Hallazgos y resolución
### H1 (Alta) — Icon-only actions sin etiqueta accesible en módulos críticos
- Estado: Resuelto en superficies prioritarias.
- Cambios:
  - Rúbricas: acciones `Asignar/Eliminar` y botones de importación/guardado con descripción explícita.
  - Planificación: iconos de navegación y acciones principales con descripción explícita.
  - iOS Cuaderno/Evaluación: botones icon-only con `accessibilityLabel`.

### H2 (Alta) — Objetivos táctiles menores a 44dp/44pt en acciones frecuentes
- Estado: Resuelto en shell/planning/rubrics/cuaderno prioritarios.
- Cambios:
  - Botones icon-only y acciones de overflow ajustados a `44dp/44pt`.
  - Tabs de planificación con altura mínima de interacción.

### H3 (Media) — Contraste reducido por alfa muy baja en acciones destructivas/primarias
- Estado: Parcialmente resuelto.
- Cambios:
  - Iconos de `Asignar/Eliminar` en tarjetas de rúbricas y acciones de criterios/niveles se elevaron a alfa 0.85.
- Pendiente:
  - Validación visual AA en temas/estados completos por pantalla (hover/pressed/disabled).

### H4 (Media) — Movimiento no reducido en algunas transiciones
- Estado: Resuelto en shell/transiciones principales.
- Cambios:
  - `reduceMotion` conectado a sidebar/planner y overlay iOS de evaluación.

### H5 (Media) — Módulos secundarios con labels/tamaños inconsistentes
- Estado: Resuelto en esta pasada.
- Cambios:
  - Dashboard: acción de refresh con label explícita.
  - Attendance: labels de navegación/fecha/marcado y `CompactStatusSelector` con objetivo mínimo de 44dp.
  - Attendance History Panel: respeta `reduceMotion`.
  - Desktop DatePicker: navegación mensual con labels.
  - iOS Notebook Grid/Group sheet: labels explícitas en acciones de columna, rúbrica, check y creación de grupo.

## Riesgos remanentes
- Quedan módulos secundarios con iconos decorativos y/o labels implícitos que requieren pasada completa:
  - Dashboard, Asistencia, DatePicker desktop, algunos diálogos avanzados.
- Falta validación manual con lector de pantalla:
  - Desktop (VoiceOver/NVDA equivalente) y iOS VoiceOver.
- Falta validación de contraste AA con herramienta visual por estado.

## Próxima tanda recomendada
1. Barrido de `contentDescription`/`accessibilityLabel` en módulos secundarios.
2. Sesión manual de teclado/foco (desktop) y VoiceOver (iOS).
3. Matriz de contraste por token/estado y correcciones de color finales.
