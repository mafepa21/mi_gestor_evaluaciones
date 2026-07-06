---
name: release-prep
description: Prepara, verifica y documenta una release candidate de Mi Gestor Evaluaciones usando los scripts reales del repo - rama release/*, consistencia de versiones, evidencias de calidad, chequeo de archivos sensibles, tag anotado y GitHub Release. Usar siempre que se hable de release, versión, alpha/beta, publicar, distribuir, "cerrar la versión", subir el número de versión o preparar evidencias de calidad para una entrega.
version: 1.0.0
---

# release-prep

## Por qué existe esta skill

El repo ya tiene proceso de release documentado (`docs/RELEASE_PROCESS.md`, `docs/VERSIONING.md`) y scripts que lo automatizan, pero el roadmap señala que aún no se ha completado una candidata de punta a punta ("probar la primera candidata con PR de release, tag anotado y GitHub Release"). El riesgo es inventarse pasos o saltarse evidencias. Esta skill fija la secuencia con las herramientas reales.

## Herramientas reales del repo (no inventar otras)

| Script | Qué hace |
|---|---|
| `scripts/create_release_candidate.sh <version>` | Crea/cambia a `release/<version>` y corre los chequeos de seguridad de release. No crea tags ni releases ni sube versiones por sí solo. |
| `scripts/check_version_consistency.sh` | Verifica que la versión es consistente entre los puntos del repo que la declaran. |
| `scripts/verify_no_sensitive_files.sh` | Bloquea archivos sensibles antes de publicar. |
| `scripts/collect_release_evidence.sh` | Recopila evidencias (builds, tests, auditorías). |
| `scripts/verify_apple_builds.sh` | Build iOS simulator + macOS. |

Documentos canónicos: `docs/RELEASE_PROCESS.md` (proceso), `docs/VERSIONING.md` (esquema de versiones y registro de ramas/PRs/releases), `release-check.yml` (CI). Leer `RELEASE_PROCESS.md` antes de ejecutar nada: si contradice esta skill, manda el documento.

## Secuencia

1. **Estado limpio**: `git status --short --branch`. Una release no sale de un working tree mezclado.
2. **Elegir versión** según `docs/VERSIONING.md` (formato tipo `0.3.0-alpha.2`; ya existe la rama `release/0.3.0-alpha.2` — comprobar qué quedó a medias antes de crear otra).
3. **Crear la candidata**: `scripts/create_release_candidate.sh <version>` y atender su checklist impreso.
4. **Verificaciones**, todas con salida registrada:
   - `scripts/check_version_consistency.sh`
   - `scripts/verify_no_sensitive_files.sh`
   - `./gradlew :shared:test` y `./gradlew :data:desktopTest`
   - `scripts/verify_apple_builds.sh`
5. **Evidencias**: `scripts/collect_release_evidence.sh`. La Fase 4 del roadmap pide evidencias de calidad reales (builds, tests, capturas, auditorías); una release sin evidencias no cierra fase.
6. **Changelog**: mover lo relevante de `Unreleased` a la sección de la versión en `docs/CHANGELOG.md`. Redactar release notes publicables (lenguaje de docente, no de commit).
7. **PR de release** con la plantilla, declarando explícitamente qué se probó y qué no con motivo.
8. **Tag anotado + GitHub Release** solo tras CI verde y aprobación del usuario. El tag y la publicación son acciones difíciles de revertir: confirmar con el usuario antes de crearlos, nunca por iniciativa propia.
9. Registrar todo con `registrar-avance-app` (entrada `Verification` en changelog, actualización de `VERSIONING.md` si registra releases).

## Reglas

- Ningún paso "en verde por fe": cada chequeo se ejecuta y su resultado (o su fallo con motivo) queda en el PR.
- Si un script falla por entorno (p. ej. sin Xcode completo), registrar el fallo y marcar la release como bloqueada, no seguir adelante.
- No subir números de versión a mano en archivos sueltos: primero entender dónde los valida `check_version_consistency.sh`.
- Privacidad antes de distribuir: `PRIVACY.md` y `docs/04_legal_comercial/` siguen pendientes de revisión jurídica; una distribución pública real debe recordárselo al usuario.

## Salida esperada

Versión, rama, tabla de chequeos ejecutados con resultado, evidencias recopiladas, estado del changelog/release notes, y qué falta para poder taggear (o confirmación de que se taggeó tras aprobación).
