# Propuesta UI — Instrumentos de evaluación del Cuaderno

Fecha: 2026-08-03
Rama: `codex/audit-cuaderno-instrumentos-evaluacion`
Estado: especificación implementada en SwiftUI; pendiente de QA visual manual

## Resumen ejecutivo

Las tres pantallas de las capturas ya son funcionales y tienen una base SwiftUI sólida, pero todavía se perciben como tres variantes del mismo producto:

- la rúbrica individual es una ficha editorial con mucho aire vertical;
- la evaluación masiva es una matriz densa con superficies casi opacas y varios chips;
- la rejilla de observación es un formulario largo con tarjetas anidadas.

Propongo un único lenguaje: **Evaluation Workspace**. La hoja se entiende en tres capas:

1. **Chrome contextual**: cabecera, alumno/grupo, estado de guardado, progreso y acción principal. Aquí sí aparece el aire Liquid Glass.
2. **Referencia curricular**: una franja compacta y expandible para los criterios LOMLOE.
3. **Contenido evaluable**: criterios, sesiones, alumnos y niveles sobre superficies sólidas, calmadas y de alto contraste.

La regla principal es: **glass para orientar y actuar; superficie sólida para leer y puntuar**.

## Alcance revisado

Se han contrastado las capturas con estos puntos de entrada actuales:

| Superficie | Implementación actual | Tarea principal |
| --- | --- | --- |
| Rúbrica individual | `RubricEvaluationView.swift` + `RubricsStyle.swift` | Elegir un nivel por criterio para un alumno |
| Rúbrica masiva | `RubricBulkEvaluationSheet.swift` | Puntuar varios alumnos con rapidez |
| Instrumento estructurado | `NotebookStructuredInstrumentSupport.swift` | Completar una plantilla por alumno |
| Auto/coevaluación | `StudentRubricInstrumentContent.swift` | Responder indicadores y reflexión |
| Rejilla de observación | `ObservationGridInstrumentContent.swift` | Registrar niveles por sesión |
| Referencia curricular | `AssessmentCriteriaDisclosureView.swift` | Consultar criterios sin abandonar la tarea |

No se propone aplicar translucencia al grid del Cuaderno ni cambiar la lógica KMP, el contrato de datos o el guardado.

## Diagnóstico Jobs

### Inventario de tareas

Las tres tareas prioritarias son distintas y no deberían competir visualmente:

1. **Evaluar a una persona**: decisión pausada, con acceso al descriptor del nivel.
2. **Evaluar al grupo**: repetición rápida, comparación entre filas y mínimo movimiento ocular.
3. **Completar un instrumento**: lectura secuencial de sesiones o campos, con progreso visible.

### Puntuación actual

| Principio | Puntuación | Observación |
| --- | ---: | --- |
| Simplicidad radical | 6/10 | Hay una acción clara, pero conviven chips, badges, anillos y superficies con mensajes parecidos. |
| Whitespace y ritmo | 6/10 | La rúbrica individual respira bien; la masiva alterna mucho espacio exterior con celdas comprimidas. |
| Jerarquía y rejilla | 6/10 | Los títulos se entienden, pero el contenido no comparte una escala estable entre las tres pantallas. |
| Foco en el flujo | 7/10 | La selección es directa, aunque la información curricular y las acciones secundarias interrumpen el recorrido. |
| Consistencia visual | 5/10 | Chips, tarjetas, píldoras, segmented pickers y toolbars cuentan el mismo estado de maneras distintas. |

**Diagnóstico global: 6/10.** El producto ya comunica “herramienta profesional”, pero todavía no comunica “una única herramienta profesional”. El mayor salto no está en añadir decoración, sino en unificar la estructura y reservar el cristal para el chrome.

### Fortalezas que conviene conservar

- La matriz masiva con columna de alumno y cabeceras fijadas.
- La lista plana y el anillo de progreso de la rúbrica individual.
- `ViewThatFits` para adaptar niveles y selectores.
- El segmentado 1–4 de la rejilla de observación.
- Atajos de teclado, hover y popovers en macOS.
- La separación entre color de nivel y color de nota.

