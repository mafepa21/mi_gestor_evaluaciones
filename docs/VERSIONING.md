# Versionado y registro en GitHub

Este documento define como versionar Mi Gestor Evaluaciones y como debe quedar registrado cada cambio en GitHub. La fuente oficial del codigo es el repositorio privado de GitHub; la copia local es solo el espacio de trabajo.

## Estado actual

- Version interna actual: `0.3.0-dev`.
- No crear tag `v0.3.0` mientras no exista una build reproducible, verificada y documentada.
- La primera version candidata esperada es `v0.3.0-alpha.1`.

## SemVer interno

Formato:

```text
MAJOR.MINOR.PATCH[-pre.N]
```

Criterio:

- `0.3.x`: app interna funcional, macOS nativo, sync, backups e informes en maduracion.
- `0.4.x`: preparacion comercial, onboarding, privacidad, exportaciones y soporte.
- `1.0.0`: version estable, documentada, revisada legalmente y evaluable externamente.

Pre-releases:

- `dev`: trabajo diario, no se etiqueta.
- `alpha.N`: fotografia interna verificable.
- `beta.N`: version candidata para uso controlado con flujos principales cubiertos.
- `rc.N`: candidata final antes de estable.
- sin sufijo: release estable.

## Ramas

Regla principal: `main` no se toca directamente. Todo cambio entra por PR.

Ramas recomendadas:

- `codex/ui-nombre-corto`
- `codex/fix-nombre-corto`
- `codex/feature-nombre-corto`
- `codex/docs-nombre-corto`
- `codex/release-x-y-z`
- `release/x.y.z-pre.n` cuando se prepare una release formal fuera del prefijo Codex.

Cada rama debe tener una intencion dominante. Si un cambio mezcla UI, KMP, data y documentacion, separar PRs salvo dependencia real.

## Registro automatico de cada cambio

Cada vez que Codex cambie la app o documentacion relevante debe cerrar la tarea con este registro minimo:

1. Revisar `git status --short --branch`.
2. Clasificar la intencion: `docs`, `ui`, `fix`, `feat`, `kmp`, `data`, `build`, `test` o `refactor`.
3. Actualizar `docs/CHANGELOG.md` cuando haya impacto en producto, arquitectura, UX, build, datos, tests o proceso.
4. Ejecutar los checks relevantes o registrar por que no aplican.
5. Crear commit claro.
6. Empujar la rama.
7. Abrir o actualizar PR con `.github/pull_request_template.md`.

Este proceso no sustituye la revision humana. Automatiza la trazabilidad: rama, commit, PR, pruebas, riesgos y changelog quedan creados o actualizados como parte normal de cada entrega.

## Commits

Formato recomendado:

```text
tipo: resumen corto
```

Ejemplos:

- `ui: polish notebook average popover`
- `fix: prevent orphan notebook columns`
- `docs: formalize release versioning`
- `build: add release safety checks`

## Tags

Crear tags solo tras mergear una version reproducible y verificada:

```bash
git tag -a v0.3.0-alpha.1 -m "v0.3.0-alpha.1"
git push origin v0.3.0-alpha.1
```

El tag debe apuntar al commit final integrado en `main`, no a una rama temporal sin mergear.

## GitHub Releases

Cada tag publicable debe tener GitHub Release con:

- version,
- resumen,
- PRs o commits incluidos,
- checks ejecutados,
- checks no ejecutados y motivo,
- riesgos conocidos,
- enlace a `docs/CHANGELOG.md`,
- artefactos o evidencias si aplican.

No adjuntar bases de datos reales, backups reales, logs con datos de alumnado, `.app`, `.dmg` o capturas identificables salvo canal seguro y aprobado.

## Versiones en manifests

Antes de una release se deben alinear los manifests activos:

- `kmp/iosApp/project.yml`.
- Proyecto Xcode versionado si no se regenera en el mismo commit.
- `kmp/androidApp/build.gradle.kts` si Android participa en la tanda.
- `pubspec.yaml` solo mientras Flutter siga en el repo como legado o referencia versionada.

No modificar manifests de version en cambios diarios que no preparen release.

## Checklist de release candidata

1. Rama creada desde `main` actualizado: `codex/release-x-y-z` o `release/x.y.z-pre.n`.
2. `docs/CHANGELOG.md` contiene entrada de version o bloque preparado desde `Unreleased`.
3. Manifests activos alineados con la version objetivo.
4. `scripts/verify_no_sensitive_files.sh` pasa.
5. Checks KMP/data ejecutados si aplica.
6. Build Apple ejecutado si aplica.
7. PR de release abierto con pruebas, riesgos y evidencias.
8. CI verde en GitHub.
9. Merge a `main`.
10. Tag anotado `vX.Y.Z[-pre.N]`.
11. GitHub Release creada con release notes.

## Backup externo

GitHub privado es la fuente oficial, pero se recomienda un mirror periodico:

```bash
git clone --mirror git@github.com:mafepa21/mi_gestor_evaluaciones.git mi_gestor_evaluaciones.git
```

El mirror puede guardarse en disco externo, iCloud Drive, Google Drive, NAS o un segundo remoto privado. Nunca debe contener artefactos o datos reales que no deban estar en Git.
