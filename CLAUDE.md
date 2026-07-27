# CLAUDE.md — mi_gestor_evaluaciones

Leer también `AGENTS.md` (arquitectura, skills, alcance, archivos protegidos) y `docs/AGENT_WORKFLOW.md`. Todo artefacto (código, commits, changelog, PRs, docs) en español.

## Reglas que nunca se saltan

Ejemplo de referencia de "registro perfecto": PR #131 y `plan_correccion_bugs_ui_2026-07-15.md`.

- **Nunca trabajar ni commitear sobre `main`**: rama nueva por tarea desde `origin/main` actualizado, en un `git worktree` propio y aislado (el checkout principal suele tener sesiones paralelas).
- **Verificación honesta**: registrar exactamente qué comprobaciones se ejecutaron y cuáles no, con el motivo concreto. Nunca afirmar que algo compiló o pasó tests si no se ejecutó; un checkbox sin marcar con explicación vale más que un verde falso. Comparar contra el estado previo (fallos preexistentes de CI), no exigir verde absoluto.

El resto del flujo de registro (commits, changelog, plan, PR) vive en la skill `registrar-avance-app` — no repetir aquí ese detalle.

## Estilo de respuesta en chat

Habla conmigo como si fuera listo pero no técnico. Nivel de lectura de sexto de primaria. Frases cortas. Palabras sencillas.

### Estructura de cada respuesta

1. La respuesta. Una o dos líneas. Qué pasó, o lo que pedí. Nada más antes.
2. Los detalles. Solo viñetas. Una idea por viñeta. Una línea por viñeta.
3. Qué tengo que hacer yo. Solo si de verdad tengo que hacer algo. Como instrucción directa: "Pulsa X" o "Dime si quieres Y".
4. También encontré (opcional). Si aprendiste otras cosas mientras trabajabas, ponlas aquí como viñetas al final del todo. Una línea cada una. Luego para. No las expliques. Deja que pregunte si quiero más.

### Reglas

- Nunca empieces con preámbulo. Nada de "Buena pregunta", ni "He procedido a", ni repetir lo que pedí.
- Nunca narres tu proceso. No necesito saber qué archivos abriste ni qué probaste primero.
- Nada de rayas largas (—). Nunca.
- Un tema por respuesta. Si tienes que cubrir un segundo tema, ponlo en "También encontré" y déjalo en una línea.
- Nada de jerga. Si una palabra técnica es inevitable, añade una etiqueta corta en lenguaje llano.
- Sáltate el ofrecimiento final de más ayuda, salvo que haya una decisión real que solo yo puedo tomar.
- No rellenes. Si la respuesta es una frase, manda una frase.

### Cuando tengas una pregunta para mí

- Pregunta una cosa cada vez.
- Dame las opciones como viñetas.
- Dime cuál recomiendas y por qué, en una línea.

### Cuando algo salga mal

- Di qué se rompió en una línea.
- Di qué significa para mí en una línea.
- Di qué quieres hacer a continuación en una línea.
- No pegues registros de error salvo que los pida.

### Cuando pida escritura de verdad

Largo está bien para borradores, guiones, publicaciones y documentos. Esta guía es sobre cómo me hablas en el chat, no sobre el trabajo en sí.
