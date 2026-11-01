# Ticket L · Integrar la Libreta (app Cuadernos) en Mi Gestor

- **Tamaño:** L (área nueva, base de datos propia, varios agentes).
- **Rama:** `codex/libreta-integrada` (worktree `.worktrees/libreta-integrada`, desde `origin/main` en `cba6611a`).
- **Maqueta aprobada:** `docs/mockups/libreta/mockup/index.html` (aprobada por el usuario el 2026-10-15).
- **Origen del código:** repo `mafepa21/Notebook-`, commit `237e847` (2026-09-29), carpeta `Cuadernos.swiftpm/Sources`.
- **Estado:** aprobado el 2026-10-15 y ejecutado en la rama. Falta QA en iPad.

## 1. Objetivo y contexto

Llevar la app Cuadernos (libretas de papel para iPad con Apple Pencil) dentro de Mi Gestor como un módulo más, llamado **Libreta**, sin que parezca un añadido.

- Se conserva tal cual el «objeto»: estantería, montones, portadas, papel, lector con paso de hoja, escritura con PencilKit, búsqueda de manuscrito, miniaturas, objetos, exportar a PDF y copia JSON.
- Se adapta el «chrome» (la parte de la app que rodea al objeto): barra lateral, barra superior, acento azul y hojas modales de Mi Gestor.
- Nombre «Libreta» porque «Cuaderno» ya es el cuaderno de notas y «Biblioteca» ya existe.
- Va en la sección **Planificación**, justo debajo de «Diario de aula». Solo iPad.

## 2. Alcance

1. Copiar el código de Cuadernos a `kmp/iosApp/App/Libreta/` con su estructura (`Models`, `Design`, `Library`, `Reader`, `Support`).
2. Base de datos propia con SwiftData, en un archivo separado (`Libreta.store`), sin iCloud.
3. Módulo nuevo `.libreta` en la barra lateral de iPad (Planificación, tras Diario de aula).
4. Estantería y montones dentro del panel de detalle, con la barra superior de Mi Gestor.
5. Lector a pantalla completa (tapa la barra lateral y la barra superior). «Estantería» vuelve.
6. Estado vacío con «Nueva libreta» y «Traer de Cuadernos» (restaurar la copia JSON de la app antigua).
7. Estado de error recuperable con «Reintentar» (sin `fatalError`).
8. Textos visibles: «cuaderno» pasa a «libreta» dentro del módulo.
9. Ajustes de accesibilidad aprobados en la maqueta: área de toque de los lomos de 44 pt como mínimo y contraste de textos pequeños.
10. El módulo no aparece en iPhone ni en Mac, y el target de Mac sigue compilando.

## 3. Fuera de alcance

- Ligar una libreta a un grupo o curso de Mi Gestor, y el botón «Abrir libreta del grupo» desde Diario o Planner (fase 2).
- Meter las libretas en las copias de Seguridad de Mi Gestor (fase 2).
- Sincronización con iCloud o SyncLAN.
- Versión de Mac o de iPhone del módulo.
- Rediseñar la estantería, el papel o el lector.
- Tocar KMP, SQLDelight, `KmpBridge.swift` o `EvaluationDesign.swift`.
- Seguir manteniendo la app Cuadernos suelta (decisión del usuario, ver Riesgos).

## 4. Modelo de datos

- **Entidades (SwiftData, sin cambios):** `Notebook` (título, color de tapa, papel, fechas, última hoja, grupo), `NotebookGroup` (nombre, orden), `Page` (índice, dibujo PencilKit, marcapáginas, plantilla, texto indexado), `PageElement` (imagen, texto o pegatina sobre la hoja).
- **Relaciones:** grupo 1→N libretas (al borrar el grupo, las libretas quedan sin grupo); libreta 1→N hojas (borrado en cascada); hoja 1→N elementos (borrado en cascada).
- **Almacén:** `ModelConfiguration("Libreta", schema:)` en Application Support del iPad. Contenedor creado de forma perezosa al abrir el módulo, para no frenar el arranque de la app.
- **Independencia:** sin relación con la base de KMP/SQLDelight. No hay migración SQLDelight.
- **Ajustes guardados:** la clave `libraryLayout` pasa a `libreta.libraryLayout`.
- **Copia JSON:** se mantiene el formato de Cuadernos y la extensión `.cuaderno`, para poder importar las copias que ya existen.

