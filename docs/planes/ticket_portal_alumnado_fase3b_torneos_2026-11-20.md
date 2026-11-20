# Ticket L · Portal del alumnado, fase 3B: «Torneos»

Estado: **aprobado e implementado** (2026-11-20).
Depende de: fase 2 fusionada (PR app #420, PR web #19). Rama: `codex/portal-alumnado-fase3b-torneos`.
Maqueta: `docs/maquetas/portal_alumnado_fase3b_torneos_2026-11-20.html` (estados T1-T5 web, A1-A4 app). Si choca con el ticket, manda el ticket.
Base: contrato `contrato_portal_v1_2026-11-18.md`, `ADR-2026-11-18` y modelo de proyección `TournamentProjectionModel.swift` / `BracketTreeLayout.swift`.

## 1. Objetivo y contexto

En clase se gestionan torneos desde la app (Liga, Eliminatoria, Liguilla + eliminatorias, Rotaciones y Liguilla + puestos), con proyección en el Mac y modo directo desde el iPad. Hoy el alumnado solo ve el progreso del torneo si mira el proyector del gimnasio.

El objetivo es que, cuando el docente active un torneo de un grupo en la app, cada alumno vea en su propio portal —dentro del mismo tablón cifrado de extremo a extremo— cuál es su equipo, su próximo partido, la clasificación, los resultados por ronda y el cuadro o podio, sin que el servidor vea ningún dato en claro y sin añadir correos ni chats.

## 2. Alcance

- **App (solo Apple, sin cambios en KMP ni SQLDelight):**
  - `AppleShared/WebPortalTournamentSettings.swift` nuevo: interruptores por torneo (`visible`, `mostrarNombres`, `confirmados`, `nombresConfirmados`) en `Documentos/EntregasWeb/portal/torneos-visibles.json`, más estado `torneos-publicados.json` para retirar torneos apagados tras reiniciar (mismo patrón que `notas-visibles.json` y `notas-publicadas.json`).
  - `AppleShared/WebPortalTournaments.swift` nuevo: construye el bloque `torneos` del tablón v1 por alumno a partir de `TournamentRecord` / `TournamentPlan`, reutilizando `ProjectionTeamLabels`, `TournamentPhaseTimeline` y `BracketTreeLayout` para no duplicar lógica de clasificación, fases ni cuadros. Identifica el equipo del alumno mediante `TournamentPlanTeam.studentIDs`.
  - `AppleShared/WebPortalTournamentsView.swift` nuevo: pestaña «Torneos» dentro de `WebPortalSheet` (estados A1-A4, confirmación al encender torneo y aviso específico al encender nombres de equipo, solo lectura en iPad).
  - `AppleShared/WebPortalSheet.swift`: selector segmentado de 3 pestañas `Cuentas · Notas visibles · Torneos`.
  - `AppleShared/WebPortalPublisher.swift` y `AppleShared/WebPortalGradesWatcher.swift` (o vigilante hermano `WebPortalTournamentsWatcher.swift`): incluir `torneos` en el JSON del tablón, vigilar `saveTournament` (`KmpBridge+Tournaments.swift`) y `.lanSyncRemoteChangesApplied` (entidad `learning_situation_tournament`), con espera de **2 minutos** al actualizar resultados y **retirada inmediata** al apagar o cambiar «Mostrar nombres de equipo».
- **Web (`entregas-alumnado`):**
  - `src/portal/torneos.mjs` nuevo: pantallas T1-T5 (mi equipo, próximo partido, línea de fases, clasificación, rondas/cuadro y podio).
  - `src/portal/tablon.mjs`: validar y sanear el bloque opcional `torneos` (tipos, longitudes, marcadores enteros no negativos) y omitirlo en la copia local de «Recordarme» (igual que `notas`).
  - `src/portal/pantallas.mjs` y `src/portal/portal.mjs`: pestaña dinámica **Torneo** (o **Torneos** si hay varios visibles) que **solo aparece cuando el tablón trae al menos un torneo visible**.
  - `src/vista/textos.mjs` y `src/estilo.css`: textos es/en y estilos coherentes con el cuaderno de papel y pista verde.
  - Sin cambios en `portal.php`, `buzon.php` ni en el cifrado.

## 3. Fuera de alcance

- Notas de incidencias del torneo (`TournamentNotes`) y notas de rúbrica evaluadas durante el modo directo (las notas siguen gobernadas exclusivamente por «Notas visibles»).
- Retransmisión segundo a segundo del reloj de pista (el portal muestra rondas, pistas y marcadores guardados, no un cronómetro en vivo).
- Edición de interruptores desde el iPad (sigue la misma regla que `notas-visibles.json`: solo cambia el Mac que tiene las llaves; los marcadores del iPad suben solos al Mac por Sync LAN).
- Inscripción o cambio de pareja desde la pestaña Torneo (la inscripción sigue entrando como tarea web en «Para hacer»).
- Cambios en `KmpBridge.swift`, `EvaluationDesign.swift`, `kmp/shared/`, `kmp/data/sqldelight/` ni `NotebookModuleView.swift`.

## 4. Modelo de datos

### 4.1 Bloque `torneos` dentro del tablón v1 (cifrado con `K_tablon`)

```json
"torneos": {
  "actualizado": "2026-11-20T11:20:00Z",
  "lista": [{
    "id": "uuid-del-torneo",
    "titulo": "Torneo de Bádminton",
    "grupo": "2º ESO B",
    "formato": "liguilla_puestos",
    "estado": "en_curso",
    "fases": [
      { "clave": "liguilla", "etiqueta": "Liguilla", "estado": "hecha" },
      { "clave": "cuadro", "etiqueta": "Cuadro", "estado": "ahora" },
      { "clave": "podio", "etiqueta": "Podio", "estado": "pendiente" }
    ],
    "miEquipo": {
      "numero": 3,
      "etiqueta": "Equipo 3",
      "resumen": "2º en Grupo A · 2G 1P"
    },
    "proximoPartido": {
      "ronda": "Semifinal · Puestos 1–4",
      "pista": 2,
      "local": "Equipo 3",
      "visitante": "Equipo 6"
    },
    "clasificacion": [{
      "titulo": "Grupo A",
      "filas": [{
        "posicion": 1,
        "equipo": "Equipo 1",
        "esMio": false,
        "jugados": 3,
        "ganados": 3,
        "empatados": 0,
        "perdidos": 0,
        "puntos": 9
      }]
    }],
    "rondas": [{
      "titulo": "Semifinales",
      "fase": "cuadro",
      "actual": true,
      "partidos": [{
        "pista": 1,
        "local": "Equipo 1",
        "visitante": "Equipo 4",
        "marcadorLocal": 15,
        "marcadorVisitante": 11,
        "esMio": false,
        "etiqueta": "Puestos 1–4",
        "destino": "Gana: 1–2 · Pierde: 3–4"
      }],
      "descansan": ["Equipo 7"]
    }],
    "podio": [
      { "puesto": 1, "equipo": "Equipo 1", "esMio": false },
      { "puesto": 2, "equipo": "Equipo 3", "esMio": true },
      { "puesto": 3, "equipo": "Equipo 6", "esMio": false }
    ]
  }]
}
```

- **Nombres de equipo**: por defecto (`mostrarNombres: false`) se usa `ProjectionTeamLabels(plan: plan, showNames: false)` → `Equipo N` (y huecos seguros como `Gana P5`, `1º Grupo A`). Nunca se exportan `studentIDs`, apellidos ni nombres antiguos huérfanos. Solo si el docente enciende «Mostrar nombres de equipo» para ese torneo concreto se envían los `team.name` del plan.
- **Privacidad de la pestaña**: sin `torneos` o con `lista` vacía, la pestaña **Torneo** no aparece en la web. El alumnado no puede deducir si existen torneos sin publicar.
- **Compatibilidad**: el tablón sigue en `schemaVersion: 1`; versiones anteriores de la web ignoran la clave `torneos`.
- **Memoria solamente**: igual que `notas`, la copia cifrada de «Recordarme» en `localStorage` se sella sin `torneos` (y limpia copias antiguas si trajeran `torneos`). Sin conexión, si el alumno intenta abrir la pestaña Torneo, ve T5 («Necesitas conexión»).
- **Tamaño estimado**: ~4–8 KB por torneo (16 equipos con liguilla y cuadro). Muy por debajo del tope de 256 KB por tablón.
- **Longitudes acotadas**: textos cortos ≤ 160 caracteres (`WebPortalGrades.shortTextLimit`), listas acotadas (≤ 10 torneos, ≤ 64 equipos, ≤ 40 rondas, ≤ 64 partidos por ronda) tanto en Swift como en el validador de la web.

### 4.2 Ajustes locales (`torneos-visibles.json`, solo Mac)

```json
{
  "<classId>": {
    "torneos": {
      "<tournamentId>": { "visible": true, "mostrarNombres": false }
    },
    "confirmados": ["<tournamentId>"],
    "nombresConfirmados": ["<tournamentId>"]
  }
}
```

- Todo apagado si falta el fichero o la entrada.
- `torneos-publicados.json` guarda los `classId` con torneos publicados o pendientes en cola, para retirar torneos apagados incluso tras reiniciar la app.

### 4.3 Cuándo se publica

- **Cambios de resultados o calendario** en un torneo visible (guardado en Mac vía `saveTournament` o llegado del iPad vía Sync LAN con entidad `learning_situation_tournament`) → cola del grupo con espera de **2 minutos** desde el último cambio (agrupa toda una ronda sin hacer esperar 10 minutos).
- **Encender un torneo** → misma cola de 2 minutos.
- **Apagar un torneo** o **cambiar «Mostrar nombres de equipo»** → retirada/actualización **inmediata** (`immediately: true`).
- Publicar una tarea web o republicar notas incluye siempre el bloque `torneos` vigente del alumno.
- **Concurrencia Swift–KMP**: todas las llamadas `suspend` (`tournaments(forClassId:)`) se invocan en `@MainActor`; la construcción del bloque JSON y los cálculos síncronos se ejecutan en `Task.detached(priority: .utility)`.

## 5. Plan

1. Revisión del ticket y la maqueta con el docente (**APROBADO**).
2. App: `WebPortalTournamentSettings`, `WebPortalTournaments` (generación de bloque para los 5 formatos + privacidad `ProjectionTeamLabels`), vigilante/cola de 2 min + enganche en `saveTournament` y `.lanSyncRemoteChangesApplied`, pestaña «Torneos» en `WebPortalSheet` (A1-A4), pruebas en `PlannerTests` (`WebPortalTournamentsTests` + `WebPortalSheetLayoutTests`).
3. Web: `src/portal/torneos.mjs`, validación y limpieza de copia local en `tablon.mjs`, pestaña dinámica en `pantallas.mjs` / `portal.mjs`, textos es/en, estilos y pruebas (`probar-portal-web.mjs`, `probar-portal-pantallas.mjs`, vector `tablonTorneos` en `portal-v1.json`).
4. Prueba de punta a punta en local (Swift real → `portal.php` → Node) con bloque `torneos` + grep de privacidad en `~/buzon-datos/portal/`.
5. Build iOS + Mac, QA en Mac e iPad, registro en `CHANGELOG.md`, anexo en `ADR-2026-11-18` y `docs/ambitos/entregas-web.md`, PR app + PR web enlazados.

## 6. Criterios de aceptación

- [ ] Todo apagado de entrada: un torneo nuevo o existente no aparece en el portal hasta que el docente enciende su interruptor.
- [ ] Sin torneos visibles en el grupo, la web muestra exactamente las 2 pestañas de siempre (`Para hacer · Mis notas`) sin revelar si hay torneos ocultos.
- [ ] Por defecto («Mostrar nombres de equipo» apagado) nunca viajan nombres de equipo ni de alumnado: solo `Equipo N` y huecos estándar del cuadro.
- [ ] Al encender un torneo por primera vez aparece confirmación (A2a) con **Cancelar** por defecto y Escape.
- [ ] Al encender «Mostrar nombres de equipo» por primera vez aparece confirmación específica (A2b) avisando de que no incluyan apellidos, con **Cancelar** por defecto.
- [ ] Apagar un torneo o apagar «Mostrar nombres de equipo» actualiza/retira de inmediato (sin esperar 2 min), incluso tras reiniciar la app (`torneos-publicados.json`).
- [ ] Cada alumno que forma parte de un equipo ve destacada su tarjeta **«Tu equipo»** y su próximo partido; un alumno sin equipo asignado ve el progreso del torneo sin errores (T4).
- [ ] Funciona con los 5 formatos de torneo de la app (`roundRobin`, `knockout`, `groupStageKnockout`, `rotation`, `leaguePlacement`).
- [ ] Nunca salen notas de incidencias (`TournamentNotes`), notas de rúbrica, `studentIDs` ni correos.
- [ ] Los resultados anotados en el iPad en *Modo directo* llegan al portal del alumnado ~2 minutos después de entrar en el Mac por Sync LAN.
- [ ] En el iPad los interruptores de la pestaña Torneos son de solo lectura con el aviso A4.
- [ ] En la web, los datos del torneo no se guardan en `localStorage` ni `sessionStorage` (ni con «Recordarme»); sin conexión se muestra T5.
- [ ] En el servidor (`~/buzon-datos/portal/`) no aparece ningún título de torneo, nombre de equipo ni marcador en claro (grep de la prueba E2E).
- [ ] Accesibilidad: pestañas con roles ARIA y flechas, áreas táctiles ≥ 48 px, contraste ≥ 4,5:1, tabla de clasificación con encabezados semánticos (`<th>`, `scope`), equipo propio marcado con texto («Tu equipo») además de borde/color.
- [ ] Todas las llamadas `suspend` de Kotlin van en `@MainActor` (sin crashes de Kotlin/Native).

## 7. Validación

- App: `WebPortalTournamentsTests` (5 formatos, privacidad sin nombres vs con nombres, identificación de `miEquipo`, cola de 2 min con reloj manual, retirada inmediata, estado tras reinicio), `WebPortalSheetLayoutTests` (ventana 900×450 con la 3ª pestaña), build `MiGestorKMPMac` y `MiGestorKMPiOS` (simulador).
- Web: `npm test` (pantallas T1-T5 en es/en, validación de `torneos`, flujo real sin copia en `localStorage`) y `npm run build`.
- Interop + E2E Swift → `portal.php` → Node con `torneos` y grep de privacidad.
- QA manual en Mac e iPad con un torneo de prueba (y prueba de sync desde Modo directo).

## 8. Riesgos y puertas humanas

- **Nombres de equipo con datos personales**: si el docente usa apellidos como nombre de equipo (p. ej. «García / López») y enciende «Mostrar nombres de equipo», todos los alumnos del grupo verán esos nombres en su portal. Mitigación: apagado por defecto (`Equipo N`), confirmación explícita con aviso A2b y retirada inmediata al apagarlo.
- **Expectativa de «en vivo»**: el alumnado puede esperar que el marcador cambie al segundo durante el partido. Mitigación: el pie de pantalla indica la hora de actualización (*«Actualizado hoy a las 11:20»*) y no se muestra reloj de partido.
- **Mismo límite de plataforma**: solo publica el Mac con las llaves del portal (hasta fase 3A de respaldo de llaves / fase 3D de sync de ajustes).

## 9. Entregables

- PR en `mi_gestor_evaluaciones` y PR en `entregas-alumnado`, enlazados.
- Maqueta aprobada (`portal_alumnado_fase3b_torneos_2026-11-20.html`).
- `docs/CHANGELOG.md`, anexo en `ADR-2026-11-18` y `docs/ambitos/entregas-web.md` actualizados.
