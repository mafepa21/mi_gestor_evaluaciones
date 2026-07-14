---
name: apple-build-verify
description: Automatiza y guía la verificación de compilación del target de iOS simulator y macOS native usando xcodegen y xcodebuild.
version: 1.0.0
---

# apple-build-verify

## Rol
Eres el encargado de asegurar la integridad y compatibilidad multiplataforma de la app Apple (iOS y macOS).
Tu misión es validar que cualquier cambio realizado en la UI SwiftUI (`kmp/iosApp/App/`, `kmp/iosApp/MacApp/`, `kmp/iosApp/AppleShared/`) o en el bridge (`KmpBridge.swift`) compile de forma limpia en ambos targets de Apple ANTES de finalizar la sesión.

## Cuándo usar este Skill
- Después de agregar, renombrar o eliminar cualquier archivo `.swift` en la app Apple.
- Tras realizar cambios en vistas comunes que se comparten entre plataformas.
- Tras modificar el puente de comunicación Swift-Kotlin (`KmpBridge.swift`).
- Antes de dar por terminada la conversación y marcar una tarea como completada.

## Proceso
1. Asegúrate de guardar todos los archivos modificados.
2. Ejecuta el script de verificación desde el directorio raíz del proyecto:
   ```bash
   ./scripts/verify_apple_builds.sh
   ```
3. Si ambos compilan correctamente (`✓ macOS Native / Catalyst: COMPILADO CORRECTAMENTE` y `✓ iOS Simulator: COMPILADO CORRECTAMENTE`), el build se considera validado.
4. Si hay fallos de compilación:
   - Revisa el archivo de log correspondiente (la ruta exacta, única por worktree, aparece en la salida del script, p. ej. `/tmp/mac_build_<worktree>.log` o `/tmp/ios_build_<worktree>.log`).
   - Identifica el archivo y la línea que causó el error de compilación.
   - En caso de errores por archivos inexistentes o no encontrados en Xcode, asegúrate de que `xcodegen generate` se haya ejecutado (el script lo hace automáticamente si `xcodegen` está instalado).

## Problemas comunes y soluciones
- **Error: "File not found" o archivos faltantes en Xcode**: Ocurre si se creó un archivo `.swift` y no se ha regenerado el `.xcodeproj`. Ejecutar `./scripts/verify_apple_builds.sh` soluciona esto porque corre `xcodegen generate` de entrada.
- **Error de firma de código (Code Signing)**: El script compila usando `CODE_SIGNING_ALLOWED=NO` para saltarse los requisitos de perfil de aprovisionamiento en la CLI. Si de todos modos hay fallos de firmas, valida que no haya overrides manuales estrictos de firma en `project.yml`.
- **Cachés corruptas o DerivedData conflictivo**: Si ves errores extraños que no parecen relacionados con tu código, limpia el DerivedData temporal borrando los directorios `/tmp/MiGestorMacBuildVerify_<worktree>` o `/tmp/MiGestorIOSBuildVerify_<worktree>` (el script los recrea automáticamente en cada ejecución) y vuelve a ejecutar.

## Salida esperada
- Reportar los resultados de la compilación para ambos targets.
- Si falló alguno, extraer las líneas más relevantes del error en el log respectivo para solucionarlo quirúrgicamente.
