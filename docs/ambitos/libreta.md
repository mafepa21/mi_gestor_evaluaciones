# Ámbito: Libreta (libretas a mano con Apple Pencil)

## Estado actual

- Integrado en `codex/libreta-integrada` (ticket `docs/planes/ticket_libreta_integrada_2026-10-15.md`, maqueta `docs/mockups/libreta/mockup/index.html`, ADR `kmp/docs/architecture/ADR-2026-10-15-libreta-swiftdata-propia.md`).
- Origen: app Cuadernos (`mafepa21/Notebook-`, commit `237e847`). Copiada tal cual; solo cambia el chrome (barra de la app, acento azul, textos «libreta»).
- Solo iPad, en Planificación tras «Diario de aula». No aparece en iPhone ni en Mac.
- Compila en iOS simulador y en Mac arm64. Sin QA en ejecución todavía (no hay simuladores instalados) ni prueba con Apple Pencil.
- Fase 2 (fuera del ticket): ligar libreta a grupo y meterla en las copias de Seguridad.

## Terreno de juego

- `kmp/iosApp/App/Libreta/` (`Models`, `Design`, `Library`, `Reader`, `Support`, `LibretaStore.swift`, `LibretaModuleView.swift`).
- Enganches mínimos (solo el caso `.libreta`):
  - `IPadWorkspaceShell.swift` (solo el enum `AppWorkspaceModule`);
  - `IOSFeatureRegistry.swift`, `IOSRootView.swift`, `WorkspaceSidebar.swift`;
  - `WorkspaceModuleSwitcher.swift`, `WorkspaceLayoutState+Extensions.swift`.
  - `MacApp/` no necesita cambios: usa su propio `MacFeature` y sus `switch` sobre el módulo tienen `default`.
- `kmp/iosApp/project.yml`: exclusión `Libreta/**` en el target `MiGestorKMPMac`.

## Trampas

- En la app, «Cuaderno» es el cuaderno de notas (`.notebook`, `NotebookModuleView`). Los tipos `Notebook`, `Page` y `Theme` de la Libreta no tienen nada que ver con él. En textos visibles, decir siempre «libreta».
- La Libreta usa SwiftData con su propio almacén (`Libreta`), no KMP ni SQLDelight. No pasar sus datos por `KmpBridge`.
- El código usa UIKit y PencilKit (`UIPageViewController`, `PKCanvasView`): no compila en macOS. Todo enganche en archivos que comparte el target de Mac va dentro de `#if os(iOS)`.
- El lector se abre con `fullScreenCover`: así tapa la barra lateral y la barra superior sin tocar `columnVisibility`.
- `Theme.accent` es el acento de la app (`Color.accentColor`); el terracota del papel es `Theme.paperAccent` y no cambia.
- La copia JSON mantiene el formato de Cuadernos: no cambiarlo, o las copias viejas (`*.cuaderno.json`, `Cuadernos-*.json`) dejan de importarse. Ahora se exporta como `<título>.json`; el importador acepta `.json` y cualquier archivo de datos.
- La clave de ajustes es `libreta.libraryLayout`, no `libraryLayout`.
- Nunca abrir ni importar libretas reales del usuario: pueden tener datos de alumnado. Solo datos de prueba.
- Archivo Swift nuevo: hay que ejecutar `xcodegen --spec kmp/iosApp/project.yml` y commitear el `project.pbxproj`.
- `Frameworks/` (MiGestorKit) no está en git: un worktree nuevo necesita enlazarlo desde el checkout principal antes de compilar.
- `xcodebuild` reescribe `*.xcscheme`: restaurarlos antes de commitear.
- `LibraryView` no tiene `NavigationStack` propio: su `.toolbar` y su `.searchable` se suman a la barra del `NavigationSplitView` de `IOSRootView`. Por eso `IOSRootView` no pone `IOSContextualToolbar` ni `IOSGlobalContextRow` en `.libreta`; si se añaden, saldrán duplicados.
- El `modelContainer` se aplica en `LibretaModuleView`; el lector y las hojas lo heredan porque cuelgan de `LibraryView`.
- `.libreta` en un `switch` de código que también compila en Mac va con `#if os(iOS)` y `EmptyView()` en Mac. Para saber si se puede mostrar, usar `AppWorkspaceModule.isAvailableOnThisDevice`.
- El target de Mac para `x86_64` no enlaza en local: el `MiGestorKit` de `Frameworks/macos` solo trae arm64. Compilar con `-destination 'platform=macOS,arch=arm64' ARCHS=arm64`.
- En este Mac no hay simuladores de iOS instalados (`xcrun simctl list runtimes` vacío): solo se puede compilar con `generic/platform=iOS Simulator`.
- `xcodegen` y `xcodebuild` necesitan salir del sandbox (escriben en la carpeta temporal del sistema).
