# Gobierno del repositorio

## Objetivo

Mantener la app preparada para escalar, colaborar, auditar cambios y, si llega el caso, presentar el proyecto con trazabilidad suficiente para venta, transferencia o due diligence tecnica.

## Principios

- Cambios pequenos, revisables y con una intencion clara.
- Una rama por entrega funcional, bugfix o decision tecnica.
- Un PR debe explicar el problema, la solucion, los riesgos y las pruebas.
- La documentacion vive cerca de la decision: producto en `docs/`, arquitectura en `kmp/docs/architecture/`, UI/UX en `kmp/docs/uiux/`.
- No mezclar refactors globales con features.
- No tocar KMP, SQLDelight o `KmpBridge.swift` sin justificarlo expresamente.
- Cualquier agente debe seguir `AGENTS.md`, `docs/AGENT_WORKFLOW.md` y la skill `registrar-avance-app` al cerrar cambios.

## Workflow para agentes

La guia operativa para agentes vive en `docs/AGENT_WORKFLOW.md`.

Regla corta:

1. Elegir una skill tecnica principal para implementar o revisar.
2. Hacer cambios pequenos y verificables.
3. Usar `registrar-avance-app` como capa final de documentacion y trazabilidad.
4. Agrupar commits por intencion.
5. Abrir o actualizar PR con pruebas, riesgos y alcance.

## Ramas

Formato recomendado:

- `codex/feature-nombre-corto`
- `codex/fix-nombre-corto`
- `codex/docs-nombre-corto`
- `codex/audit-nombre-corto`
- `codex/release-x-y-z`

Ejemplos:

- `codex/docs-repo-governance`
- `codex/fix-notebook-hidden-columns`
- `codex/feature-learning-situations`
- `codex/audit-macos-parity`

## Commits

Usar mensajes concretos, en ingles o espanol, pero consistentes dentro de una rama.

Formato recomendado:

```text
tipo: resumen corto
```

Tipos utiles:

- `docs`: documentacion, plantillas, decisiones.
- `fix`: correccion de bug.
- `feat`: funcionalidad nueva.
- `ui`: mejora visual o interaccion.
- `data`: SQLDelight, repositorios, migraciones.
- `kmp`: shared, viewmodels o contratos.
- `build`: Gradle, Xcode, scripts, CI.
- `test`: pruebas.
- `refactor`: cambio interno sin cambio funcional esperado.

## Pull requests

Cada PR debe incluir:

- Resumen.
- Alcance exacto.
- Archivos o modulos afectados.
- Casos probados.
- Riesgos.
- Cambios no realizados.
- Capturas o evidencias si afecta a UI.
- Entrada de changelog si el cambio afecta a producto, datos, arquitectura, build o UX.

