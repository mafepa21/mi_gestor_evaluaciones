---
name: registrar-avance-app
description: Documenta avances, cambios, decisiones, versiones y PRs de Mi Gestor Evaluaciones. Usar cuando Codex implemente o revise un cambio de la app y deba actualizar changelog, roadmap, baseline, ADRs, notas de PR, evidencias o documentacion de seguimiento.
---

# Registrar Avance App

## Objetivo

Dejar cada avance de Mi Gestor Evaluaciones trazable, revisable y util para escalar, vender o transferir el proyecto en el futuro.

## Workflow obligatorio

0. Rama y worktree: nunca trabajar ni commitear sobre `main`. `git fetch` y crear rama nueva desde `origin/main` actualizado (`fix/...`, `feat/...`, `docs/...`, `ui/...`, `build/...`), en un `git worktree` propio y aislado — el checkout principal suele tener otras sesiones en paralelo. Verificar `git status --short --branch` antes de tocar nada.
1. Revisar el alcance real del cambio con `git status --short` y `git diff --stat`.
2. Clasificar el cambio por intencion principal:
   - `docs`: documentacion, procesos, plantillas.
   - `ui`: SwiftUI, UX, accesibilidad, diseño visual.
   - `fix`: correccion funcional.
   - `feat`: funcionalidad nueva.
   - `kmp`: dominio, contratos, viewmodels o logica compartida.
   - `data`: SQLDelight, repositorios, migraciones o persistencia.
   - `build`: Gradle, Xcode, scripts, CI o configuracion.
   - `test`: pruebas o fixtures.
   - `refactor`: cambio interno sin cambio funcional esperado.

   Commits atomicos: un commit por bug o intencion, formato `tipo(ambito): descripcion en español`. No mezclar bugs ni ambitos (UI / KMP / SQLDelight / docs) en un mismo commit salvo dependencia real.
3. Actualizar `docs/CHANGELOG.md` **en el mismo commit** que el cambio que documenta, bajo `## Unreleased`, en la seccion correcta (ver "Criterio de changelog").
4. Actualizar `docs/ROADMAP.md` si cambia una prioridad, se cierra una fase o aparece una deuda relevante.
5. Crear o actualizar un ADR en `kmp/docs/architecture/` si la decision condiciona arquitectura, persistencia, KMP, Apple targets, sync, backups o distribucion.
6. Si la tarea agrupa varios bugs, dejar el plan en la raiz como `plan_correccion_bugs_<tema>_<fecha>.md` y commitearlo con `docs(plan): ...`.
7. Registrar evidencias de verificacion:
   - comando ejecutado,
   - resultado,
   - si no se pudo ejecutar, motivo concreto (fallo preexistente de CI, entorno, etc.). Nunca afirmar que algo compilo o paso tests si no se ejecuto.
8. Push de la rama y apertura o actualizacion de PR contra `main` con la plantilla `.github/pull_request_template.md`, con todas las secciones rellenas:
   - resumen,
   - alcance,
   - archivos modificados,
   - cambios realizados,
   - que no se ha tocado,
   - riesgos,
   - casos probados,
   - resumen del diff.

## Reglas del repo

- Archivos protegidos: ver `AGENTS.md`.
- Si hay cambios previos del usuario en el working tree, no revertirlos ni reordenarlos destructivamente.
- Si el working tree ya esta mezclado, proponer o ejecutar commits por grupos solo cuando los archivos pertenezcan claramente a una misma intencion.

## Criterio de changelog

Usar `docs/CHANGELOG.md` con secciones:

- `Added`: capacidades nuevas.
- `Changed`: cambios funcionales, UX o arquitectura.
- `Fixed`: bugs corregidos.
- `Data`: persistencia, SQLDelight, repositorios o migraciones.
- `Docs`: documentacion relevante.
- `Verification`: builds, tests, auditorias o evidencias.

No registrar microcambios sin impacto. Si hay duda, registrar una linea breve bajo `Unreleased`.

## Criterio de PR

Un PR debe tener una unica intencion dominante. Si incluye varios dominios, explicar por que no se separo.

Antes de abrir PR:

1. Comprobar rama actual.
2. Revisar `git diff --cached --stat`.
3. Confirmar que no se han staged archivos ajenos al alcance.
4. Ejecutar las pruebas relevantes si los comandos estan claros.
5. Dejar constancia si las pruebas no aplican.

## Salida final esperada

Responder siempre con:

1. Resumen breve.
2. Archivos modificados.
3. Cambios realizados.
4. Que no se ha tocado.
5. Riesgos o pendientes.
6. Casos probados.
7. Diff o resumen del diff.
