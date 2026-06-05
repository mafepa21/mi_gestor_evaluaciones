# Release process

Este documento define el proceso interno para preparar versiones reproducibles de Mi Gestor Evaluaciones. Hasta que haya distribucion publica, la version actual del producto es `0.3.0-dev`.

La guia completa de ramas, commits, tags, GitHub Releases y registro automatico por PR vive en `docs/VERSIONING.md`.

## Versiones internas

- `0.1.x`: base tecnica y paridad funcional principal.
- `0.2.x`: estabilizacion de cuaderno, rubricas, asistencia y planificacion.
- `0.3.x`: macOS nativo, sync, backups e informes maduros.
- `0.4.x`: preparacion comercial: onboarding, seguridad, exportaciones, soporte y documentacion.
- `1.0.0`: version lista para uso real estable y evaluable externamente.

`0.3.0-dev` no debe etiquetarse como release. Representa el estado interno actual mientras se estabilizan builds, CI y evidencia de calidad.

## Preparar una release

1. Crear una rama `codex/release-x-y-z` desde `main` actualizado.
2. Actualizar versiones en los manifiestos activos:
   - `kmp/iosApp/project.yml` y el proyecto Xcode versionado si no se regenera en el mismo commit.
   - `kmp/androidApp/build.gradle.kts` si Android KMP participa en la tanda.
   - `pubspec.yaml` mientras Flutter siga en el repo como legado o referencia versionada.
3. Actualizar `docs/CHANGELOG.md` moviendo cambios relevantes de `Unreleased` a la version preparada.
4. Ejecutar comprobaciones obligatorias y guardar evidencia en el PR.
5. Abrir PR con la plantilla oficial y una intencion dominante.
6. Etiquetar `vX.Y.Z` solo despues de mergear una version reproducible y verificada.

Para preparar la rama sin crear tags reales:

```bash
scripts/create_release_candidate.sh 0.3.0-alpha.1
```

## Checks obligatorios

- KMP/shared: `./gradlew :shared:test` desde `kmp/`.
- SQLDelight/data: `./gradlew :data:desktopTest` desde `kmp/`.
- Apple: `scripts/verify_apple_builds.sh` desde la raiz.
- Documentacion pura: revisar `git diff --stat`, enlaces Markdown y estado Git.
- Release safety: `scripts/verify_no_sensitive_files.sh` desde la raiz.

Si un check no puede ejecutarse por entorno, el PR debe registrar el comando, el fallo exacto y el motivo.

## Evidencia minima

Cada PR de release debe incluir:

- resumen de alcance,
- version objetivo,
- commits o PRs incluidos,
- casos probados,
- casos no probados con motivo,
- riesgos conocidos,
- capturas o logs si afecta a UI o build,
- enlace al changelog.

## Artefactos y privacidad

No se versionan bases SQLite locales, `.db`, `.sqlite`, `.sqlite3`, bundles generados, apps, DMG ni datos reales de alumnado. Si hace falta un fixture, debe ser anonimo, minimo y vivir en una ruta de tests claramente documentada.
