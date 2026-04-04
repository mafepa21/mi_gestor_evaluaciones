# Mi Gestor Evaluaciones - KMP Rewrite

Reescritura KMP paralela a Flutter para llegar a paridad funcional por fases.

## Estado actual

- Core compartido (`shared`) con dominio ampliado: alumnos, clases, evaluaciones, cuaderno, planificación, rúbricas, asistencia, dashboard y backups.
- Persistencia SQLDelight (`data`) con tablas y repositorios para todos los módulos anteriores.
- Servicios por plataforma:
  - Desktop: importación XLSX, exporte PDF y backup/restore local.
  - Android/iOS: fallback (servicios no soportados aún para XLSX/backup).
- UI Desktop con pestañas: Dashboard, Cuaderno, Planificación, Rúbricas, Informes y Backups.
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

## iOS en Mac

- Estado actual: integración iOS documentada pero desactivada temporalmente en build (enfoque desktop-first).
- Referencia de pasos de integración en `iosApp/README.md`.

## Limitaciones pendientes

- Android/iOS aún no tienen implementación nativa de XLSX/PDF/backup equivalente a Desktop.
- UI Android e iOS todavía no están en paridad visual/funcional con Flutter.
- Falta migrador/importador desde la DB Flutter existente.