La plantilla oficial del proyecto con la estructura requerida vive en [.github/pull_request_template.md](file:///Users/mariofernandez/Projects/mi_gestor_evaluaciones/.github/pull_request_template.md).

### Formato Exigido para Pull Requests

Cada PR debe seguir obligatoriamente esta estructura de bloques para asegurar la trazabilidad del cambio:

1. **Resumen:** De 2 a 5 líneas describiendo brevemente qué cambia y por qué.
2. **Alcance:** Lista detallada de los límites de la intervención técnica.
3. **Archivos o módulos afectados:** Listado de los ficheros implicados.
4. **Cambios realizados:** Descripción de las modificaciones.
5. **Qué no se ha tocado:** Exclusión explícita de componentes fuera de alcance para acotar regresiones.
6. **Riesgos:** Identificación de riesgos residuales o dependencias.
7. **Casos probados:** Checklist de validación (Build iOS/macOS, tests de KMP/shared, SQLDelight y capturas de pantalla de UI).
8. **Documentación:** Links y menciones a ADRs, Roadmap o Changelog actualizados.
9. **Evidencias:** Logs de compilación, logs de ejecución de tests o imágenes que evidencien el funcionamiento real.

## CI y verificaciones

Los PRs deben apoyarse en checks automaticos siempre que el entorno lo permita:

- KMP/shared: `./gradlew :shared:test`.
- SQLDelight/data: `./gradlew :data:desktopTest`.
- Apple iOS/macOS: `scripts/verify_apple_builds.sh`.

Flutter queda fuera del CI obligatorio mientras se decide si es legado, referencia o target activo.

## Changelog

`docs/CHANGELOG.md` registra cambios relevantes con este criterio:

- `Added`: funcionalidades nuevas.
- `Changed`: cambios funcionales o de UX.
- `Fixed`: bugs corregidos.
- `Data`: cambios de persistencia, migraciones o repositorios.
- `Docs`: documentacion relevante.
- `Verification`: pruebas, builds o auditorias.

No registrar microcambios cosmeticos sin impacto. Si un PR es puramente interno, basta con el resumen del PR salvo que afecte a arquitectura o mantenibilidad.

## ADRs

Crear o actualizar un ADR cuando una decision sea dificil de revertir o explique el futuro del proyecto.

Ubicacion:

```text
kmp/docs/architecture/ADR-YYYY-MM-DD-slug.md
```

Estructura minima:

```md
# ADR-YYYY-MM-DD: Titulo

## Estado
Propuesto | Aprobado | Reemplazado

## Contexto

## Decision

## Consecuencias
```

## Versionado

Hasta que haya releases publicas, usar fases internas:

- `0.1.x`: base tecnica y paridad funcional principal.
- `0.2.x`: estabilizacion de cuaderno, rubricas, asistencia y planificacion.
- `0.3.x`: macOS nativo, sync, backups e informes maduros.
- `0.4.x`: preparacion comercial: onboarding, seguridad, exportaciones, soporte y documentacion.
- `1.0.0`: version lista para uso real estable y evaluable externamente.

Version interna actual: `0.3.0-dev`. No etiquetar `v0.3.0` hasta tener una build reproducible con checks verdes y evidencia registrada.

Cuando una version se cierre:

1. Crear entrada en `docs/CHANGELOG.md`.
2. Crear rama `codex/release-x-y-z` si hace falta preparar ajustes finales.
3. Etiquetar con `vX.Y.Z` cuando el estado sea reproducible.
4. Guardar evidencias de build/pruebas en el PR o release notes.

## Recuperacion del historial anterior

Como la app ya estaba empezada, no conviene inventar un historial perfecto. El enfoque recomendado es:

1. Documentar la fotografia inicial en `docs/PROJECT_BASELINE_2026-06-04.md`.
2. Revisar cambios grandes sin commitear y agruparlos por intencion.
3. Convertir cada grupo en PR pequeno cuando sea posible.
4. Crear ADRs solo para decisiones tecnicas que sigan condicionando el futuro.
5. Usar `.workflow/` como evidencia auxiliar de auditorias y planes, no como fuente canonica.

## Proceso futuro mínimo (Post-Baseline)

A partir de la baseline `v0.3.0-traceability-baseline`, se aplican las siguientes cinco reglas operativas obligatorias para el control y la trazabilidad de los cambios:

1. **Una tarea o issue antes de abrir una rama**: Cada rama de desarrollo (creada por un humano o un agente de IA) debe estar asociada a una issue abierta en GitHub que describa el alcance.
2. **Una pull request por objetivo funcional**: Cada PR debe centrarse en un único propósito y documentar claramente el problema, las decisiones tomadas, los casos probados y los riesgos residuales.
3. **Squash merge obligatorio para ramas de IA**: Las ramas generadas por agentes de IA se integrarán en `main` mediante *Squash and Merge*, resultando en un único commit atómico revisado y redactado por el desarrollador.
4. **Referencia obligatoria a la issue**: Tanto el cuerpo del PR como el mensaje del commit final de squash deben contener la referencia explícita a la issue que resuelven (por ejemplo, `Closes #123`).
5. **Tag + Release + evidencia de validación**: Cualquier versión distribuible o candidata a producción debe ser etiquetada en Git (`vX.Y.Z`), tener una GitHub Release asociada y registrar su hoja de evidencias de validación en `docs/audit/validation/`.


## Artefactos locales y privacidad

No versionar bases SQLite locales, `.db`, `.sqlite`, `.sqlite3`, bundles generados, apps, DMG ni datos reales de alumnado. Si hace falta un fixture de datos, debe ser anonimo, minimo y vivir en una ruta de tests documentada.

`.workflow/` puede mantenerse como evidencia auxiliar cuando ayude a auditar decisiones o planes, pero la fuente canonica sigue siendo `docs/`, ADRs, changelog, PRs y tests.
