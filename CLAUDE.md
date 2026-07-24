# CLAUDE.md — mi_gestor_evaluaciones

Leer también `AGENTS.md` (arquitectura, skills, alcance, archivos protegidos) y `docs/AGENT_WORKFLOW.md`. Todo artefacto (código, commits, changelog, PRs, docs) en español.

## Flujo de registro de avances (obligatorio, sin excepciones)

Todo cambio se registra siempre igual — "registro perfecto". Ejemplo de referencia: PR #131 y `plan_correccion_bugs_ui_2026-07-15.md`.

1. **Nunca trabajar sobre `main`** ni commitear directamente en él. Rama nueva por tarea desde la punta actualizada de `origin/main` (hacer `git fetch` antes de ramificar): `fix/...`, `feat/...`, `docs/...`, `ui/...`, `build/...`.
2. **Worktree limpio y aislado por tarea**: crear un `git worktree` propio en vez de cambiar de rama en el checkout principal (suele haber sesiones paralelas trabajando sobre él). Verificar `git status --short --branch` antes de tocar nada, partir de árbol limpio y no barrer jamás archivos que la tarea no haya creado o modificado.
3. **Commits atómicos**: un commit por bug o intención, formato `tipo(ámbito): descripción en español` (`fix`, `feat`, `docs`, `ui`, `data`, `kmp`, `build`, `test`, `refactor`). No mezclar bugs distintos ni ámbitos distintos (UI / KMP / SQLDelight / docs) en un mismo commit.
4. **Changelog en el mismo commit**: cada cambio lleva su entrada en `docs/CHANGELOG.md` bajo `## Unreleased`, en la sección correcta (Added/Changed/Fixed/Data/Docs/Verification), dentro del mismo commit que el cambio que documenta.
5. **Plan documentado cuando hay varios fixes**: si la tarea agrupa varios bugs, dejar el plan en la raíz como `plan_correccion_bugs_<tema>_<fecha>.md` (estilo de `plan_correccion_bugs_2026-07-13.md`) y commitearlo con `docs(plan): ...`.
6. **Push + PR siempre**: subir la rama y abrir PR contra `main` con la plantilla `.github/pull_request_template.md`, con todas las secciones rellenas (Resumen, Alcance, Archivos afectados, Cambios, Qué no se ha tocado, Riesgos, Casos probados, Documentación, Evidencias).
7. **Verificación honesta**: registrar exactamente qué comprobaciones se ejecutaron y cuáles no, con el motivo concreto. Nunca afirmar que algo compiló o pasó tests si no se ejecutó; un checkbox sin marcar con explicación vale más que un verde falso. Tener en cuenta los fallos preexistentes de CI y compararse contra el estado previo, no exigir verde absoluto.
