---
name: limpieza-post-tarea
description: Libera espacio en disco tras una tarea de Mi Gestor Evaluaciones. Usar al abrir el PR (fase 1), cuando el PR ya esté fusionado (fase 2), o cuando el usuario pida liberar espacio, borrar builds o limpiar worktrees.
---

# Limpieza post-tarea

## Principio

Solo se borra lo que se puede regenerar, o lo que ya está fusionado y guardado en origin.
Ante la duda, no se borra: se informa.

## Antes de empezar

1. Anota el espacio libre: `df -h / | tail -1`.
2. Confirma que estás en el worktree de la tarea, no en el checkout principal:
   `git worktree list` y `git status --short --branch`.
3. Si estás en el checkout principal (`main`), no borres nada. Pregunta antes.

## Fase 1: al abrir el PR

Solo si se cumplen **todas** estas condiciones:

- No hay cambios sin commit: `git status --porcelain` vacío.
- La rama está en origin y coincide con HEAD: `git rev-parse @{u}` igual a `git rev-parse HEAD`.

Lista blanca de rutas a borrar, dentro del worktree de la tarea:

- `build/` de la raíz.
- Los `build/` de `kmp/` a profundidad 2. Lístalos antes con `find kmp -maxdepth 2 -type d -name build`.
- `kmp/.gradle/`.

Cualquier otra ruta queda fuera de la lista.

## Fase 2: PR fusionado

1. Comprueba el estado: `gh pr view <rama> --json state,mergedAt`. Debe ser `MERGED`.
2. Quita el worktree sin forzar: `git worktree remove <ruta>`.
   Si falla, hay cambios dentro. Para y avisa. No uses `--force`.
3. Borra la rama local con `git branch -d codex/<slug>`.
   Si git dice que no está fusionada (pasa con squash merge), no la fuerces. Informa y deja la decisión al usuario.

## Nunca borrar

- Archivos sin seguimiento que no sean builds: `.xlsx`, `.docx`, `.md` sueltos, `publicaciones/`, o cualquier cosa fuera de la lista blanca.
- `.env`, `.env.*`, `secrets/`, `.mcp.json`.
- Worktrees que no sean el de la tarea (por ejemplo `version-main`).
- Cachés globales: `~/.gradle`, `~/Library/Caches`, `~/Library/Developer/Xcode/DerivedData`.
  Solo se listan con su tamaño. Se borran únicamente si el usuario lo pide.
- Comandos destructivos: `git clean`, `git reset --hard`, `git branch -D`, `--force`, y `rm -rf` con comodines fuera de la lista.

## Modo prueba

Si el usuario pide simular, o es la primera vez en esa tarea, lista lo que se borraría con `du -sh` y no borres nada.

## Informe final

Responde en español, en frases cortas:

- Espacio libre antes y después (`df -h /`).
- Qué se borró, con su tamaño.
- Qué se dejó y por qué.
- Si hay una rama o worktree que requiera decisión del usuario.
