# Ámbito: Entregas web y portal del alumnado

## Estado actual

- Formularios web (autoevaluación, coevaluación, pasaporte por paradas, inscripción a torneos) publicados desde la app, con buzón cifrado en alwaysdata (ADR-2026-10-24).
- Portal del alumnado, fase 1 (`codex/portal-alumnado-fase1`, ADR-2026-11-18): cuenta propia con código de alta y tablón cifrado «Para hacer». Fase 2 «Mis notas» pendiente (sección 11 del ticket).

## Terreno de juego

- App: `kmp/iosApp/AppleShared/WebSubmission*.swift`, `WebPortal*.swift`, `WebPeer*.swift`, `WebPassport*.swift`, `kmp/iosApp/App/Bridge/KmpBridge+WebForms.swift`.
- Tests: `kmp/iosApp/PlannerTests/WebPortalTests.swift`, `WebPeerEvaluationStoreTests.swift`; vectores en `PlannerTests/Recursos/portal-v1.json`; comprobadores en `scripts/interop_entregas_web/` (y `portal/`).
- Web y servidor: repo `marfepa/entregas-alumnado` (`src/`, `src/portal/`, `buzon/buzon.php`, `buzon/portal.php`, `buzon/purgar.php`).

## Trampas

- Las tablas `web_*` y los ficheros de `Documentos/EntregasWeb/` no viajan por Sync LAN. El portal (`portal/alumnos.json` y llaves del llavero) tampoco: solo publica el equipo que invitó.
- `portal-v1.json` se genera en la web (`npm run fixture`) y se copia a mano a `PlannerTests/Recursos/`. Si cambia el cifrado, regenerar y copiar.
- El tablón de los vectores son los bytes literales de `entradas.tablonJson`: Swift debe cifrar exactamente esos bytes.
- Reinvitar a una cuenta activa deja `tablon-pend-<portalId>` en el llavero: no promoverla hasta que `estado` diga cuenta + invitación «ninguna».
- `caduca` llega del servidor en segundos; la web multiplica por 1000 y la app detecta segundos con `> 1e11`.
- El pasaporte por paradas sigue en «Para hacer» hasta caducar aunque tenga envíos.
- `buzon/.htaccess` solo deja pasar los PHP listados: un PHP nuevo necesita su línea.
- `portal.php` no hace `password_verify` ni `password_hash` dentro del cerrojo global. No volver a meterlos.
- Los correos de invitación solo se preparan en Mac (`WebSubmissionBulkMailer` es solo macOS). En iPad: «Mostrar su código…» con QR.
- El Bash del sandbox no escribe en los worktrees de fuera del checkout principal.
- En macOS, una hoja no puede pedir más alto que la ventana principal (por defecto 900x450): AppKit entra en bucle de Update Constraints y cierra la app. En `WebPortalSheet` el alto está acotado y la tabla va dentro de un ScrollView con alto fijo por filas; lo vigila `WebPortalSheetLayoutTests`.
