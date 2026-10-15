# Ámbito: Libreta (libretas a mano con Apple Pencil)

## Estado actual

- Módulo nuevo, en preparación. La maqueta está aprobada (`docs/mockups/libreta/mockup/index.html`) y el ticket redactado (`docs/planes/ticket_libreta_integrada_2026-10-15.md`), pendiente de «APROBADO».
- Origen: app Cuadernos (`mafepa21/Notebook-`, commit `237e847`). Se copia tal cual. Solo cambia el chrome: barra lateral, barra superior, acento azul y hojas modales.
- Solo iPad, en Planificación tras «Diario de aula». No aparece en iPhone ni en Mac.
- Fase 2 (fuera del ticket): ligar libreta a grupo y meterla en las copias de Seguridad.

## Terreno de juego

- `kmp/iosApp/App/Libreta/` (`Models`, `Design`, `Library`, `Reader`, `Support`, `LibretaStore.swift`).
- Enganches mínimos (solo el caso `.libreta`):
  - `IPadWorkspaceShell.swift` (solo el enum `AppWorkspaceModule`);
  - `IOSFeatureRegistry.swift`, `IOSRootView.swift`, `WorkspaceSidebar.swift`;
  - `WorkspaceModuleSwitcher.swift`, `WorkspaceLayoutState+Extensions.swift`;
  - `MacApp/MacRootView.swift`.
- `kmp/iosApp/project.yml`: exclusión `Libreta/**` en el target `MiGestorKMPMac`.

## Trampas

- En la app, «Cuaderno» es el cuaderno de notas (`.notebook`, `NotebookModuleView`). Los tipos `Notebook`, `Page` y `Theme` de la Libreta no tienen nada que ver con él. En textos visibles, decir siempre «libreta».
- La Libreta usa SwiftData con su propio almacén (`Libreta`), no KMP ni SQLDelight. No pasar sus datos por `KmpBridge`.
- El código usa UIKit y PencilKit (`UIPageViewController`, `PKCanvasView`): no compila en macOS. Todo enganche en archivos que comparte el target de Mac va dentro de `#if os(iOS)`.
- El lector se abre con `fullScreenCover`: así tapa la barra lateral y la barra superior sin tocar `columnVisibility`.
- `Theme.accent` es el acento de la app (`Color.accentColor`); el terracota del papel es `Theme.paperAccent` y no cambia.
- La copia JSON mantiene el formato y la extensión `.cuaderno` de la app antigua: no cambiarlos, o las copias viejas dejan de importarse.
- La clave de ajustes es `libreta.libraryLayout`, no `libraryLayout`.
- Nunca abrir ni importar libretas reales del usuario: pueden tener datos de alumnado. Solo datos de prueba.
- Archivo Swift nuevo: hay que ejecutar `xcodegen --spec kmp/iosApp/project.yml` y commitear el `project.pbxproj`.
- `Frameworks/` (MiGestorKit) no está en git: un worktree nuevo necesita enlazarlo desde el checkout principal antes de compilar.
- `xcodebuild` reescribe `*.xcscheme`: restaurarlos antes de commitear.
