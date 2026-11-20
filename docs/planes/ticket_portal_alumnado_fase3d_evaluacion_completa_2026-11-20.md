# Ticket · Portal del alumnado · Fase 3D: Evaluación completa (histórico y sellos de pasaporte)

- **Estado**: Implementado y verificado (tests Swift + 157 tests web + `vite build` + macOS/iOS builds)
- **Fecha**: 2026-11-20
- **Ramas previstas**:
  - App: `codex/portal-alumnado-fase3d-evaluacion-completa` (`mafepa21/mi_gestor_evaluaciones`)
  - Web: `codex/portal-alumnado-fase3d-evaluacion-completa` (`marfepa/entregas-alumnado`)
- **Maqueta interactiva**: [portal_alumnado_fase3d_evaluacion_completa_2026-11-20.html](../maquetas/portal_alumnado_fase3d_evaluacion_completa_2026-11-20.html)
- **Dependencias previas**: Fase 1, Fase 2 (PR #420), Fase 3B (PR #421), Fase 3A (PR #422) y Fase 3C (PR #423 / Web PR #22), todas fusionadas y desplegadas.

---

## 1. Problema y objetivo

Con el portal cubriendo tareas, notas de la evaluación activa, torneos, pruebas físicas y asistencia, quedan dos piezas de cierre de curso muy valiosas para el alumnado:

1. **Ver su evolución a lo largo del curso**: hoy «Mis notas» muestra una sola pestaña del Cuaderno (`1.ª Eval` o `2.ª Eval`). Cuando avanza el curso, al alumnado y a las familias les ayuda ver la evolución de las evaluaciones cerradas anteriores (`1.ª Eval: 7,8 → 2.ª Eval: 8,4`).
2. **Progreso motivador en el Pasaporte de EF**: hoy un pasaporte por paradas aparece solo como enlace pendiente en «Para hacer», sin enseñar al alumno cuántas paradas ha sellado ya ni qué hitos le faltan.

Esta fase cierra el roadmap del portal manteniendo **4 pestañas limpias** en el móvil (sin añadir una 5.ª pestaña que sature la barra, siguiendo `jobs-design-philosophy`), todo **apagado por defecto** y viajando dentro del mismo tablón cifrado v1 (`K_tablon`), sin cambios en `portal.php`, KMP ni SQLDelight.

---

## 2. Contrato de datos (ampliación compatible del tablón v1)

### A) Campo opcional `historico` dentro de `notas.materias[]`

Solo se incluye si el docente activa una o más evaluaciones anteriores en `Notas visibles`:

```json
"historico": [
  { "titulo": "1.ª Evaluación", "media": { "valor": 7.8, "nivel": "Notable" } },
  { "titulo": "2.ª Evaluación", "media": { "valor": 8.4, "nivel": "Notable" } }
]
```

- Cada entrada representa una pestaña del Cuaderno distinta a la actual marcada como visible por el docente, con la misma `finalGrade` y `finalLevel` del informe del Cuaderno (nunca recalculada en la web).
- Si no hay ninguna evaluación anterior activada, la clave `historico` se omite por completo.

### B) Bloque opcional `pasaporte` en la raíz del tablón v1

Solo se incluye si el docente activa **«Mostrar sellos del pasaporte»** en `EF y seguimiento` y el grupo tiene al menos un formulario `mode == "passport"`:

```json
"pasaporte": {
  "actualizado": "2026-11-20T15:30:00Z",
  "lista": [
    {
      "titulo": "Pasaporte · Balonmano",
      "completadas": 3,
      "total": 4,
      "paradas": [
        { "titulo": "Punto de partida", "hecha": true },
        { "titulo": "Ataque en equipo", "hecha": true },
        { "titulo": "Defensa activa", "hecha": true },
        { "titulo": "Reflexión final", "hecha": false }
      ]
    }
  ]
}
```

- **Regla estricta de privacidad**: solo se exporta el título de cada parada y si está completada (`hecha: true/false`) para ese alumno. **Nunca** viajan respuestas de texto ni datos de compañeros.

---

## 3. Alcance en la App Apple (`mi_gestor_evaluaciones`)

### 3.1. Histórico de evaluaciones en `Notas visibles` (`WebPortalGradeSettings.swift`, `WebPortalGrades.swift`, `WebPortalGradesView.swift`)
- Nuevo campo en `WebPortalGroupGradeSettings` (con decodificación retrocompatible):
  - `var evaluacionesAnteriores: [String] = []` (IDs de pestañas del Cuaderno distintas a la activa).
  - `var evaluacionesConfirmadas: [String] = []`.
- En `WebPortalGradesPane`: si el Cuaderno del grupo tiene más de 1 pestaña, aparece una sección compacta debajo de las columnas:
  - **«HISTÓRICO DE EVALUACIONES»** con un interruptor por cada otra pestaña del Cuaderno (apagado por defecto, confirmación con Cancelar por defecto la primera vez; apagar retira al momento).
- Al construir el bloque `notas`, si `evaluacionesAnteriores` no está vacío, se calcula la media real de cada pestaña activada (usando `WebPortalGrades.scope(sheet:preferredTabId:)`) y se añade `historico` a la materia del alumno.

### 3.2. Sellos del Pasaporte en `EF y seguimiento` (`WebPortalPESettings.swift`, `WebPortalPE.swift`, `WebPortalPEView.swift`)
- Nuevo campo en `WebPortalGroupPESettings` (con decodificación retrocompatible):
  - `var pasaporte: Bool = false`
  - `var pasaporteConfirmado: Bool = false`
- En `WebPortalPEPane`: un interruptor limpio **«Mostrar sellos del pasaporte»** (apagado por defecto, confirmación con Cancelar por defecto) con subtítulo: *«Enseña al alumnado qué paradas de su pasaporte de EF lleva selladas. Nunca muestra sus respuestas.»*
- `WebPortalPE.pasaporteBlock(...)` lee `WebPassportStore` de las instancias `passport` del grupo y determina qué paradas ha completado cada alumno (`WebPassportSections.webTitle`).

### 3.3. Integración con Vista Previa (Fase 3A) y Backup cifrado
- `WebPortalStudentPreviewSheet` («Ver como este alumno…») muestra el bloque **Evolución del curso** en `Mis notas` y las tarjetas de **Sellos del pasaporte** en `Mi EF`.
- `WebPortalBackupVault` ya incluye `notas-visibles.json` y `ef-visible.json`, por lo que los nuevos ajustes quedan respaldados automáticamente en `.migestorbackupx`.

---

## 4. Alcance en la Web (`entregas-alumnado`)

- **Evolución del curso en «Mis notas»** (`src/portal/notas.mjs`, `src/portal/tablon.mjs`):
  - `validarMateria` valida el array opcional `historico` (máx. 10 evaluaciones, título + media válida 0–10).
  - Si existe `historico`, pinta una tarjeta sobria **«Evolución del curso»** con cada evaluación en fila (nombre, nota en monoespaciada y nivel) y tendencia discreta.
- **Sellos del pasaporte en «Mi EF»** (`src/portal/ef.mjs`, `src/portal/tablon.mjs`, `src/portal/pantallas.mjs`):
  - `validarPasaporte` valida `lista` (máx. 10 pasaportes, máx. 20 paradas por pasaporte, solo `titulo` y `hecha`).
  - La pestaña **«Mi EF»** se muestra si existe `fisica`, `asistencia` **o** `pasaporte`.
  - Cada pasaporte muestra una barra de progreso (`3 de 4 paradas`) y una cuadrícula de **sellos circulares** (verde pista «SELLADA» si `hecha: true`, círculo punteado si `hecha: false`).
- **Privacidad en navegador («Recordarme»)**:
  - `sobreParaCopia` elimina también `pasaporte` (junto con `notas`, `torneos`, `fisica` y `asistencia`) antes de sellar la copia local.

---

## 5. Archivos previstos

### App (`mi_gestor_evaluaciones`)
- Modificados en `kmp/iosApp/AppleShared/`:
  - `WebPortalGradeSettings.swift`, `WebPortalGrades.swift`, `WebPortalGradesView.swift`
  - `WebPortalPESettings.swift`, `WebPortalPE.swift`, `WebPortalPEView.swift`
  - `WebPortalPublisher.swift`, `WebPortalSheet.swift`, `WebPortalStudentPreviewSheet.swift`
- Tests en `kmp/iosApp/PlannerTests/`:
  - Ampliar `WebPortalPETests.swift` y `WebPortalGradesTests.swift` / `WebPortalStudentPreviewTests.swift` (histórico de evaluaciones, pasaporte con paradas selladas/pendientes, todo apagado por defecto y retirada inmediata).

### Web (`entregas-alumnado`)
- Modificados: `src/portal/tablon.mjs`, `src/portal/notas.mjs`, `src/portal/ef.mjs`, `src/portal/pantallas.mjs`, `src/vista/textos.mjs`, `src/estilo.css`.
- Tests: ampliar `scripts/probar-portal-ef.mjs` (`validarPasaporte`, `historico` en `validarNotas`, `sobreParaCopia` sin `pasaporte`).

### Archivos protegidos que NO se tocan
- `kmp/iosApp/App/KmpBridge.swift`, `EvaluationDesign.swift`, `kmp/shared/domain/`, `sqldelight/`, `desktopApp/`, `buzon/portal.php`.

---

## 6. Criterios de aceptación

- [x] Histórico de evaluaciones y sellos del pasaporte empiezan **apagados por defecto** y piden confirmación con **Cancelar** como acción por defecto la primera vez.
- [x] En la web del alumno, «Mis notas» muestra «Evolución del curso» solo cuando hay evaluaciones anteriores activadas, y «Mi EF» muestra los sellos circulares del pasaporte solo cuando el docente lo activa.
- [x] `sobreParaCopia` elimina `pasaporte` antes de guardar en `localStorage` con «Recordarme».
- [x] «Ver como este alumno…» refleja ambos bloques en local antes de publicar.
- [x] Tests Swift, tests web (`npm test`), `vite build`, `MiGestorKMPMac` y `MiGestorKMPiOS` pasan en verde.
