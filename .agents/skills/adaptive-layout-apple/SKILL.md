---
name: adaptive-layout-apple
description: Aplica el patrón de layout adaptativo iPad-first del proyecto - dos zonas con ViewThatFits, fallback compacto vertical, sheets con detents nativos en iOS/iPadOS y frames fijos solo en macOS. Usar siempre que una pantalla o sheet se vea cortada, desbordada, "de escritorio" en iPhone/iPad, con columnas rígidas, o cuando se pida adaptar un módulo a iPad/iPhone/macOS o crear una pantalla nueva que deba funcionar en varios tamaños.
version: 1.0.0
---

# adaptive-layout-apple

## Por qué existe esta skill

Diecisiete módulos de la app (Dashboard, Evaluación, Rúbricas, Informes, Biblioteca, Situaciones, Sesiones EF, Material EF, Torneos, Cursos, Alumnado, Diario, Pruebas Físicas, Backups, Asistencia, Horario, Sync LAN) ya migraron al mismo patrón adaptativo. Cualquier pantalla nueva o arreglo de layout debe usar ese patrón, no inventar otro. Los bugs de "controles cortados" tienen además una causa raíz ya identificada dos veces.

## El patrón canónico: dos zonas + fallback

```
ViewThatFits(in: .horizontal) {
    // 1) Ancho regular (iPad/macOS): dos zonas
    HStack { navegación/lista  |  detalle/superficie de trabajo }
    // 2) Ancho compacto (iPhone, iPad multitarea): apilado vertical
    VStack { filtros/lista  →  detalle }
}
```

Reglas del patrón, extraídas de las 17 migraciones:

1. **La zona principal es la tarea diaria**, la zona secundaria es navegación o inspector. Nunca tres columnas rígidas (Torneos las tenía y se eliminaron).
2. **El fallback compacto conserva TODAS las acciones**, apiladas; no es una versión recortada. Alumnado con `ViewThatFits` mantiene seguimiento, lesión e incidencias en compacto.
3. **Nada de anchos rígidos en iOS.** `frame(width:)` fijo solo se permite bajo `#if os(macOS)`. La previsualización de importación de horario tuvo que retirar su ancho rígido; no reintroducir.
4. **Sheets**: detents nativos (`.presentationDetents`) en iOS/iPadOS y frames fijos solo en macOS. Ya migrados así: añadir columna, organización del Cuaderno, instrumentos, asignación de rúbricas, editor de fórmulas, previsualización Apple IA, detalle de sesión del Planner, sheets de Situaciones. Pantalla nueva = mismo criterio desde el día uno.
5. **Inspector**: lateral en iPad regular, apilado o sheet en compacto (Asistencia es la referencia). Útil y no invasivo.

## Bug recurrente ya diagnosticado: controles cortados

Dos incidencias reales en `NotebookColumnOrganizerSheet` enseñaron la causa raíz:

- **`.fixedSize()` en controles de una fila horizontal** obliga a cada control a exigir su ancho natural completo; la suma supera el ancho del sheet y el borde corta los controles. Solución: quitar `.fixedSize()`, dar `.layoutPriority(1)` al control que debe comprimirse y simplificar etiquetas (sin contadores embebidos si no caben).
- **Filas con demasiados controles**: si una fila de acciones puede exceder el ancho, agrupar las secundarias en un menú "Más" en vez de estirar el frame del sheet.
- Un `.searchable(placement: .toolbar)` conviviendo con un `TextField` de búsqueda propio produce buscador duplicado flotante. Uno de los dos, nunca ambos.

Ante cualquier reporte de "se corta / se solapa / desborda": buscar primero `.fixedSize()` y frames rígidos antes de tocar nada más.

## Compatibilidad multiplataforma

Antes de escribir un `#if os(...)` para presentación, teclado, hover, búsqueda o navegación, revisar si ya existe helper en `kmp/iosApp/AppleShared/AppleViewCompatibility.swift`: `appFullScreenCover`, `appSearchable`, `appOnChange`, `appInlineNavigationBarTitleDisplayMode`, `appNavigationBarHidden`, `appHoverLiftEffect`, `appKeyboardType`, `appEditMode`, colores `appSecondary/TertiarySystemBackgroundColor`, etc. Usar el helper; si falta uno genuinamente nuevo, añadirlo ahí para todos, no inline en la vista.

Atajos de teclado: iPad con teclado hardware y macOS comparten estructura (`hardwareKeyboardShortcuts` en Rúbricas es la referencia); no duplicar lógica por plataforma salvo límite real del SDK (documentado: `.onMoveCommand` solo macOS).

## Proceso

1. Clasificar la pantalla: ¿dos zonas o flujo único? ¿Qué es tarea principal y qué es inspector?
2. Aplicar el patrón con `ViewThatFits`, mirando como referencia el módulo migrado más parecido (lista arriba).
3. Auditar la pantalla en busca de `.fixedSize()`, `frame(width:)` sin `#if os(macOS)` y detents ausentes.
4. Compilar ambas plataformas con `./scripts/verify_apple_builds.sh` y repasar mentalmente: iPhone, iPad split-view (compacto), iPad completo, macOS con ventana estrecha.
5. Estética según `jobs-design-philosophy`; cierre con `registrar-avance-app`.

## Salida esperada

Patrón aplicado (dos zonas o apilado), módulo de referencia imitado, lista de frames/fixedSize eliminados, y las cuatro configuraciones de tamaño repasadas.
