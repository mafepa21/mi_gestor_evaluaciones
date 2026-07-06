# Workflow para agentes

Este documento explica como debe trabajar cualquier agente en Mi Gestor Evaluaciones para que cada cambio quede documentado, revisable y trazable.

## Entrada obligatoria

Antes de modificar archivos:

1. Leer `AGENTS.md`.
2. Revisar `docs/REPO_GOVERNANCE.md`.
3. Ejecutar o consultar `git status --short --branch`.
4. Identificar la skill principal segun la tarea.

## Skills del proyecto

Las skills locales viven en:

```text
.agents/skills/
```

Skills tecnicas frecuentes:

- `swiftui-polish`: mejoras visuales SwiftUI.
- `swiftui-bugfix`: bug concreto SwiftUI.
- `swiftui-native-feature`: feature nativa Apple.
- `swiftui-macos-adapt`: adaptacion macOS.
- `kmp-bridge-fix`: binding Swift-KMP.
- `kmp-logic-fix`: logica compartida KMP.
- `sqldelight-fix`: bug de persistencia SQLDelight sin cambio de esquema.
- `sqldelight-migration`: evolucion segura de esquema, tablas y migraciones.
- `apple-service-patch`: servicios Apple.

Skills de dominio (usar cuando la tarea cae en su area, tienen prioridad sobre las genericas):

- `kmp-feature-vertical`: feature completa que atraviesa SQLDelight -> repositorio -> contrato -> ViewModel -> KmpBridge -> SwiftUI.
- `planner-workspace`: modulo Planificacion (Semana, Dia, Secuencia, Resumen, composer, PDF).
- `liquid-glass-design`: adopcion y correccion de Liquid Glass iOS/macOS 26 con fallbacks.
- `apple-intelligence-service`: servicios de IA local Foundation Models (insights, EarlyWarning, informes, orchestrator).
- `adaptive-layout-apple`: patron adaptativo iPad-first, sheets con detents, bugs de controles cortados.
- `synclan-debug`: sincronizacion LAN Mac <-> iPad (helper, SSE, debounce, crashes de sync).
- `release-prep`: release candidates, consistencia de version, evidencias, tag y GitHub Release.

Skill transversal de cierre:

- `registrar-avance-app`: documentar avance, changelog, roadmap, ADRs, evidencias, commits y PR.

## Regla de uso de `registrar-avance-app`

Usar `registrar-avance-app` cuando el cambio:

- modifique producto o UX,
- toque SwiftUI iOS/macOS,
- toque KMP, SQLDelight, sync, backups o bridge,
- cambie scripts, Xcode, Gradle o CI,
- añada o modifique tests,
- cree una decision tecnica,
- cierre una fase de roadmap,
- prepare un PR o una release.

No usarla para respuestas puramente conversacionales sin cambio en el repo.

## Secuencia recomendada

1. Diagnosticar el problema y elegir una skill tecnica principal.
2. Hacer cambios pequeños y acotados.
3. Ejecutar comprobaciones relevantes.
4. Usar `registrar-avance-app` para decidir si actualizar:
   - `docs/CHANGELOG.md`,
   - `docs/ROADMAP.md`,
   - `kmp/docs/architecture/ADR-YYYY-MM-DD-slug.md`,
   - `.workflow/`,
   - `memoria`,
   - PR body.
5. Agrupar commits por intencion.
6. Abrir o actualizar PR.

## Agrupacion de commits

Tipos recomendados:

- `docs`: documentacion, plantillas, evidencia, memoria.
- `feat`: funcionalidad nueva.
- `fix`: correccion funcional.
- `ui`: cambios SwiftUI/UX.
- `data`: SQLDelight, repositorios, migraciones.
- `kmp`: shared, contratos, viewmodels.
- `build`: Gradle, Xcode, scripts, CI.
- `test`: tests, fakes, fixtures.
- `refactor`: cambio interno sin cambio funcional esperado.

Si el working tree esta mezclado, agrupar por rutas solo cuando la intencion sea clara. No partir hunks complejos si eso puede romper coherencia logica.

## Documentacion que debe quedar al cerrar

Todo PR relevante debe incluir:

- resumen,
- alcance,
- archivos o modulos afectados,
- que se ha probado,
- que no se ha probado,
- riesgos,
- cambios no realizados,
- enlace a ADR si aplica,
- entrada de changelog si aplica.

## Comprobaciones esperadas

Elegir segun alcance:

- KMP/shared: `./gradlew :shared:test`.
- SQLDelight/data: `./gradlew :data:desktopTest`.
- iOS/macOS Apple: `xcodebuild` con el esquema afectado.
- UI: build y, si procede, capturas o QA manual.
- Documentacion pura: revisar diff, enlaces y estado Git.

No inventar comandos. Si un comando falla por entorno, registrar el fallo y el motivo.

## PRs

Si ya existe PR para la rama, actualizarlo. Si no existe, crearlo usando `.github/pull_request_template.md`.

El PR debe representar una intencion dominante. Si no se puede separar porque la rama acumula dependencias, explicarlo en riesgos.
