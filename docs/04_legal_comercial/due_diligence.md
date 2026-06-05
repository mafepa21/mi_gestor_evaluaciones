# Due Diligence Comercial

Objetivo: convertir el repositorio en un activo revisable antes de piloto,
venta, cesion, auditoria o distribucion publica.

## Estado actual

| Area | Estado | Proxima accion |
|---|---|---|
| Licencia del repo | Definida como propietaria. | Revisar con asesoria si se ofrecera a terceros. |
| Seguridad | Politica base creada. | Definir canal privado y SLA de respuesta. |
| Privacidad | Borrador operativo creado. | Cerrar roles, contratos y deber de informacion. |
| Terceros | Inventario inicial creado. | Extraer licencias exactas y transitivas. |
| Matriz de modulos | Creada. | Actualizarla en cada PR transversal. |
| Release process | Automatizado con checks seguros y evidencia. | Validar primera release `v0.3.0-alpha.1` sin publicar tags por push. |
| Versionado GitHub | Guia canonica creada. | Crear tag manual tras merge y publicar draft release solo con `workflow_dispatch`. |
| PR template | Existe. | Mantener riesgos, pruebas y docs actualizados. |

## Checklist legal y comercial

- Confirmar titularidad del codigo, disenos, iconos, textos y assets.
- Confirmar que no hay datos reales de alumnado en commits, issues, PRs,
  adjuntos, artefactos, SQLite, capturas o logs.
- Revisar compatibilidad de licencias de terceros con distribucion propietaria.
- Definir responsable/encargado del tratamiento y contratos aplicables.
- Preparar politica de privacidad publicable y acuerdo de tratamiento si aplica.
- Definir condiciones de uso, soporte, limitaciones y garantias.
- Documentar donde se guardan datos, como se exportan, como se borran y como se
  restauran backups.
- Definir politica de IA: local, externa, datos usados, transparencia y bloqueo
  de servicios no aprobados.
- Confirmar estrategia de distribucion: TestFlight, instalador macOS, DMG,
  notarizacion, App Store o canal privado.
- Preparar evidencias de calidad: builds, tests, capturas, checklist UX y
  pruebas de restauracion/exportacion.
- Confirmar que cada version publicable tiene rama `release/*`, PR, changelog,
  tag anotado manual, GitHub Release manual y checks asociados.

## Riesgos abiertos

| Riesgo | Impacto | Mitigacion |
|---|---|---|
| Roles RGPD no cerrados | Bloquea piloto formal o venta a centros. | Revision juridica y contratos. |
| Licencias transitivas sin auditar | Riesgo de incumplimiento en distribucion. | Automatizar reporte y revisar restricciones. |
| Backups/exportaciones con datos reales | Riesgo alto de privacidad. | Fixtures anonimos, checklist y `.gitignore`. |
| Publicacion accidental de releases | Confusion comercial o exposicion prematura. | `publish-release.yml` solo manual y tags nunca automaticos por push. |
| Sync futuro sin politica | Riesgo de transferencia no documentada. | ADR antes de implementar sync externo. |
| IA contextual sin transparencia suficiente | Riesgo de confianza y privacidad. | Limitar a local/minimo y documentar cada flujo. |
| Versiones desktop marcadas como `1.0.0` en packaging | Confusion comercial. | Alinear packageVersion con version interna antes de release. |

## Evidencias minimas por release

| Evidencia | Fuente esperada |
|---|---|
| Build iOS Simulator | `scripts/verify_apple_builds.sh` o CI Apple. |
| Build macOS | `scripts/verify_apple_builds.sh` o CI Apple. |
| Tests KMP shared | `./gradlew :shared:test`. |
| Tests data | `./gradlew :data:desktopTest`. |
| Revision privacidad | `PRIVACY.md` y `docs/04_legal_comercial/datos_personales.md`. |
| Revision terceros | `THIRD_PARTY_NOTICES.md` actualizado. |
| Changelog | `docs/CHANGELOG.md`. |

## Criterio de listo para vender

No considerar el repo comercialmente listo hasta que:

- `main` contenga todo el trabajo estable.
- CI este verde en la rama candidata.
- Exista release reproducible con version coherente.
- Legal, privacidad, seguridad y terceros esten revisados.
- Se haya probado exportacion, backup, restauracion y borrado con datos anonimos.
- Exista documentacion de uso minima para docentes o evaluadores.
