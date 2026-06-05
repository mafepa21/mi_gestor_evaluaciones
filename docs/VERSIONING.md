# Versionado y registro en GitHub

Este documento define como versionar Mi Gestor Evaluaciones y como debe quedar registrado cada cambio en GitHub. La fuente oficial del codigo es el repositorio privado de GitHub; la copia local es solo el espacio de trabajo.

## Estado actual

- Version interna actual: `0.3.0-dev`.
- No crear tag `v0.3.0` mientras no exista una build reproducible, verificada y documentada.
- La primera version candidata esperada es `v0.3.0-alpha.1`.
- Ningun workflow crea tags por push. La publicacion de GitHub Release es manual con `workflow_dispatch`.

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
- `alpha.N`: fotografia interna verificable. Puede tener deudas conocidas, pero debe tener checks de seguridad y versionado verdes.
- `beta.N`: version candidata para uso controlado con flujos principales cubiertos, evidencias de build y riesgos documentados.
- `rc.N`: candidata final antes de estable, sin cambios funcionales previstos salvo fixes bloqueantes.
- sin sufijo: release estable, con changelog cerrado, evidencia reproducible y revision comercial/legal suficiente para el alcance.

## Ramas

Regla principal: `main` no se toca directamente. Todo cambio entra por PR.

Ramas recomendadas:

- `codex/ui-nombre-corto`
- `codex/fix-nombre-corto`
- `codex/feature-nombre-corto`
- `codex/docs-nombre-corto`
- `codex/docs-release-automation`
- `release/x.y.z-pre.n` para preparar una release formal.

Cada rama debe tener una intencion dominante. Si un cambio mezcla UI, KMP, data y documentacion, separar PRs salvo dependencia real.

## Pull requests y checks automaticos

PRs normales:

- Usan ramas `codex/*` o equivalentes.
- Activan `.github/workflows/pr-check.yml`.
- Deben pasar `scripts/verify_no_sensitive_files.sh` y `scripts/check_version_consistency.sh`.
- Pueden apoyarse ademas en los workflows existentes de KMP y Apple cuando el alcance lo requiera.

PRs de release:

- Usan rama `release/x.y.z[-alpha.N|-beta.N|-rc.N]`.
- Activan `.github/workflows/release-check.yml` en PR y push a `release/**`.
- Generan `release-evidence.md` como artifact de CI.
- No crean tags ni GitHub Releases automaticamente.

Publicacion de release:

- Usa `.github/workflows/publish-release.yml`.
- Solo se ejecuta por `workflow_dispatch`.
- Exige que el tag `vX.Y.Z[-pre.N]` ya exista.
- Publica una GitHub Release en modo draft, salvo que se deje en `dry_run`.

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

### Script de automatización de registro (`scripts/auto_commit_pr.sh`)

Para automatizar este flujo localmente, disponemos del script `scripts/auto_commit_pr.sh`. Este script realiza de forma secuencial:
1. Validación de cambios locales pendientes.
2. Comprobación de que no se cometen commits directamente sobre `main` (bloqueado por seguridad).
3. Ejecución del escáner de seguridad de archivos sensibles (`verify_no_sensitive_files.sh`).
4. Selección guiada (o por argumentos) del tipo de commit y el mensaje.
5. Stage automático de los cambios, commit con el formato correcto, push a la rama en GitHub.
6. Creación o actualización automática del Pull Request en GitHub usando la CLI oficial (`gh`), utilizando la plantilla oficial del proyecto `.github/pull_request_template.md` y en modo borrador (draft) para protección extra.

Uso:
```bash
# De forma interactiva (asistida)
scripts/auto_commit_pr.sh

# O pasando los parámetros directamente
scripts/auto_commit_pr.sh feat "implement physical test metrics UI popover"
```

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
Los scripts y workflows de este repositorio no crean tags reales. La creacion del tag es una accion humana explicita.

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
`scripts/check_version_consistency.sh` compara el SemVer base `X.Y.Z`. Para `0.3.0-alpha.1`, los manifests pueden seguir usando `0.3.0` mientras el tag y la release usan el pre-release completo.

## Checklist de release candidata

1. Rama creada desde `main` actualizado: `release/x.y.z-pre.n`.
2. `docs/CHANGELOG.md` contiene entrada de version o bloque preparado desde `Unreleased`.
3. Manifests activos alineados con la version objetivo.
4. `scripts/verify_no_sensitive_files.sh` pasa.
5. `scripts/check_version_consistency.sh X.Y.Z[-pre.N]` pasa.
6. `scripts/collect_release_evidence.sh X.Y.Z[-pre.N]` genera evidencia.
7. Checks KMP/data ejecutados si aplica.
8. Build Apple ejecutado si aplica.
9. PR de release abierto con pruebas, riesgos y evidencias.
10. CI verde en GitHub.
11. Merge a `main`.
12. Tag anotado `vX.Y.Z[-pre.N]` creado manualmente sobre `main`.
13. `publish-release.yml` ejecutado manualmente con `workflow_dispatch`.

## Scripts de soporte

- `scripts/verify_no_sensitive_files.sh`: bloquea `.db`, `.sqlite`, `.sqlite3`, `.env`, `.dmg`, `.app`, backups, logs y secretos. Las unicas excepciones futuras permitidas son `tests/fixtures/anonymous_*` y `tests/fixtures/demo_*`.
- `scripts/check_version_consistency.sh`: valida que los manifests activos comparten el mismo SemVer base.
- `scripts/create_release_candidate.sh`: crea o cambia a `release/x.y.z[-pre.N]`, ejecuta checks de seguridad/versionado y no crea tags.
- `scripts/collect_release_evidence.sh`: imprime un resumen Markdown de rama, commit, checks esperados y snapshot local de seguridad/versionado.

## Backup externo

GitHub privado es la fuente oficial, pero se recomienda un mirror periodico:

```bash
git clone --mirror git@github.com:mafepa21/mi_gestor_evaluaciones.git mi_gestor_evaluaciones.git
```

El mirror puede guardarse en disco externo, iCloud Drive, Google Drive, NAS o un segundo remoto privado. Nunca debe contener artefactos o datos reales que no deban estar en Git.