## 5. Plan

### Fase A · Copia sin cambios de comportamiento (1 commit)

- Copiar `Sources/{Models,Design,Library,Reader,Support}` a `kmp/iosApp/App/Libreta/`.
- No copiar `App.swift` (el `@main`), `Assets.xcassets` ni `Design-source`.
- `project.yml`, target `MiGestorKMPMac`: añadir `Libreta/**` a `excludes`. Regenerar con `xcodegen`.
- Comprobar que no hay choques de nombres de tipos con la app ni con `MiGestorKit` (revisado en el análisis: ninguno).
- Antes de compilar en el worktree, enlazar `kmp/iosApp/Frameworks/` desde el checkout principal (no está en git).
- Commitear el `project.pbxproj` regenerado.

### Fase B · Adaptaciones mínimas dentro de `App/Libreta/` (un commit por punto)

1. `LibretaStore.swift` (nuevo): contenedor perezoso, almacén `Libreta`, estado `cargando / listo / error` y `reintentar()`.
2. `LibraryView`: variante embebida. Sin `NavigationStack`, sin título propio y sin barra propia. Expone sus acciones (vista, buscar, nueva libreta, nuevo grupo, copia y restaurar) para la barra del módulo.
3. `Theme.accent` pasa a `Color.accentColor` (el acento de la app). `paperAccent` y el resto de colores del objeto no cambian.
4. Estado vacío con «Traer de Cuadernos» (reutiliza `restore`). Estado de error con aviso y «Reintentar».
5. Textos: «cuaderno» pasa a «libreta» (unas 30 cadenas en 26 archivos). «Sueltos» pasa a «Sin grupo».
6. Lector: el botón de volver muestra «Estantería» con flecha (antes solo flecha con etiqueta «Biblioteca»).
7. Lomos: `contentShape` con un mínimo de 44 pt de ancho, sin cambiar su dibujo.

### Fase C · Enganche en la app (un commit)

- `IPadWorkspaceShell.swift`: solo el enum `AppWorkspaceModule`. Caso `.libreta` con título «Libreta», subtítulo «Notas a mano con Apple Pencil», icono `pencil.and.scribble` y sección `.operations`.
- `IOSFeatureRegistry.swift`: descriptor tras `.diary`, filtrado a `userInterfaceIdiom == .pad`.
- `IOSRootView.swift`:
  - `.libreta` en `IOSWorkspaceSidebarSection.planning`, tras `.diary`.
  - `case .libreta` en `IOSWorkspaceContent`, dentro de `#if os(iOS)`.
  - Rama de barra `libretaToolbarItems`, como ya hacen Cuaderno y Asistencia.
  - Sin `IOSGlobalContextRow` en este módulo.
  - `normalizedModule`: `.libreta` fuera de iPad vuelve a `.dashboard`.
- `WorkspaceSidebar.swift`: `.libreta` en Planificación, tras `.diary`.
- `WorkspaceModuleSwitcher.swift` y `WorkspaceLayoutState+Extensions.swift`: añadir el caso.
- `MacApp/MacRootView.swift`: sin cambios al final (usa `MacFeature` y `default`). `MacFeatureRegistry` no lo lista.

### Fase D · Registro

- Skill `registrar-avance-app`: CHANGELOG, ROADMAP, nota de PR y capturas.
- Actualizar `docs/ambitos/libreta.md` (Estado actual y Trampas).

## 6. Agentes

| Paso | Agente | Modelo |
|---|---|---|
| Fases A y B | `worker` | Sonnet, medio |
| Fase C | `worker` | Sonnet, medio |
| Si un worker falla dos veces | `architect` | Opus |
| Revisión de código y criterios | `reviewer` | Sonnet |
| Capturas frente a la maqueta | `ui-reviewer` | Sonnet |
| Antes del merge | `janitor` | Sonnet |

Skills: `swiftui-native-feature` como principal y `registrar-avance-app` al cierre.

## 7. Criterios de aceptación