### Problemas observables en las capturas

- **Cabeceras sobrecargadas**: nombre, subtítulo, estado, chips y criterios compiten antes de empezar a evaluar.
- **Contexto repetido**: el nombre del instrumento y los criterios aparecen en más de un nivel de la hoja.
- **Densidad irregular**: la matriz masiva aprieta texto y controles, mientras la ficha individual deja una zona inferior demasiado vacía.
- **Niveles poco comparables**: los nombres se recortan en la matriz y el descriptor completo queda fuera del recorrido principal.
- **Jerarquía de acción ambigua**: “Guardar” es una CTA dominante en la rúbrica individual, pero la masiva funciona con autoguardado y necesita solo confianza ambiental.
- **Glass sin contrato común**: si cada tarjeta se hace translúcida, el contenido pierde contraste y el efecto deja de ser especial.

## Rediseño propuesto: Evaluation Workspace

### Estructura común

```text
┌────────────────────────────────────────────────────────────┐
│ [Cerrar]  ALUMNO / GRUPO       Instrumento     [progreso]  │  ← chrome glass
│           contexto breve       estado guardado             │
├────────────────────────────────────────────────────────────┤
│  Criterios LOMLOE   CE 2.1   CE 4.2   ⓘ                    │  ← glass ligero
├────────────────────────────────────────────────────────────┤
│                                                            │
│  CONTENIDO EVALUABLE                                       │  ← sólido
│  criterio / sesión / alumno                               │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

La estructura es común, pero el contenido cambia de modo:

- **Individual**: una columna centrada y una acción de guardado persistente.
- **Masiva**: toolbar compacta y matriz sólida con columna de alumno fijada.
- **Instrumento**: secciones secuenciales y progreso del formulario.

### 1. Rúbrica individual

**Cabecera**

- Avatar pequeño del alumno, nombre y rúbrica en dos líneas.
- Un solo indicador de progreso: `3/6` y nota actual; mantener el anillo si aporta lectura rápida, pero sin duplicarlo en otro panel.
- El estado “Guardado” queda como punto + texto secundario en el chrome, no como tarjeta.
- Mientras falten criterios, la etiqueta debe decir `Nota provisional`; así la cifra parcial no parece una nota definitiva.

**Criterios**

- Lista plana con separación por whitespace y hairlines solo cuando haga falta.
- Cada fila: código/título del criterio arriba y selector de niveles debajo.
- El selector presenta nombre corto + puntos; el descriptor completo se abre con el mismo gesto en iOS/iPadOS y macOS (`ⓘ`/popover o inspector contextual).
- Nivel seleccionado: color semántico de ese nivel con contraste AA. Niveles no seleccionados: borde neutro, sin cuatro rellenos compitiendo.
- El color se acompaña de borde, check o texto de estado; nunca es la única señal de selección.
- El selector debe poder pasar de cuatro cápsulas horizontales a una rejilla 2×2 sin recortar texto.

**Acción**

- Barra inferior flotante con una única CTA: `Guardar · 3 de 6 criterios`.
- Cuando está completa: `Guardar · 8,5`.
- La barra es chrome y puede usar `.glassProminent`; no convertir cada criterio en una tarjeta translúcida.

### 2. Rúbrica masiva

**Modo de trabajo**

La matriz es el patrón correcto para una clase completa. No debe parecer una hoja de cálculo genérica ni una galería de tarjetas.

- Toolbar de cristal con: grupo/rúbrica, pendientes totales, estado de guardado y menú de acciones.
- Diferenciar semánticamente `8 por evaluar` de `Cambios guardados`; son estados distintos y no deben parecer contradictorios.
- El cuerpo es sólido y opaco para mantener contraste durante el scroll horizontal.
- Primera columna de alumno fijada; cabecera de criterios fijada verticalmente.
- Avatar + nombre + un único punto de estado por fila: pendiente, completa o incidencia.
- La nota final aparece como número semántico sin una tarjeta adicional.
- Las acciones por fila se agrupan en un menú `…`; visibles al hover en macOS y siempre disponibles en iPadOS.

**Celda de criterio**

- Probar primero un control compacto numérico `1–4` con una leyenda contextual del criterio activo; preserva la velocidad de un toque.
- Mostrar nombre abreviado solo si cabe; el nombre completo se ofrece mediante tooltip/popover accesible. Si los nombres no caben, el menú es fallback, no el modo por defecto.
- La selección usa el color del nivel, no el azul de sistema por defecto.
- Si la anchura no permite legibilidad, la celda muestra el nivel elegido y abre un menú de selección al tocar; no se deben truncar cuatro etiquetas hasta hacerlas ilegibles.

**Autoguardado**

- Mantener el autoguardado.
- El estado se comunica con un pequeño punto y texto (`Guardando…` / `Guardado`), junto con un feedback breve al completar.
- No añadir un gran botón “Guardar” que sugiera un modelo de guardado manual distinto.

### 3. Instrumento estructurado, auto/coevaluación y observación

**Cabecera del instrumento**

- Alumno como identidad principal.
- Debajo: tipo de instrumento, progreso `5/12 campos` y nota final cuando exista.
- Criterios LOMLOE en una franja compacta; la descripción legal completa queda bajo expansión explícita.
- “Cerrar” y “Guardar” siguen siendo acciones de toolbar; en iPadOS puede existir una barra inferior si el contenido es largo.

**Vinculación curricular**

`AssessmentCriteriaDisclosureView` y `EvaluationCriterionSection` deberían converger conceptualmente en un único bloque “Vinculación curricular”:

- Replegado: `CE 2.1 · 1 criterio`.
- Expandido: código, título, enunciado oficial y texto alternativo.
- Una sola superficie secundaria, visible pero subordinada a la tarea de puntuar.

**Auto/coevaluación**

- Mantener la separación conceptual entre indicadores puntuables y reflexión.
- Cada indicador se presenta como una fila de rúbrica compacta: título, cuatro niveles y descriptor bajo demanda.
- “Preguntas de reflexión” pasa a una sección claramente no puntuable, con icono y texto secundario, no a otra tarjeta idéntica.

**Rejilla de observación**

- Cada sesión es una sección con cabecera, recuento de respuestas y media de sesión.
- Los indicadores se leen como filas de una lista, no como mini-tarjetas anidadas.
- La escala 1–4 se mantiene como control directo; el nivel seleccionado debe tener color semántico y el estado vacío un tratamiento neutro.
- La nota final se integra en la cabecera del instrumento y no se repite en cada bloque salvo la media de sesión.

## Sistema visual

| Token | Propuesta |
| --- | --- |
| Espaciado | Base 8pt: 8 para microseparación, 16 para control, 24 para sección, 32 para cambio de contexto. |
| Radios | 24–28 para el contenedor de la hoja; 16 para superficies de trabajo; 8–12 para controles interiores. Radios concéntricos. |
| Tipografía | Título de pantalla, título de sección, dato/estado. Máximo tres pesos visibles por zona. Dynamic Type siempre que sea posible. |
| Color | Acento para acción y foco; verde/ámbar/rojo solo para estados semánticos; niveles con color relativo a sus puntos. |
| Bordes | Hairline discreta. Preferir espacio a dividers repetidos. |
| Datos | Superficie opaca del sistema para tablas, filas, celdas y texto curricular. |

### Contrato Liquid Glass

Aplicar el patrón nativo del proyecto:

- iOS/macOS 26: `.glass`, `.glassProminent` y `GlassEffectContainer` únicamente en toolbar, franja contextual y barra de acción.
- Fallback explícito para targets anteriores: `.ultraThinMaterial`/`.thinMaterial` o la superficie adaptativa existente.
- No recrear el efecto con blur + opacidad manual.
- No introducir tint azul de sistema en selecciones; usar tint semántico reducido o neutro.
- Si se anima una selección entre controles, los `glassEffectID` deben ser estables.
- El grid del Cuaderno y la matriz de evaluación masiva permanecen sólidos: cientos de celdas translúcidas degradarían rendimiento y legibilidad.

Referencias de implementación a reutilizar cuando se pase a código:

- `kmp/iosApp/AppleShared/PlannerLiquidGlassControls.swift`
- `kmp/iosApp/App/PlannerFloatingTabBar.swift`
- `kmp/iosApp/MacApp/MacLiquidGlassStyle.swift`

## Accesibilidad y fiabilidad

- Todas las opciones de nivel mantienen un área táctil mínima de 44pt.
- VoiceOver debe anunciar criterio, nivel, puntos y estado seleccionado en una sola lectura.
- El color nunca es la única señal: añadir texto, punto, icono o anillo para estados.
- Dynamic Type no debe convertir cuatro niveles en controles recortados; `ViewThatFits`/rejilla son preferibles a truncar.
- Reduce Motion: las transiciones del cristal deben degradar a un cambio de selección simple.
- En macOS: hover y teclado aceleran la tarea, pero no pueden ser la única forma de acceder a descriptores o acciones.
- El autoguardado masivo debe seguir siendo visible y recuperable tras error, sin bloquear el registro de nuevas notas.

## Plan de implementación sugerido

### Fase 1 — Fundación visual

- Extraer un chrome compartido para las tres hojas en `AppleShared/` o `App/`, sin tocar KMP.
- Unificar cabecera, franja curricular, estados de guardado y CTA.
- Definir tokens locales de instrumentos sin editar `EvaluationDesign.swift`.

### Fase 2 — Individual y estructurados

- Aplicar el shell a `RubricEvaluationView` y `StructuredInstrumentEvaluationSheet`.
- Convertir niveles y escalas en controles semánticos comunes.
- Reagrupar observación por sesión y reflexión con progressive disclosure.

### Fase 3 — Masiva

- Reskin del toolbar y simplificación de filas.
- Mantener el cuerpo de la matriz opaco, con primera columna y cabeceras fijadas.
- Resolver la estrategia de celda: segmented picker si cabe; menú contextual si no.

### Fase 4 — QA visual

- iPad 11\" y macOS 14\" en claro y oscuro.
- Rúbrica con 6+ criterios y clase de 30 alumnos.
- Instrumento de observación con varias sesiones y descriptores largos.
- Dynamic Type grande, VoiceOver, teclado macOS, Reduce Motion y fallback sin Liquid Glass.

## Riesgos y decisiones pendientes

- **Alto**: un segmented picker con nombres largos puede empeorar la evaluación masiva. Se debe validar con datos reales antes de fijarlo.
- **Medio**: una CTA glass persistente puede ocupar demasiado en iPad; debe respetar safe area y desaparecer cuando no hay cambios.
- **Medio**: trasladar el descriptor a popover reduce ruido, pero requiere una vía táctil obvia y consistente.
- **Bajo**: añadir un componente compartido puede cruzar límites entre `App` y `AppleShared`; mantenerlo visual y sin dependencias de KMP.

## Qué no se recomienda

- Glass en el grid del Cuaderno o en cada celda de la evaluación masiva.
- Más chips para explicar cantidades que ya aparecen en el layout.
- Descriptores completos repetidos en cada nivel y en un popover simultáneamente.
- Acciones importantes escondidas solo en long-press o hover.
- Cambios en `KmpBridge.swift`, `kmp/shared/`, `kmp/data/` o en el modelo de persistencia para este rediseño.

## Criterio de éxito

Al entrecerrar los ojos, debe destacar una sola cosa según el modo: el criterio que se está puntuando, la fila del alumno o la sesión actual. El usuario debe poder responder “qué estoy evaluando, cuánto me falta y cómo termino” sin leer una segunda vez la cabecera.
