# Changelog

Todas las entradas relevantes del proyecto se registraran aqui desde el 2026-06-04.

El formato sigue una variante practica de Keep a Changelog:

- `Added`: funcionalidades nuevas.
- `Changed`: cambios funcionales, UX o arquitectura.
- `Fixed`: bugs corregidos.
- `Data`: cambios en SQLDelight, repositorios, migraciones o persistencia.
- `Docs`: documentacion relevante.
- `Verification`: builds, tests, auditorias o evidencias.

## Unreleased

### Changed

- Se fija `0.3.0-dev` como version interna actual hasta contar con una release reproducible y verificada.
- Los manifiestos activos bajan de `1.0` a `0.3.0` para reflejar el estado real de madurez del producto.

### Docs

- Se crea la estructura documental base del repositorio: indice, gobierno, roadmap, baseline inicial y plantilla de PR.
- Se documenta el workflow para agentes y el uso obligatorio de `registrar-avance-app` como capa final de trazabilidad.
- Se añade el proceso interno de release con checks obligatorios, version bump, evidencias minimas y criterio de etiquetado.
- Se actualiza el estado documental de KMP + SwiftUI Apple como target activo y Flutter como legado o referencia pendiente de decision.

### Verification

- Se añaden workflows de GitHub Actions para tests KMP/data y verificacion de builds Apple en PRs y pushes a `main`.
- Se cierra el PR #6 como redundante/conflictivo tras verificar que no quedaban commits pendientes respecto a `origin/main`.

## Baseline historico - 2026-06-04

### Changed

- El proyecto ya contiene una app Flutter original y una evolucion KMP + SwiftUI en curso.
- La documentacion canonica pasa a organizarse desde `docs/`, con ADRs tecnicos en `kmp/docs/architecture/`.

### Verification

- Se reviso la estructura del repositorio, README existentes, ADR inicial Apple dual-target y checklist UI/UX existente.