- [ ] En iPad aparece «Libreta» en Planificación, justo debajo de «Diario de aula».
- [ ] En iPhone no aparece. Si estaba guardada como último módulo, la app abre en Hoy.
- [ ] El target de Mac compila y no muestra el módulo.
- [ ] La estantería y los montones se ven dentro del panel, con la barra lateral y la barra superior de la app.
- [ ] La barra superior muestra el título «Libreta», Estantería/Montones, Buscar y «Nueva libreta» como única acción principal.
- [ ] Tocar un lomo o una portada abre el lector a pantalla completa, sin barra lateral ni barra superior.
- [ ] «Estantería» cierra el lector y devuelve a la misma vista.
- [ ] Funciona como en Cuadernos: Apple Pencil escribe, el dedo pasa hoja, deshacer y rehacer, miniaturas, marcapáginas, objetos, plantillas de hoja, búsqueda de manuscrito, PDF y copia JSON.
- [ ] Grupos: crear, renombrar, ordenar, eliminar (con confirmación) y mover libretas arrastrando.
- [ ] Vacío: «Nueva libreta» y «Traer de Cuadernos». Una copia `.cuaderno` o `.json` de Cuadernos se importa completa.
- [ ] Error al abrir la base: aviso arriba con «Reintentar». Nada se borra.
- [ ] Ningún texto visible del módulo dice «cuaderno».
- [ ] Botones y menús en el azul de la app. El papel, las tapas y la madera no cambian.
- [ ] Claro y oscuro correctos. Lomos con al menos 44 pt de toque.
- [ ] El arranque de la app no empeora (el contenedor solo se crea al entrar en Libreta).
- [ ] Sin cambios en archivos protegidos.

## 8. Validación

- `xcodebuild` del esquema `MiGestorKMPiOS` para simulador de iPad.
- `xcodebuild` del esquema `MiGestorKMPMac` (que siga compilando sin la carpeta Libreta).
- `xcodebuild test` del esquema `MiGestorPlannerTests` como regresión del shell.
- QA manual en simulador de iPad (horizontal y vertical, claro y oscuro), con datos de prueba creados en el momento:
  - crear, abrir, escribir con el ratón usando «Dibujar también con el dedo», cerrar;
  - grupos, montones, búsqueda, PDF, copia, restaurar y error simulado.
- Capturas para `ui-reviewer` frente a la maqueta.
- Comparar con el estado previo de CI: los fallos que ya existían no bloquean.
- Si un comando falla por entorno (por ejemplo, la compilación de KMP sin red), se registra con su motivo.

## 9. Riesgos y puertas humanas

- **Apple Pencil real:** solo se puede probar en un iPad físico. **Puerta humana:** lo prueba el usuario.
- **Datos reales:** las libretas del usuario pueden tener datos de alumnado. El agente nunca abre ni importa copias reales; solo usa datos de prueba. **Puerta humana:** la importación real la hace el usuario.
- **Dos copias del código:** si Cuadernos sigue cambiando, habrá dos versiones. **Puerta humana:** decidir si se congela la app suelta (recomendado) o si los cambios se pasan a mano.
- **Sin copia en Seguridad:** hasta la fase 2, las libretas no entran en las copias de Mi Gestor. Mitigación: la copia JSON propia de la Libreta sigue disponible en su menú.
- **Nombres genéricos** (`Page`, `Theme`, `Notebook`) en el mismo módulo Swift que la app: hoy no chocan, pero podrían en el futuro. Mitigación: anotarlo en Trampas y renombrar si aparece un choque.
- **Archivo sensible:** en `IPadWorkspaceShell.swift` solo se toca el enum.
- **`xcodebuild` reescribe `*.xcscheme`:** restaurarlos antes de cada commit.
- **Merge:** lo hace el usuario tras la revisión de `janitor`.

## 10. Entregables

- Código en `kmp/iosApp/App/Libreta/` y enganches de la Fase C, en commits atómicos.
- `project.yml` con la exclusión para Mac, y el proyecto regenerado.
- `docs/ambitos/libreta.md` creado y actualizado.
- CHANGELOG, ROADMAP y nota de PR (skill `registrar-avance-app`), con las comprobaciones hechas y las no hechas.
- Capturas de iPad en horizontal, vertical, claro y oscuro.
- PR hacia `main` desde `codex/libreta-integrada`.
