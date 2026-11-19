# Ámbito: Entregas web y portal del alumnado

## Estado actual

- Formularios web (autoevaluación, coevaluación, pasaporte por paradas, inscripción a torneos) publicados desde la app, con buzón cifrado en alwaysdata (ADR-2026-10-24).
- Portal del alumnado, fase 1 (`codex/portal-alumnado-fase1`, ADR-2026-11-18): cuenta propia con código de alta y tablón cifrado «Para hacer». Fase 2 «Mis notas» (`codex/portal-alumnado-fase2`): app (pestaña «Notas visibles», bloque `notas` en el tablón, cola de 10 min y retirada inmediata al apagar) y web (pestañas «Para hacer · Mis notas», pantallas N1-N6, detalle de rúbrica y copia local sin notas) implementadas y verificadas.

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
- Fase 2 «Mis notas» (app): `AppleShared/WebPortalGrades*.swift`. Los interruptores (`Documentos/EntregasWeb/portal/notas-visibles.json`) y el estado de grupos publicados/pendientes (`notas-publicadas.json`) viven solo en el Mac, igual que `alumnos.json`: no viajan por Sync LAN y en iPad la pestaña es de solo lectura.
- Las notas no tienen punto común de guardado en Swift: el grid, las rúbricas y Sync LAN escriben desde Kotlin. Por eso `WebPortalGradesWatcher` vigila `observeGradesForClass` y `observeClassCells` (se descarta la primera emisión) y los flujos de Kotlin no se cancelan: hay un vigilante por grupo para siempre y, si el grupo está apagado, `noteChange` no hace nada. Al arrancar (`runStartupPassOnce`), retira las notas de grupos que quedaron en `notas-publicadas.json` y ya no deben verse.
- La cola es de 10 min por grupo desde el último cambio, sin «Publicar ahora»; apagar una columna o la media retira al momento (`immediately: true`). Reloj inyectable en `WebPortalGradesDebouncer` (los tests usan un reloj manual; no duermen 10 min de verdad).
- La media del portal es la de la pestaña fijada en `notas-visibles.json` (se fija al encender la primera columna y se puede cambiar en la hoja, para no depender de la pestaña abierta en el Cuaderno) y solo se habilita si **todas** las columnas que cuentan en esa pestaña son visibles y están encendidas. Se recalcula con `computeAverageExplanation` sobre `loadNotebookSnapshot` (la caché de hojas de Kotlin guarda 4 entradas: publicar grupos de uno en uno). Si cambia la regla en `NotebookViewModel.withActiveTabAverages`, cambiar `WebPortalGrades.scope` a la vez.
- `computeAverageExplanation` no mira `isHidden`: una columna oculta cuenta en la media. El filtro de ocultas/archivadas del portal está en `WebPortalGrades.isShowable`.
- Un grupo que no se puede leer no borra notas: `republishPortalBoards` reutiliza el último bloque publicado (`WebPortalGradesSummary.lastNotas`). El resumen es solo memoria: tras reiniciar la app, el primer cambio vuelve a subir a todos una vez.
- En macOS, una hoja no puede pedir más alto que la ventana principal (por defecto 900x450): AppKit entra en bucle de Update Constraints y cierra la app. En `WebPortalSheet` el alto está acotado y la tabla va dentro de un ScrollView con alto fijo por filas; lo vigila `WebPortalSheetLayoutTests`.
- Kotlin/Native exige invocar funciones `suspend` desde `@MainActor` (hilo principal); llamar `loadNotebookSnapshot` o `makeGradeReports` dentro de `Task.detached` o desde un método `nonisolated async` aborta la app (`Calling Kotlin suspend functions from Swift/Objective-C is currently supported only on main thread`). Las llamadas `suspend` van en `@MainActor` (los repositorios de Kotlin ya saltan a `Dispatchers.Default`) y solo los cálculos síncronos (`scope`, `BuildStudentGradeReportsUseCase().build`, `blocks`) van en `Task.detached(priority: .utility)`.
