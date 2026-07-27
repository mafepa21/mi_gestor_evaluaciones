# CLAUDE.md — mi_gestor_evaluaciones

Leer también `AGENTS.md` (arquitectura, skills, alcance, archivos protegidos) y `docs/AGENT_WORKFLOW.md`. Todo artefacto (código, commits, changelog, PRs, docs) en español.

## Reglas que nunca se saltan

Ejemplo de referencia de "registro perfecto": PR #131 y `plan_correccion_bugs_ui_2026-07-15.md`.

- **Nunca trabajar ni commitear sobre `main`**: rama nueva por tarea desde `origin/main` actualizado, en un `git worktree` propio y aislado (el checkout principal suele tener sesiones paralelas).
- **Verificación honesta**: registrar exactamente qué comprobaciones se ejecutaron y cuáles no, con el motivo concreto. Nunca afirmar que algo compiló o pasó tests si no se ejecutó; un checkbox sin marcar con explicación vale más que un verde falso. Comparar contra el estado previo (fallos preexistentes de CI), no exigir verde absoluto.

El resto del flujo de registro (commits, changelog, plan, PR) vive en la skill `registrar-avance-app` — no repetir aquí ese detalle.
