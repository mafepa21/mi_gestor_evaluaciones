---
name: liquid-glass-design
description: Aplica o corrige el sistema Liquid Glass (iOS 26/macOS 26) en la app - botones .glass/.glassProminent, GlassEffectContainer, morphing con glassEffectID y fallbacks material para OS anteriores. Usar siempre que la tarea hable de glass, translucidez, materiales, blur, "efecto cristal", botones flotantes, tab bars flotantes o de que un control se ve opaco/plano/inconsistente respecto al resto del chrome premium de la app.
version: 1.0.0
---

# liquid-glass-design

## Por qué existe esta skill

La app adoptó Liquid Glass de forma incremental y ya hay decisiones firmes sobre dónde aplicarlo, cómo agrupar superficies y qué fallback usar. Aplicar glass "de memoria" produce dos fallos recurrentes: tint azul que no queremos y controles que rompen en targets anteriores a iOS/macOS 26. Esta skill fija el criterio.

## Dónde SÍ y dónde NO (decisión de producto ya tomada)

**SÍ** — shell, banners, inspectores, componentes premium, Dashboard, tab bars flotantes y botones flotantes de módulos (Planner es la referencia).

**NO** — el grid del Cuaderno. La capa Liquid Glass macOS se concentró deliberadamente fuera del grid: la translucidez sobre cientos de celdas cuesta rendimiento y ensucia la lectura de datos. No "unificar" el grid con glass aunque parezca inconsistente.

## Patrones canónicos del proyecto

Referencia viva en tres archivos; leer el que corresponda antes de escribir glass nuevo:

- `kmp/iosApp/AppleShared/PlannerLiquidGlassControls.swift` — botones de acción con `.glass`/`.glassProminent`, CTA tintado de forma semántica, densidad en menú secundario.
- `kmp/iosApp/App/PlannerFloatingTabBar.swift` — tab bar flotante con selección como capa translúcida superpuesta y morphing entre pestañas.
- `kmp/iosApp/MacApp/MacLiquidGlassStyle.swift` — adaptaciones específicas macOS.

### Reglas extraídas del trabajo ya hecho

1. **Disponibilidad**: todo uso de `.glass`, `.glassProminent`, `GlassEffectContainer` o `glassEffectID` va tras un check de disponibilidad iOS/macOS 26 con fallback a material (`.ultraThinMaterial`/`.thinMaterial`). El fallback debe seguir siendo usable y estéticamente digno, no un placeholder.
2. **Agrupación**: botones/pestañas relacionados se agrupan dentro de un mismo `GlassEffectContainer` con separación suficiente entre elementos (hubo que refinarla: los elementos pegados dentro del container se leen como una masa).
3. **Morphing**: transiciones entre estados/pestañas usan `glassEffectID` con IDs estables. IDs inestables (derivados de índices que cambian) rompen el morphing silenciosamente.
4. **Selección translúcida, no pintada**: la selección de una pestaña es una capa glass más transparente sobre icono/texto, con tint reducido. Sin azul del sistema por defecto: el tint es semántico o neutro. Esta decisión ya se corrigió dos veces; no reintroducir botones azules.
5. **El glass es chrome, no contenido**: se aplica a controles y superficies de navegación. El contenido (celdas, texto de datos, tablas) queda sobre fondos sólidos del sistema de `EvaluationDesign.swift`.
6. **Sistema antes que imitación**: preferir estilos del sistema (`.buttonStyle(.glass)`) a recrear el efecto con blur+opacity manual. La app ya migró de imitaciones a estilos nativos ("use system glass button styles in planner").

## Proceso

1. Identificar si el elemento es chrome (aplica) o contenido (no aplica).
2. Buscar el patrón equivalente en los tres archivos de referencia y replicarlo, no reinventarlo.
3. Escribir la rama de 26 y la rama fallback en el mismo cambio; compilar ambas.
4. Comprobar en macOS además de iOS: los tamaños de hit-target y hover difieren, y `MacLiquidGlassStyle.swift` puede necesitar su override.
5. Validar con `./scripts/verify_apple_builds.sh` y revisión visual mental: ¿el foco sigue estando en el contenido? Glass que llama más la atención que la tarea principal es un fallo de diseño (Test del Bizqueo de `jobs-design-philosophy`).

## Límites

- No aplicar glass al grid del Cuaderno ni a superficies de datos densos.
- No añadir tint azul del sistema a selecciones.
- No duplicar estilos: si un patrón glass se necesita en un tercer módulo, extraerlo a `AppleShared/` en vez de copiarlo.

## Salida esperada

Elemento tratado, patrón de referencia usado, rama de fallback incluida (decirlo explícitamente), builds ejecutados en ambas plataformas.
