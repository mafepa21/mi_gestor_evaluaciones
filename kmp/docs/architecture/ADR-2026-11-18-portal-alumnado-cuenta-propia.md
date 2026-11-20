# ADR-2026-11-18: Portal del alumnado con cuenta propia

## Estado

Aprobado (fase 1). Contrato: `docs/planes/contrato_portal_v1_2026-11-18.md`. Ticket: `docs/planes/ticket_portal_alumnado_fase1_2026-11-18.md`.

## Contexto

Cada formulario web generaba un enlace nuevo por alumno que el docente mandaba por correo. Las entregas ya volvían solas por el buzón (ADR-2026-10-24), pero la ida seguía siendo un correo por formulario. Queríamos un sitio fijo donde el alumnado vea todo lo pendiente, sin que el servidor sepa quién es cada alumno ni pueda leer su contenido.

## Decisión

- Cada alumno tiene un `portalId` al azar y una llave `K_tablon` creadas en la app. El tablón (pendientes y ya enviados) viaja cifrado con ChaCha20-Poly1305 y `K_tablon`.
- Alta: un código de 10 caracteres (≈50 bits), de un uso y 7 días, por correo (solo Mac) o QR. Del código salen, con PBKDF2-HMAC-SHA256 (600 000 iteraciones) y HKDF, el `inviteId`, una prueba y la llave que abre `sobreAlta`. El servidor no conoce el código.
- Cuenta: usuario (mote) y contraseña. El navegador deriva con Argon2id (m=19 MiB, t=2) `claveAuth`, que el servidor guarda con `password_hash`, y `claveEnvoltura`, que nunca sale y abre `sobreCuenta`. El usuario llega al servidor solo como hash.
- Servidor: `buzon/portal.php` en el mismo alojamiento que el buzón, datos en `~/buzon-datos/portal/`, sin registros ni IPs, con esperas crecientes por usuario y dispositivo y sal falsa estable para usuarios que no existen.
- Reinvitar rota `K_tablon`. Si el alumno ya tiene cuenta, la rotación se difiere: se sigue publicando con la llave actual hasta que `estado` confirma que canjeó el código nuevo.
- La app publica el tablón al publicar un formulario y al importar entregas. El cruce `portalId` ↔ alumno solo existe en `Documentos/EntregasWeb/portal/alumnos.json` (no viaja por Sync LAN) y las llaves en el llavero.

## Alternativas descartadas

- Solo enlace o QR fijo: se pierde y no sirve en varios dispositivos.
- Entrar con la cuenta del centro (Google o Microsoft): el servidor sabría quién entra y depende del responsable informático del centro.
- Argon2id también para el código: CryptoKit no lo trae y no se quieren dependencias. Con 50 bits de entropía, PBKDF2 basta.

## Consecuencias

- Sin cambios en KMP ni SQLDelight.
- Solo publica el dispositivo que tiene las llaves en su llavero. Cambiar de equipo exige volver a invitar.
- El servidor ve cuántos tablones hay, su tamaño, cuándo cambian y cuáles se publican juntos. No ve de quién son.
- Rendija conocida: con muchos dispositivos distintos, un usuario real y uno inexistente no se bloquean igual, así que se puede llegar a confirmar que un mote existe. No da acceso a nada.
- La fase 2 («Mis notas», sección 11 del ticket) cabe en el mismo tablón v1.
- Puertas humanas: consulta al delegado de protección de datos, permitir `portal.php` en `buzon/.htaccess` del servidor y probar `probar-portal.sh` con PHP antes de abrirlo a alumnado real.

## Anexo: Fase 2 «Mis notas» (2026-11-19)

