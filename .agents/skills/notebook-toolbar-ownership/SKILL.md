---
name: notebook-toolbar-ownership
description: Corrige o redisena toolbars del Cuaderno SwiftUI cuando haya duplicados, acciones faltantes, ownership confuso entre shell y modulo, o necesidad de paridad iOS/iPad/macOS. Usar para cambios de toolbar antes de swiftui-polish generico.
version: 1.0.0
---

# notebook-toolbar-ownership

## Objetivo
Mantener una sola fuente de verdad para las acciones del Cuaderno segun plataforma y tamano, evitando toolbars duplicadas o acciones criticas inaccesibles.

## Evidencia local que origino esta skill
- 2026-05-21: se elimino una toolbar global duplicada del Cuaderno iPad.
- 2026-05-23: se rediseno el toolbar iOS/iPad para parecerse a macOS.
- 2026-05-23: se anadio selector de clase al toolbar macOS del Cuaderno.
- 2026-05-24: la toolbar iOS/iPad perdia acciones criticas existentes en macOS: anadir columna, columnas indirectas, organizar/reordenar y columnas ocultas.
- `memoria` registra que macOS usa toolbar propiedad de `MacRootView` y que el ownership del Cuaderno debe revisarse antes de exponer controles desde `IPadWorkspaceShell` o `NotebookModuleView`.

## Archivos frecuentes
- `kmp/iosApp/App/IPadWorkspaceShell.swift`
- `kmp/iosApp/App/NotebookModuleView.swift`
- `kmp/iosApp/App/NotebookTopBar.swift`
- `kmp/iosApp/App/AddColumnSheet.swift`
- `kmp/iosApp/MacApp/MacRootView.swift`
- `kmp/iosApp/MacApp/NotebookMacLayout.swift`

## Mapa de ownership
- macOS: la toolbar del Cuaderno vive en `MacRootView`; `NotebookModuleView` no debe duplicar acciones de ventana.
- iPad regular: normalmente el shell (`IPadWorkspaceShell`) owns toolbar/context row; el modulo expone callbacks/estado.
- iPhone o inline compact: `NotebookModuleView` puede renderizar barra compacta local si no hay toolbar shell-owned suficiente.
- Acciones de edicion del grid deben reutilizar sheets/menus existentes; no crear flujos paralelos.

## Proceso
1. Inventariar acciones visibles por plataforma: clase, busqueda, modo grid/plano, anadir columna, indirectas/formulas, organizar, ocultas, inspector, refrescar/deshacer si aplica.
2. Identificar el owner activo para el contexto: `MacRootView`, `IPadWorkspaceShell` o `NotebookModuleView`.
3. Eliminar duplicados antes de anadir botones nuevos.
4. Conectar acciones faltantes reutilizando estado/callbacks existentes del Cuaderno.
5. Mantener paridad semantica con macOS, no necesariamente pixel-perfect si iPhone exige menu compacto.
6. En iPad, preferir una fila horizontal compacta con menus para acciones secundarias; evitar doble fila persistente sobre el grid.

## No hacer
- No reintroducir la toolbar interna de `NotebookModuleView` si el shell ya owns la toolbar.
- No mover seleccion de clase o busqueda entre owners sin revisar `StudentSelectionStore` y estado compartido.
- No tocar `KmpBridge.swift` para exponer una accion que ya existe en la UI.
- No anadir acciones permanentes sin utilidad diaria clara.

## Checklist visual
- Una sola toolbar activa.
- No hay acciones duplicadas con distinto icono/texto.
- Las acciones criticas del Cuaderno son accesibles en iPad y macOS.
- El grid conserva maximo espacio vertical.
- El estado vacio o sin clase no muestra comandos inutiles.

## Entrega
Responder con owner elegido, acciones anadidas/eliminadas, archivos modificados, que no se toco y casos probados.
