# Baseline inicial del proyecto - 2026-06-04

## Motivo

La app ya estaba empezada antes de implantar una disciplina formal de documentacion, PRs, changelog y versionado. Este documento fija una fotografia inicial para no depender de memoria oral ni intentar reconstruir un historial perfecto.

## Estructura observada

- `README.md`: actualizado para describir el estado real del proyecto.
- `docs/`: documentacion canonica general.
- `kmp/README.md`: descripcion de la reescritura KMP.
- `kmp/shared/`: dominio y viewmodels KMP.
- `kmp/data/`: SQLDelight, repositorios y servicios de datos.
- `kmp/iosApp/App/`: app Apple iOS/iPadOS.
- `kmp/iosApp/MacApp/`: app Apple macOS.
- `kmp/iosApp/AppleShared/`: servicios Apple compartidos.
- `kmp/desktopApp/`: Compose Desktop.
- `lib/` y targets Flutter: app original o legado activo pendiente de clasificar.
- `.workflow/`: auditorias, planes y resultados generados; utiles como evidencia auxiliar, pero no documentacion canonica.

## Documentacion existente relevante

- `AGENTS.md`: reglas operativas del repo y rutas protegidas.
- `kmp/docs/architecture/ADR-2026-04-14-apple-dual-target.md`: decision de contenedor Apple dual.
- `kmp/docs/architecture/MACOS_PARITY_MATRIX.md`: matriz inicial de paridad macOS.
- `kmp/docs/uiux/UX_DOD_CHECKLIST.md`: checklist UI/UX.
- `kmp/docs/uiux/UIUX_IMPLEMENTATION_BACKLOG.md`: backlog UI/UX.
- `docs/AVANCES_Y_MADUREZ_PREMIUM_2026-05-31.md`: registro previo de avances.

## Estado Git observado

Fecha de observacion: 2026-06-04.

- Rama actual: `codex/fix-addcolumnsheet-onchange`.
- Hay muchos cambios sin commitear en SwiftUI, KMP, SQLDelight, scripts y documentacion.
- Hay archivos nuevos sin seguimiento relacionados con situaciones de aprendizaje, gestion de grupos, servicios Apple y migraciones SQLDelight.

## Implicacion

Antes de crear una release o PR grande, conviene agrupar el trabajo pendiente por intencion:

- Documentacion y gobierno del repo.
- Cambios Apple SwiftUI.
- Cambios KMP/shared.
- Cambios SQLDelight/data.
- Cambios de build/proyecto.
- Servicios Apple y sync.
- Tests.

Cada grupo deberia convertirse en un PR pequeno o, si ya esta mezclado, en una serie de PRs con alcance cuidadosamente explicado.

## Riesgos iniciales

- El README raiz no representaba el producto real hasta esta actualizacion.
- La convivencia Flutter + KMP necesita una decision documentada: legado, referencia, migracion activa o target mantenido.
- Los cambios sin commitear pueden mezclar decisiones independientes.
- Tocar SQLDelight, KMP y SwiftUI en un mismo PR dificulta revisar, probar y vender la trazabilidad del proyecto.

## Proxima accion recomendada

Crear un primer PR solo documental con:

- `README.md`
- `docs/README.md`
- `docs/REPO_GOVERNANCE.md`
- `docs/CHANGELOG.md`
- `docs/ROADMAP.md`
- `docs/PROJECT_BASELINE_2026-06-04.md`
- `.github/pull_request_template.md`

Despues, revisar el working tree actual y separar los cambios tecnicos en paquetes revisables.

## Actualizacion operativa - 2026-06-04

- `origin/main` incluye el PR #7: `Document governance and expand Apple/KMP learning workflows`.
- La rama `codex/fix-addcolumnsheet-onchange` no mantiene diff pendiente contra `origin/main`.
- El PR #6 quedo redundante y conflictivo porque sus commits ya estaban integrados en `main`; se cerro con comentario explicativo.
- El working tree usado para preparar la rama de gobernanza estaba limpio antes de crear `codex/docs-operational-readiness`.
- La siguiente disciplina operativa queda centrada en CI minimo, versionado interno `0.3.0-dev`, release process y exclusion de artefactos locales.