- **Sin cambios en KMP, SQLDelight ni `portal.php`**: el bloque opcional `notas` viaja dentro del mismo tablón v1 cifrado con `K_tablon` (compatible con la web de la fase 1, que ignora claves desconocidas).
- **Fuente única de notas**: `WebPortalGrades` reutiliza `BuildStudentGradeReportsUseCase` (`KmpBridge.buildStudentGradeReports(classId:columns:rows:)`) sobre `loadNotebookSnapshot`, fijando la pestaña del Cuaderno en `notas-visibles.json` al encender la primera columna. Así valores, niveles y descriptores coinciden con el PDF de «Enviar notas al alumnado» sin abrir el Cuaderno y sin depender de la pestaña activa en pantalla.
- **Filtro estricto y privacidad**: todo apagado de entrada; solo entran columnas que cuentan en la media, no ocultas/archivadas y con su interruptor encendido (tras confirmación P2 por columna). La media solo se puede mostrar si todas las columnas que cuentan están encendidas y ninguna está oculta. Nunca salen comentarios, observaciones, Inclusión, asistencia ni datos brutos.
- **Ajustes solo en Mac**: `notas-visibles.json` y `notas-publicadas.json` (para retirar notas tras reinicio) viven en `Documentos/EntregasWeb/portal/`, no viajan por Sync LAN y en iPad la pestaña es de solo lectura (P5).
- **Publicación y vigilancia**: `WebPortalGradesWatcher` observa `observeGradesForClass`, `observeClassCells`, `.lanSyncRemoteChangesApplied` y `NotebookRefreshBus` (incluyendo notas llegadas del iPad por Sync LAN). Los cambios en columnas visibles se agrupan en una cola de 10 minutos por grupo; apagar una columna o la media retira al momento. El cálculo y cifrado se ejecutan fuera del hilo principal.
- **Sin copia local en el navegador**: la web valida el bloque `notas`, muestra N1-N6 con textos neutros y «Notas provisionales», y vuelve a sellar la copia de «Recordarme» sin `notas` (y limpia copias antiguas que pudieran traerlas). Sin conexión se muestra N6.
- **Puertas humanas adicionales**: consulta al delegado de protección de datos antes de activar notas parciales y aviso previo a familias.

## Anexo: Fase 3B «Torneos» (2026-11-20)

- **Mismo tablón `v1` cifrado con `K_tablon`**: el bloque opcional `torneos` viaja dentro del sobre cifrado sin cambios en `portal.php`, KMP ni SQLDelight (compatible con versiones anteriores de la web).
- **Control opt-in y privacidad por defecto**: todo apagado de entrada en `Documentos/EntregasWeb/portal/torneos-visibles.json` (solo Mac; iPad solo lectura). Por defecto cada equipo se etiqueta como `Equipo N` (reutilizando `ProjectionTeamLabels` para evitar fugas de nombres o apellidos). Activar un torneo o activar «Nombres equipo» exige confirmación con Cancelar por defecto. Nunca se incluyen incidencias (`TournamentNotes`), notas de rúbrica ni `studentIDs`.
- **Reutilización del motor de torneos**: `WebPortalTournaments` construye fases, clasificación, rondas, cuadro y podio directamente desde `TournamentPlan`, `TournamentPhaseTimeline` y `BracketTreeLayout` para los 5 formatos, identificando el equipo del alumno mediante `TournamentPlanTeam.studentIDs`.
- **Cola ágil de 2 minutos y retirada inmediata**: `WebPortalTournamentsWatcher` escucha `saveTournament`/`deleteTournament` y `.lanSyncRemoteChangesApplied` (`learning_situation_tournament`). Los cambios de resultados se agrupan en 2 minutos; apagar un torneo o cambiar «Nombres equipo» publica al momento (`torneos-publicados.json` asegura la retirada tras reiniciar).
- **Web dinámica y solo en memoria**: la pestaña «Torneo» solo aparece si el tablón trae torneos visibles; `sobreParaCopia` elimina `torneos` junto con `notas` antes de sellar la copia local de «Recordarme».

## Anexo · Fase 3A: Base operativa (2026-11-20)

- **Tarjetas QR imprimibles en PDF (Mac + iPad)**: `WebPortalCardsPDFRenderer` renderiza hojas A4 (2×4, 8 tarjetas por página) con CoreGraphics + CoreImage (`CIQRCodeGenerator`). El nombre del alumno solo aparece en el PDF local para repartir en aula; nunca sale hacia el servidor.
- **Vista previa local «Ver como este alumno…»**: `WebPortalStudentPreviewSheet` parsea el JSON real generado por `WebPortalPublisher.buildBoard` (reutilizando `portalGradeBlocks` y `portalTournamentBlocks` en `@MainActor`, sin red), garantizando paridad exacta con lo que vería el alumno.
- **Respaldo cifrado de llaves en `.migestorbackupx`**: `WebPortalBackupVault` empaqueta `portal-vault.json` en memoria dentro del ZIP temporal únicamente al exportar una copia cifrada `.migestorbackupx` (PBKDF2 600k + AES-256-GCM). Al importar `.migestorbackupx`, `WebPortalBackupVault.extractAndStrip` lee la bóveda a memoria y borra `portal-vault.json` del staging antes de incorporar el paquete al historial local `.migestorbackup`, evitando llaves en texto claro en disco. Las copias legacy `.migestorbackup` nunca exportan ni aceptan `portal-vault.json`.
