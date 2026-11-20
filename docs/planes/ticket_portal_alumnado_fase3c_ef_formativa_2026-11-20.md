# Ticket · Portal del alumnado · Fase 3C: Educación Física y evaluación formativa

- **Estado**: Implementado y verificado (56/56 tests Swift + 156 tests web + `vite build` + macOS/iOS builds)
- **Fecha**: 2026-11-20
- **Ramas previstas**:
  - App: `codex/portal-alumnado-fase3c-ef-formativa` (`mafepa21/mi_gestor_evaluaciones`)
  - Web: `codex/portal-alumnado-fase3c-ef-formativa` (`marfepa/entregas-alumnado`)
- **Maqueta interactiva**: [portal_alumnado_fase3c_ef_formativa_2026-11-20.html](../maquetas/portal_alumnado_fase3c_ef_formativa_2026-11-20.html)
- **Dependencias previas**: Fase 1 (Cuentas), Fase 2 (Mis notas, PR #420), Fase 3B (Torneos, PR #421) y Fase 3A (Base operativa, PR #422), todas fusionadas en `main`.

---

## 1. Problema y objetivo

En Educación Física el valor pedagógico no está solo en una nota final, sino en que el alumnado **vea su propia evolución** y entienda **por qué tiene un nivel en una rúbrica**:

1. **Pruebas físicas**: hoy el alumno solo puede ver la columna de nota en «Mis notas», sin su marca real (`4:15 min`, `2,18 m`), ni sus intentos anteriores ni cuánto ha mejorado respecto al inicio del trimestre.
2. **Asistencia y equipación**: el alumnado pregunta con frecuencia cuántas faltas, retrasos o días sin equipación lleva acumulados. Mostrar un resumen limpio de sus propias fechas ahorra tiempo de clase y evita malentendidos.
3. **Feedback formativo en rúbricas**: en el Cuaderno el docente escribe observaciones útiles en celdas de rúbrica/actividad, pero hoy nunca llegan al portal porque por defecto se tratan como apuntes internos.

Esta fase añade los tres bloques **100 % controlados por el docente** (todo apagado de entrada, con confirmación explícita la primera vez y Cancelar por defecto), viajando dentro del mismo tablón cifrado v1 (`K_tablon`), sin cambios en `portal.php`, KMP ni SQLDelight.

---

## 2. Contrato de datos (ampliación compatible del tablón v1)

Se añaden dos bloques opcionales en el JSON cifrado del tablón (`schemaVersion: 1`) y un campo opcional en las actividades de `notas`:

### A) Bloque `fisica` (opcional; omitido si no hay ninguna prueba activada)

```json
{
  "actualizado": "2026-11-20T12:30:00Z",
  "pruebas": [
    {
      "id": "test-1000m",
      "nombre": "Test 1000m",
      "capacidad": "Resistencia",
      "unidad": "min:s",
      "mejorEsMayor": false,
      "actual": { "marca": "4:15", "valor": 255, "nota": 8.5, "fecha": "2026-11-18" },
      "anterior": { "marca": "4:32", "valor": 272, "nota": 7.2, "fecha": "2026-09-28" },
      "diferencia": "-17 s",
      "mejora": true,
      "intentos": [
        { "fecha": "2026-09-28", "marca": "4:32", "nota": 7.2 },
        { "fecha": "2026-11-18", "marca": "4:15", "nota": 8.5 }
      ]
    }
  ]
}
```

- **Regla estricta de privacidad**: solo los registros del propio alumno (`PhysicalTestResult`). **Nunca** incluye medias de clase, rankings, puestos ni datos de otros compañeros, ni notas privadas de lesiones.

### B) Bloque `asistencia` (opcional; omitido si el interruptor está apagado)

```json
{
  "actualizado": "2026-11-20T12:30:00Z",
  "resumen": {
    "faltas": 2,
    "retrasos": 1,
    "justificadas": 1,
    "sinEquipacion": 1
  },
  "recientes": [
    { "fecha": "2026-11-14", "tipo": "retraso" },
    { "fecha": "2026-11-05", "tipo": "sin_equipacion" },
    { "fecha": "2026-10-22", "tipo": "falta" }
  ]
}
```

- **Regla estricta de privacidad**: **NUNCA** se exportan `Attendance.note`, `hasIncident`, `followUpRequired` ni incidencias de tutoría. Solo fecha (`yyyy-MM-dd`) y tipo (`falta`, `retraso`, `justificada`, `sin_equipacion`). Máximo las últimas 20 incidencias de asistencia para mantener el tablón ligero.

### C) Campo opcional `comentario` en `notas.materias[].actividades[]`

- Solo se incluye `"comentario": "<texto recortado a 400 caracteres>"` cuando el docente ha activado explícitamente el interruptor **«Mostrar comentarios de celda»** en `Notas visibles` (apagado por defecto).

---

## 3. Alcance en la App Apple (`mi_gestor_evaluaciones`)

### 3.1. Nueva pestaña `EF y seguimiento` en `WebPortalSheet`
- Se añade la 4.ª sección en `WebPortalSheet` (`Cuentas`, `Notas visibles`, `Torneos`, `EF y seguimiento`), manteniendo el tamaño acotado (`minHeight: 340, maxHeight: 560`) y `WebPortalSheetLayoutTests` intactos.
- En iPad es de **solo lectura** (mismo patrón que `Notas visibles` y `Torneos`: los interruptores se gobiernan en el Mac y los datos recogidos en iPad se publican al llegar por Sync LAN).
- Contenido (principios `jobs-design-philosophy`, cero ruido):
  - **Bloque 1 · Pruebas físicas del grupo**: lista de pruebas (`PhysicalTestDefinition` asignadas al grupo) con nombre, capacidad, número de alumnos con registro y un interruptor por prueba (todo apagado por defecto).
  - **Bloque 2 · Asistencia del grupo**: un único interruptor **«Mostrar resumen de asistencia»** (apagado por defecto) con subtítulo tranquilizador: *«Solo contadores y fechas de faltas, retrasos y equipación. Nunca tus notas privadas ni incidencias.»*
- Confirmación con **Cancelar por defecto** la primera vez que se enciende una prueba física o la asistencia.
- **Publicación diferida / retirada inmediata**:
  - Persistencia en `Documentos/EntregasWeb/portal/ef-visible.json` y `ef-publicado.json` (solo local en Mac, no viaja por Sync LAN).
  - Encender o editar marcas/asistencia agrupa los cambios en una cola de **10 minutos** (mismo debouncer fiable que `Notas visibles`).
  - **Apagar** una prueba o la asistencia **retira al momento** (`immediately: true`).

### 3.2. Interruptor «Mostrar comentarios de celda» en `Notas visibles`
- Interruptor adicional apagado por defecto bajo «Mostrar la media» en `WebPortalGradesPane`.
- Al encenderlo por primera vez, alerta con **Cancelar por defecto**: *«Las notas de celda escritas en las columnas visibles se mostrarán al alumnado como comentario del docente. Comprueba que no incluyan apuntes internos.»*
- Al apagarlo, retira los comentarios al momento.

### 3.3. Integración con Fase 3A (Vista previa + Backup cifrado)
- `WebPortalStudentPreviewSheet` («Ver como este alumno…») muestra también los bloques `fisica`, `asistencia` y `comentario` para que el docente verifique en local exactamente qué verá el alumno antes de que se publique.
- `WebPortalBackupVault` incluye `ef-visible.json` dentro del respaldo cifrado `.migestorbackupx` (misma protección AES-256-GCM, cero texto claro).

---

## 4. Alcance en la Web (`entregas-alumnado`)

- **Pestaña dinámica «Mi EF»** en el portal (`src/portal/ef.mjs` + integración en `pantallas.mjs` y `portal.mjs`):
  - **Solo aparece** si el tablón trae `fisica` (con al menos 1 prueba) o `asistencia`. Si ambos faltan, la barra de navegación sigue exactamente igual que antes.
  - **Tarjetas de progreso físico**: nombre de la prueba, capacidad, marca actual destacada, insignia de mejora personal (`Mejoraste 17 s` / `+14 cm`), comparativa inicial → actual y barra/línea simple de intentos.
  - **Tarjeta de asistencia** (si existe `asistencia`): 4 contadores limpios (Faltas, Retrasos, Justificadas, Sin equipación) y lista compacta de fechas recientes.
- **Comentarios del docente en «Mis notas»** (`src/portal/notas.mjs`):
  - Si una actividad trae `comentario`, se muestra en una caja cálida destacada («Comentario del docente») debajo del desglose de rúbrica/nota.
- **Privacidad en navegador («Recordarme»)**:
  - `sobreParaCopia` elimina `fisica` y `asistencia` (junto con `notas` y `torneos`) antes de sellar cualquier copia en `localStorage`.

---

## 5. Archivos previstos

### App (`mi_gestor_evaluaciones`)
- Nuevos en `kmp/iosApp/AppleShared/`:
  - `WebPortalPESettings.swift` — Configuración por grupo (`ef-visible.json`) + estado publicado (`ef-publicado.json`).
  - `WebPortalPE.swift` — Construcción pura de los bloques `fisica` y `asistencia`, cálculo de evolución/mejora respetando `higherIsBetter`, y puente `KmpBridge` (`@MainActor` para `suspend`).
  - `WebPortalPEView.swift` — Pestaña «EF y seguimiento» + `WebPortalPEViewModel` + pie de estado.
  - `WebPortalPEWatcher.swift` — Debouncer de 10 min + retirada inmediata al apagar y al arrancar.
- Modificados en `kmp/iosApp/AppleShared/`:
  - `WebPortalGradeSettings.swift`, `WebPortalGrades.swift`, `WebPortalGradesView.swift` — Interruptor `mostrarComentarios` y exportación opcional de `comentario`.
  - `WebPortalPublisher.swift` — Añadir `fisica` y `asistencia` opcionales a `buildBoard` y `republishPortalBoards`.
  - `WebPortalSheet.swift`, `WebSubmissionsWorkspaceView.swift`, `WebPortalStudentPreviewSheet.swift`, `WebPortalBackupVault.swift`.
- Tests nuevos en `kmp/iosApp/PlannerTests/`:
  - `WebPortalPETests.swift` (evolución `higherIsBetter` true/false, privacidad estricta de `Attendance.note`/`hasIncident`, apagado inmediato, comentarios de celda apagados por defecto).

### Web (`entregas-alumnado`)
- Nuevo: `src/portal/ef.mjs` + tests en `pruebas/probar-portal-ef.mjs`.
- Modificados: `src/portal/notas.mjs`, `src/portal/pantallas.mjs`, `src/portal/portal.mjs`, `src/portal/sesion.mjs` (`sobreParaCopia`), `src/estilos.css`.

### Archivos protegidos que NO se tocan
- `kmp/iosApp/App/KmpBridge.swift`, `EvaluationDesign.swift`, `kmp/shared/domain/`, `sqldelight/`, `desktopApp/`, `buzon/portal.php`.

---

## 6. Criterios de aceptación

- [x] Todo empieza **apagado por defecto** (pruebas físicas, asistencia y comentarios de celda); encender la primera vez pide confirmación con **Cancelar** como acción por defecto.
- [x] En la web del alumno, la pestaña «Mi EF» solo aparece si hay pruebas físicas o asistencia visibles; nunca se muestran notas privadas de asistencia, incidencias ni comparativas con otros alumnos.
- [x] `sobreParaCopia` excluye `fisica` y `asistencia` de `localStorage` incluso con «Recordarme».
- [x] «Ver como este alumno…» refleja fielmente pruebas físicas, asistencia y comentarios antes de publicar.
- [x] Tests Swift (`WebPortal*Tests`), tests web (`npm test`), `vite build`, compilación `MiGestorKMPMac` y `MiGestorKMPiOS` pasan en verde.
