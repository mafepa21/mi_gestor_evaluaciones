# Ticket L · Portal del alumnado, fase 2: «Mis notas»

Estado: **borrador, pendiente de APROBADO**. No se toca código hasta entonces.
Depende de: fase 1 fusionada (PR app #419, PR web #18). Rama: `codex/portal-alumnado-fase2`, apilada sobre la de la fase 1.
Maqueta: `docs/maquetas/portal_alumnado_fase2_notas_2026-11-19.html` (estados N1-N6 web, P1-P5 app). Si choca con el ticket, manda el ticket.
Base: sección 11 del ticket de la fase 1 y contrato `contrato_portal_v1_2026-11-18.md`.
Revisión de la maqueta (`ui-reviewer`, 2026-11-19): «no aprobar tal cual». Aplicados los 12 cambios: textos neutros que no dejan deducir notas ocultas, nota baja como «Para mejorar» sin rojo, aviso de provisional con explicación, interruptores y pestañas accesibles, sin «Publicar ahora», confirmación por columna con Cancelar por defecto, nivel de rúbrica en número.

## 1. Objetivo y contexto

Hoy las notas llegan al alumnado por correo, con un PDF por alumno («Enviar notas al alumnado…»). El portal ya tiene cuentas y un tablón cifrado de extremo a extremo. El objetivo es que cada alumno vea en su portal, en una pestaña «Mis notas», las notas que el docente decida enseñar, y que se actualicen solas, sin correo y sin que el servidor pueda leerlas.

## 2. Alcance

- **App (solo Apple, sin KMP ni SQLDelight):**
  - `AppleShared/WebPortalGrades.swift` nuevo: construye el bloque `notas` desde `KmpBridge.buildStudentGradeReports(data:)` (la misma fuente que el PDF) y lo filtra por las columnas visibles.
  - `AppleShared/WebPortalGradeSettings.swift` nuevo: interruptores por columna y «Mostrar la media» por grupo, en `Documentos/EntregasWeb/portal/notas-visibles.json`.
  - `AppleShared/WebPortalSheet.swift`: segmentado «Cuentas · Notas visibles» y estados P1-P5.
  - `AppleShared/WebPortalPublisher.swift`: añadir `notas` al JSON del tablón y una cola con espera de 10 min por grupo.
  - Enganche mínimo donde se guardan notas en el puente (`App/Bridge/KmpBridge+Notebook.swift` y equivalentes de guardado de nota; el worker localiza el punto común) y al aplicar cambios de Sync LAN en el Mac: una llamada `schedulePortalGradesRepublish(classId:)`.
- **Web (`entregas-alumnado`):**
  - `src/portal/`: pestañas «Para hacer · Mis notas», pantallas N1-N6, detalle de rúbrica.
  - `src/vista/textos.mjs`: textos es/en.
  - Sin cambios en `portal.php` ni en el cifrado.

## 3. Fuera de alcance

- Comentarios del docente, observaciones, Inclusión, asistencia y datos brutos.
- Historial de notas o notas de evaluaciones cerradas.
- Notas de varias materias de docentes distintos (cada docente publica su propio tablón).
- Notificaciones push y avisos por correo de «nota nueva».
- Interruptores editables desde el iPad (ver decisión 4.3).
- Cambios en el Cuaderno (`NotebookModuleView.swift` y el grid).

## 4. Modelo de datos

### 4.1 Bloque `notas` dentro del tablón v1 (cifrado como siempre)

```json
"notas": {
  "provisional": true,
  "actualizado": "2026-11-19T18:40:00Z",
  "materias": [{
    "materia": "Educación Física",
    "grupo": "2º ESO B",
    "media": { "valor": 7.4, "nivel": "Notable" },
    "actividades": [{
      "titulo": "Bádminton · Rúbrica de juego",
      "fecha": "2026-11-12",
      "tipo": "rubrica",
      "valor": 8.0,
      "nivel": "Notable",
      "rubrica": [{ "criterio": "Golpeo de fondo", "nivel": "Bueno", "posicion": 3, "de": 4, "descripcion": "…" }]
    }]
  }]
}
```

- `media` solo aparece si «Mostrar la media» está encendido. Es `finalGrade` del caso de uso, sin recalcular.
- Solo entran columnas de `averageExplanation.included` (las que cuentan en la media) **y** con el interruptor encendido.
- Sin `notas` o con `materias` vacío: estado N4. La web no puede saber si hay columnas ocultas.
- El tablón sigue en `schemaVersion: 1`: la web de la fase 1 ignora `notas` (ya ignora claves desconocidas).
- Tamaño estimado: ~10 KB por alumno, muy por debajo del tope de 256 KB.

### 4.2 Interruptores (`notas-visibles.json`, local)

`{ "<classId>": { "media": false, "columnas": { "<columnId>": true }, "confirmadas": ["<columnId>"] } }`. Todo apagado si falta. `confirmadas` guarda las columnas que ya pasaron el aviso P2: se confirma cada columna la primera vez que se enciende.

### 4.3 Decisión: los interruptores viven solo en el Mac

Solo publica el equipo con las llaves (fase 1). Guardarlos en SQLDelight para que viajen al iPad exigiría migración y tocar el puente protegido. En el iPad la pestaña se ve en solo lectura con el aviso P5. Si hace falta editarlos desde el iPad, será otro ticket con `sqldelight-migration`.

### 4.4 Cuándo se publica

- Cambio de nota de una columna visible (en el Mac o llegada por Sync LAN) → cola del grupo con espera de 10 min desde el último cambio.
- Cambio de interruptor → misma cola de 10 min. No hay botón «Publicar ahora»: un solo modelo, automático, con margen para corregir.
- Publicar una tarea o importar entregas (fase 1) incluye ya las notas vigentes.
- Sin red: se reintenta al volver la conexión (P4).

## 5. Plan

1. Revisión breve del diseño por `architect` (punto de enganche de guardado de notas y Sync LAN en el Mac).
2. App: `WebPortalGradeSettings`, `WebPortalGrades` (filtro y JSON), cola de 10 min, pestaña P1-P5, tests.
3. Web: pestañas, N1-N6, detalle de rúbrica, textos, pruebas de pantallas.
4. Prueba de punta a punta como en la fase 1 (docente real en Swift + alumno real en Node + `portal.php` local), ampliada con notas.
5. QA en la app de Mac aislada y en iPad con datos inventados.
6. Registro: CHANGELOG, ADR corto (o anexo al de la fase 1), Trampas del ámbito `entregas-web`.

## 6. Agentes

| Paso | Agente | Modelo |
|---|---|---|
| 1 | `architect` | Opus |
| 2 | `worker` (app) | Sonnet |
| 3 | `worker` (web) | Sonnet |
| Revisión | `reviewer` y `security` | Sonnet / Opus |
| Antes de fusionar | `janitor` | Sonnet |

## 7. Criterios de aceptación

- [ ] Todo apagado de entrada: un grupo sin tocar no publica ninguna nota.
- [ ] Solo salen columnas que cuentan en la media y con su interruptor encendido. Nunca observación, comentarios, Inclusión, datos brutos ni columnas ocultas.
- [ ] Los valores, niveles y descriptores coinciden con el PDF de «Enviar notas al alumnado» para el mismo alumno.
- [ ] La media solo aparece con «Mostrar la media» encendido, y es la del Cuaderno.
- [ ] Un cambio de nota o de interruptor llega al portal entre 10 y 11 minutos después.
- [ ] Una nota evaluada en el iPad llega al portal cuando entra en el Mac por Sync LAN.
- [ ] Al encender cada columna por primera vez sale el aviso P2, con Cancelar por defecto y Escape.
- [ ] En el iPad los interruptores se ven desactivados con el aviso P5.
- [ ] La web muestra N1-N6 tal como la maqueta: nivel en texto (no solo color), nota baja como «Para mejorar» en tinta normal, «Notas provisionales · Pueden cambiar hasta la evaluación» siempre visible, y «¿Dudas con alguna nota? Habla con tu docente».
- [ ] Ningún texto habla de notas «publicadas», «todavía» ni de la media «de lo publicado».
- [ ] Las notas no se guardan en el navegador, ni con «Recordarme en este móvil» (N6).
- [ ] El estado N4 no permite saber si hay notas ocultas.
- [ ] En el servidor no aparece ningún valor, título, materia ni grupo en claro (grep de la prueba de punta a punta).
- [ ] La web de la fase 1 sigue funcionando igual con tablones que traen `notas`.
- [ ] Accesibilidad web: pestañas con roles, táctiles ≥ 48 px, contraste ≥ 4.5:1. App: interruptores con etiqueta, Cancelar con Escape en P2.

## 8. Validación

- App: tests nuevos de filtro, JSON, cola y ajustes en `PlannerTests`; `WebPortalSheetLayoutTests` sigue en verde; build iOS y Mac.
- Web: `npm test` (no puede bajar de 421/0) y `vite build`.
- Punta a punta en local con notas inventadas y grep de privacidad.
- QA visual en Mac aislado e iPad. Registrar qué se ejecutó y qué no.

## 9. Riesgos y puertas humanas

- **Puerta humana: delegado de protección de datos.** Publicar notas parciales es más delicado que publicar tareas.
- **Puerta humana: avisar a las familias** antes de activar la primera columna. Ver las notas cada día cambia cómo las vive el alumnado.
- **Móvil con sesión recordada**: quien tenga el móvil desbloqueado puede ver las notas mientras la sesión dure (hasta 30 días). Se mitiga con la sesión corta por defecto y sin copia local de notas.
- **Nota equivocada**: la espera de 10 min da margen; después, la corrección sustituye a la nota anterior y no queda historial en el servidor.
- **Un alumno en dos grupos del mismo docente** tiene dos fichas y dos cuentas: limitación de la fase 1 que aquí se hereda.

## 10. Entregables

- PR en la app y PR en la web, enlazados.
- Maqueta aprobada y capturas de QA en Mac e iPad.
- CHANGELOG, ADR y Trampas del ámbito actualizados.
