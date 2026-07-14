# Incidencia — build de macOS/iOS roto tras merge de medidas Nivel III/IV (14 de julio de 2026)

## Contexto

El 14/07/2026 se ejecutó `90d8216` — *"Merge branch 'main' into feature/planner-diario-macos-sesion resolving conflicts"* —, que incorporó a la rama del planificador diario los cambios ya en `main` de la rama `feature/medidas-apoyo-nivel-iii-iv` (registro y seguimiento de medidas de apoyo, importación masiva desde Excel, vista de grupo, `SyncStatusBadge`, etc.). El merge se cerró como resuelto (`923ce61` → `90d8216` → `7869552`), pero dejó la build de `MiGestorKMPMac`/`MiGestorKMPiOS` rota. El síntoma inicial reportado por el usuario fue una UI con el panel lateral recortado y sin la sección "Medidas de apoyo" en la ficha de alumno, pese a que el código de esa funcionalidad ya estaba en `main`.

## Causa raíz (tres problemas independientes, todos originados en el mismo merge)

1. **Marcador de conflicto de Git sin resolver.** `kmp/iosApp/MacApp/MacRootView.swift` conservaba texto literal `<<<<<<< HEAD` / `=======` / `>>>>>>> main` alrededor del `case .planner` del inspector de macOS (líneas ~518-534). Xcode no compilaba el archivo; el error no llegaba a mostrarse con claridad porque Xcode seguía usando el binario compilado antes del merge (build "sincronizado" en la UI, pero obsoleto).
2. **Cinco archivos Swift traídos por el merge nunca se dieron de alta en `MiGestorKMPiOS.xcodeproj`.** El merge añadió al árbol de git/disco `SyncStatusBadge.swift`, `SupportMeasureBulkImportSheet.swift`, `SupportMeasureGroupOverviewSheet.swift`, `SupportMeasureShared.swift` y `SupportMeasureBulkImport.swift`, pero el `project.pbxproj` no se actualizó con las referencias `PBXFileReference`/`PBXBuildFile`/`PBXSourcesBuildPhase` correspondientes en ninguno de los dos targets (`MiGestorKMPiOS`, `MiGestorKMPMac`). Los archivos existían en disco y en git, pero el compilador nunca los veía: de ahí los `Cannot find type 'SupportMeasureRow'/'SupportMeasureBulkImportResult'/...` y `Cannot find 'SyncStatusBadge' in scope`, y de ahí que la sección "Medidas de apoyo" no apareciera en ninguna build generada después del merge, aunque el código llevara semanas en `main`.
3. **Bug de concurrencia preexistente, no causado por el merge, descubierto al despejar los dos anteriores.** `MacStudentsStore` (clase `@MainActor`) cancelaba `profileLoadTask` en su `deinit`; Swift ejecuta `deinit` en contexto no aislado, por lo que acceder a una propiedad aislada al actor principal desde ahí es un error de compilación (`Main actor-isolated property 'profileLoadTask' can not be referenced from a nonisolated context`).

Nota: el aviso de "Missing package product 'CoreXLSX'/'ZIPFoundation'" que apareció durante el proceso **no** era un bug — el proyecto ya declaraba correctamente esas dependencias remotas de SPM; era una consecuencia esperada de borrar `~/Library/Developer/Xcode/DerivedData` (paso de diagnóstico legítimo), que obliga a Xcode a re-resolver los paquetes.

## Corrección aplicada

| Archivo | Cambio |
|---|---|
| `kmp/iosApp/MacApp/MacRootView.swift` | Eliminados los marcadores de conflicto, conservando el bloque `case .planner:` (usa `plannerInspectorSession`/`plannerToolbarActions`, ya en uso en el resto del archivo). |
| `kmp/iosApp/MiGestorKMPiOS.xcodeproj/project.pbxproj` | Se registran los 5 archivos huérfanos en ambos targets (`MiGestorKMPiOS`, `MiGestorKMPMac`), replicando la estructura de un archivo hermano ya correcto (`PhysicalTestsWorkspaceView.swift`): 1 `PBXFileReference` + 2 `PBXBuildFile` + entradas en el grupo (`App`/`AppleShared`) y en ambas `PBXSourcesBuildPhase`. Verificado con `plutil -lint` tras cada edición. |
| `kmp/iosApp/MacApp/MacStudentsView.swift` | `profileLoadTask` pasa a `nonisolated(unsafe)` para permitir su cancelación desde `deinit` sin violar el aislamiento de actor. |

## Verificación

- `plutil -lint` sobre `project.pbxproj` tras cada edición (sintaxis de plist válida).
- Barrido completo de `kmp/iosApp` comparando cada `.swift` contra las referencias del `.pbxproj` para descartar más archivos huérfanos (no se encontró ninguno adicional relacionado con este merge; `SwiftUiBootstrap.swift` aparece sin referenciar pero es un placeholder del commit inicial del repo, ajeno a esta incidencia).
- Compilación confirmada por el usuario en Xcode (`MiGestorKMPMac`) tras aplicar los tres cambios: build correcta, sección "Medidas de apoyo" visible.
- No se ha ejecutado `xcodebuild` de forma automatizada en este entorno (solo hay Command Line Tools instaladas, sin Xcode completo); la verificación de compilación la realizó el usuario.

## Lección para próximos merges de integración

Un merge puede reportarse como "resuelto" por git (sin marcadores restantes según `git status`) y aun así dejar el proyecto de Xcode desincronizado del árbol de archivos, porque **`project.pbxproj` es un artefacto que hay que fusionar explícitamente**, no algo que se derive automáticamente del contenido de las carpetas. Antes de dar por bueno un merge que toque `kmp/iosApp`, conviene:
1. `grep -rn "^<<<<<<<\|^=======$\|^>>>>>>>"` sobre los archivos tocados, por si el editor de conflictos dejó algo sin resolver.
2. Comparar la lista de `.swift` nuevos del merge contra las referencias del `.pbxproj` (`grep -c "<archivo>" project.pbxproj`), no solo compilar y confiar en el resultado en caché de Xcode.
