# Documentacion de Mi Gestor Evaluaciones

Este directorio es la fuente principal para entender que existe, que se ha decidido, que queda pendiente y como evoluciona la app.

## Documentos canonicos

- [REPO_GOVERNANCE.md](REPO_GOVERNANCE.md): reglas para ramas, commits, PRs, changelog, decisiones y versionado.
- [AGENT_WORKFLOW.md](AGENT_WORKFLOW.md): instrucciones operativas para que cualquier agente use las skills y registre avances.
- [ROADMAP.md](ROADMAP.md): mapa vivo de producto y prioridades.
- [CHANGELOG.md](CHANGELOG.md): cambios relevantes por version o tanda de trabajo.
- [PROJECT_BASELINE_2026-06-04.md](PROJECT_BASELINE_2026-06-04.md): fotografia inicial creada con la app ya empezada.
- [RELEASE_PROCESS.md](RELEASE_PROCESS.md): proceso interno de versionado, checks, evidencias y etiquetado.

## Documentos existentes

- [AVANCES_Y_MADUREZ_PREMIUM_2026-05-31.md](AVANCES_Y_MADUREZ_PREMIUM_2026-05-31.md): avances previos de madurez premium.
- [apple-ui-guidelines.md](apple-ui-guidelines.md): criterios Apple UI.
- [kmp/docs/architecture](../kmp/docs/architecture): ADRs y arquitectura KMP/Apple.
- [kmp/docs/uiux](../kmp/docs/uiux): auditorias, checklist y backlog UI/UX.

## Regla practica

Antes de crear un documento nuevo, comprobar si encaja en una de estas categorias:

- Producto y prioridades: `docs/ROADMAP.md`.
- Cambio entregado: `docs/CHANGELOG.md`.
- Decision tecnica duradera: `kmp/docs/architecture/ADR-YYYY-MM-DD-slug.md`.
- Calidad visual o accesibilidad: `kmp/docs/uiux/`.
- Auditorias o trabajos exploratorios: `.workflow/` como evidencia auxiliar, no como documentacion canonica.
