# Mi Gestor Evaluaciones - KMP Rewrite

Reescritura KMP paralela a Flutter para llegar a paridad funcional por fases.

## Estado actual

Version interna actual: `0.3.0-dev`. KMP + SwiftUI Apple es el producto activo principal; Flutter queda como legado o referencia pendiente de decision formal.

- Core compartido (`shared`) con dominio ampliado: alumnos, clases, evaluaciones, cuaderno, planificación, rúbricas, asistencia, dashboard y backups.
- Persistencia SQLDelight (`data`) con tablas y repositorios para todos los módulos anteriores.
- Servicios por plataforma:
  - Desktop: importación XLSX, exporte PDF y backup/restore local.
  - Apple iOS/macOS: servicios nativos en evolucion para importacion, backups, sync local y soporte de flujos docentes.
  - Android: MVP operativo con servicios pendientes de paridad.
- UI Desktop con pestañas: Dashboard, Cuaderno, Planificación, Rúbricas, Informes y Backups.
- SwiftUI iOS/iPadOS y macOS activos en `iosApp/`.
- Android app MVP operativa.

## Ejecutar en macOS

Desde `kmp/`:

- Ejecutar Desktop: `./gradlew :desktopApp:run`
- Empaquetar `.dmg`: `./gradlew :desktopApp:packageDmg`
- Tests shared: `./gradlew :shared:test`
- Tests data (desktop): `./gradlew :data:desktopTest`
- Guía completa para generar el DMG: [DMG_MACOS.md](./DMG_MACOS.md)

Atajos:

- `./scripts/run_desktop.sh`
- `./scripts/package_mac.sh`

### Runtime recomendado para macOS

- Para el empaquetado Desktop en macOS, usar JDK 17 de distribución (Temurin) y no OpenJDK de Homebrew para evitar fallos AWT al arrancar (`RegisterApplication`).
- Ruta usada en este proyecto: `/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home`.

## Apple iOS/macOS

- Proyecto XcodeGen en `iosApp/project.yml`.
- Targets activos: `MiGestorKMPiOS` y `MiGestorKMPMac`.
- Verificacion recomendada desde la raiz: `scripts/verify_apple_builds.sh`.
- Detalles de integracion Apple en `iosApp/README.md`.

## Limitaciones pendientes

- Android no tiene todavia implementacion nativa de XLSX/PDF/backup equivalente a Desktop/Apple.
- Flutter queda pendiente de clasificar como legado, referencia o target mantenido.
- Falta migrador/importador desde la DB Flutter existente.
