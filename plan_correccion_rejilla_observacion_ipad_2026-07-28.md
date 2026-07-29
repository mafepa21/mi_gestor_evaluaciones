# Plan de corrección — Rejilla de observación no aparece en iPad (2026-07-28)

## Contexto

Un agente externo (Google Antigravity) trabajó **directamente sobre `main`** — saltándose la
regla de rama + worktree del repo — para intentar que el instrumento "Rejilla de observación"
se viera en iPad igual que en Mac. Dejó tres commits ya publicados en `origin/main`:

- `cb31aae` `data(synclan): incluir plantillas, items y respuestas de instrumentos estructurados en sincronizacion`
- `77dcb6c` `fix(notebook): paridad iPad/Mac en instrumentos estructurados, auto-recuperacion local y visualizacion de criterios`
- `c16a79e` `fix(notebook): garantizar auto-recuperacion de rejilla de observacion y visibilidad de criterios de evaluacion`

Este plan documenta el diagnóstico real, lo que había que deshacer y lo que había que terminar.

## Diagnóstico

### 1. La causa real del "Sin plantilla" en iPad: la plantilla nunca se sincronizaba

La plantilla estructurada de una rejilla la crea el importador de instrumentos de la situación
de aprendizaje (`saveAssessmentInstrumentTemplateIfNeeded` en `KmpBridge.swift`), a partir del
`.docx`. El docente importó en el Mac, así que la plantilla y sus ítems viven en la base de
datos del Mac.

`KmpBridge.enqueueNotebookSnapshot(forClassId:)` es la función que empuja el Cuaderno completo
al helper de Sync LAN. Emitía 19 entidades (`student`, `evaluation`, `notebook_column`,
`notebook_cell`, `grade`, `rubric_assessment`…) y **ninguna** de instrumentos estructurados.
Comprobado enumerando todos los `enqueueLocalChange(entity:)` del bridge: no existía ni un
`notebook_instrument_template`, ni `_item`, ni `_response`.

Resultado: el iPad recibía la **columna** pero nunca la **plantilla**. Al abrir la celda,
`getTemplateForColumn` devolvía `nil` y la hoja mostraba "Sin plantilla". El Mac funcionaba
porque el dato estaba en su propia base de datos, sin pasar por sync.

Los commits externos añadieron el lado **receptor** en los dos extremos (`KmpBridge` para el
iPad, `SqlDelightSyncAdapter` para el helper), pero nadie emitía esas entidades, así que la
cadena seguía rota.

### 2. La "auto-recuperación" no recuperaba nada: inventaba datos y los persistía

En lugar de cerrar la cadena de sync, `c16a79e` hizo que
`loadStructuredInstrumentEvaluation` **fabricara** una plantilla cuando no la encontraba, con
las sesiones e indicadores del Mac del docente escritos a mano en el código fuente:

```swift
let sessions = ["S2L - juegos autoarbitrados", "S3L - torneo de clasificación", "S4L - Torneo Inclusivo"]
let indicators = ["Respeto, lenguaje y gestión de disputas", "Cumplimiento del rol asignado", "Inclusión activa de compañeros/as"]
```

…y la **guardaba en la base de datos** (`saveTemplate`, `source = "auto_repair"`). El mismo
bloque se duplicó como fallback en memoria en `NotebookStructuredInstrumentSupport.swift`.
Además `c16a79e` quitó la condición que limitaba la reparación a columnas de observación, así
que cualquier columna de instrumento estructurado sin plantilla recibía la rejilla inventada.

Verificado en el Simulador (ver "Evidencia"): con base de datos de demo recién creada, clase
"3 ESO A", alumno "Pablo García", la hoja se abre completa con esos indicadores inventados y
los persiste. Datos que el docente nunca definió, que se guardan como suyos y que la nueva
sincronización propagaría al resto de dispositivos.

Además los ítems inventados usan la clave `obs_item_<n>`, que **no** casa con el contrato
`^obs_s(\d+)_i(\d+)$` que `NotebookInstrumentsRepositorySqlDelight.deriveObservationGridScore`
necesita para calcular la nota: esa rejilla inventada nunca podría generar nota.

### 3. `main` no compilaba en macOS

`cb31aae` introdujo en `SqlDelightSyncAdapter.kt` (Kotlin del helper) diez llamadas a una
propiedad `db` que no existe en esa clase (solo tiene `container`), más un `JsonPrimitive`
sobre un `Double?` y un `value_number` de tipo equivocado. `:data:compileKotlinDesktop` fallaba,
y con él el target `MiGestorKMPMac` (el helper Command Center va embebido). Verificado antes de
tocar nada: iOS Simulator `BUILD SUCCEEDED`, macOS `BUILD FAILED`.

### 4. El criterio se mostraba dos veces y no era un criterio

`c16a79e` reordenó la cascada de `criterionLabel` para poner primero
`competencyCriteriaIds` renderizado como `"CE \(id)"`. Esos son identificadores de fila de la
base de datos, no códigos curriculares, así que sustituían el texto real del criterio por algo
como "CE 47". Y el último escalón caía al **título de la columna**, que ya es el título de la
hoja: el criterio nunca salía vacío porque siempre acababa repitiendo el título.

Encima, el mismo bloque "Criterio: X" se añadió a `ObservationGridInstrumentContent`
cuando ya existía en la cabecera de `StructuredInstrumentEvaluationSheet`: se veía duplicado
dos líneas seguidas (visible en la captura de evidencia).

### 5. Bug preexistente que corrompe justo "la descripción del criterio"

`enqueueNotebookSnapshot` enviaba `"description": evaluation.description`. En Swift,
`description` es el de `NSObject` (el `toString` del objeto Kotlin,
`Evaluation(id=…, code=…)`); el campo real del dominio se expone como `description_`. El resto
del bridge usa `description_` en sus 4 usos. Es decir: cada sincronización mandaba un volcado
del objeto como si fuera el texto del criterio de evaluación. No lo introdujo el agente externo
(viene del snapshot inicial), pero afecta exactamente al dato que el docente echaba en falta.

## Cambios aplicados

| Archivo | Cambio |
|---|---|
| `kmp/data/src/desktopMain/kotlin/com/migestor/desktop/sync/SqlDelightSyncAdapter.kt` | `db.` → `container.database.` (10 sitios); `value_number` serializado a String al emitir y `toDoubleOrNull()` al aplicar. Desbloquea el build de macOS. |
| `kmp/iosApp/App/KmpBridge.swift` | Se elimina la plantilla fabricada y la búsqueda por id alternativo en `loadStructuredInstrumentEvaluation`; cascada de `criterionLabel` honesta (descripción → código → nombre → unidad, sin ids crudos ni título de columna). |
| `kmp/iosApp/App/KmpBridge.swift` | `enqueueNotebookSnapshot` emite `notebook_instrument_template`, `notebook_instrument_item` y `notebook_instrument_response`. Cierra la cadena de sync. |
| `kmp/iosApp/App/KmpBridge.swift` | `evaluation.description` → `evaluation.description_` en el payload de sync y en el filtro de pruebas físicas. |
| `kmp/iosApp/App/NotebookStructuredInstrumentSupport.swift` | Se elimina el fallback de ítems inventados; el estado vacío explica la causa real y la salida (sincronizar). |
| `kmp/iosApp/App/ObservationGridInstrumentContent.swift` | Se retira el "Criterio: X" duplicado. |
| `kmp/iosApp/App/KmpBridge.swift` | Reparación del dato ya corrompido por el bug del punto 5: `recoveredEvaluationDescription` detecta si `description_` es en realidad un volcado anidado del objeto (`Evaluation(id=…, description=Evaluation(…))`) y extrae el `description=` más interno. `repairCorruptedEvaluationDescription` lo reescribe en base de datos (no solo al pintarlo, porque el dato corrupto ya está sincronizado y seguiría circulando). Se engancha en dos sitios: `loadStructuredInstrumentEvaluation` (repara al abrir la hoja del instrumento) y `repairLearningSituationAssessmentInstrumentImportIfNeeded` (repara todas las evaluaciones de la clase, vía `repairCorruptedEvaluationDescriptions`, dentro de la cadena de reparaciones que ya existe). |

Archivo protegido tocado: `KmpBridge.swift`. Motivo: los cuatro defectos (invención de datos,
cascada del criterio, ausencia de emisión de las entidades de instrumento en el snapshot de
sync, y reparación del dato corrompido por el bug de `description`) viven todos ahí y no tienen
otro punto de intervención.

## Evidencia

Todo sobre iPad Pro 13" (M5), iOS Simulator, build Debug real de esta rama.

- Baseline en `origin/main` (`478c311`): iOS Simulator `BUILD SUCCEEDED`, macOS `BUILD FAILED`
  (`:data:compileKotlinDesktop`, `Unresolved reference: db`).
- Arnés temporal de diagnóstico (eliminado antes de commitear) ejecutado sobre base de datos de
  demo limpia, con `main` sin corregir:

  ```
  DIAGINSTR clase=1 nombre=3 ESO A
  DIAGINSTR ANTES plantilla=nil items=-1
  DIAGINSTR MODELO criterio=Rejilla de observación de prueba items=9
  DIAGINSTR MODELO item titulo=S2L - juegos autoarbitrados · Respeto, lenguaje y gestión de disputas
  DIAGINSTR DESPUES plantilla=template_diag_obs_col items=9 source=auto_repair
  DIAGINSTR DESPUES item key=obs_item_1 titulo=S2L - juegos autoarbitrados · Respeto…
  ```

  La plantilla no existía, y tras abrir la hoja existe, inventada y persistida.
- Captura de la hoja en iPad con `main` sin corregir: rejilla completa con los indicadores
  inventados y "Criterio:" repetido dos veces.
- Tras la corrección, mismo arnés, misma base de datos limpia:

  ```
  DIAGINSTR ANTES plantilla=nil items=-1
  DIAGINSTR MODELO nil (sin plantilla)
  DIAGINSTR DESPUES plantilla=nil items=-1 source=nil
  ```

  Ya no se inventa ni se escribe nada. Captura: la hoja muestra "Sin plantilla" con la
  explicación de la causa real.
- Con una plantilla real (ítems `obs_s<N>_i<M>` y una evaluación con descripción), misma hoja en
  iPad: sesiones agrupadas, selector 1-4 por indicador, "Nota final del instrumento" y
  `Criterio: CE 3.2 Participa de forma activa y respetuosa en juegos y deportes…` una sola vez.
  Es la paridad con Mac que se buscaba, pero con datos reales.
- El bug de `description` quedó demostrado en el mismo arnés:

  ```
  DIAGINSTR REAL evaluation.description_=CE 3.2 Participa de forma activa y respetuosa…
  DIAGINSTR REAL evaluation.description=Evaluation(id=3, classId=1, code=CE 3.2, name=…, trace=AuditTrace(…))
  ```

- `./scripts/verify_apple_builds.sh` con el arnés ya retirado: macOS ✓ COMPILADO CORRECTAMENTE,
  iOS Simulator ✓ COMPILADO CORRECTAMENTE.
- `./gradlew :data:compileKotlinDesktop`: BUILD SUCCESSFUL.
- La reparación del dato corrompido (punto 5) se añadió después del corte de cupo del primer
  agente. `./scripts/verify_apple_builds.sh` vuelve a dar macOS ✓ / iOS Simulator ✓ con el código
  de la reparación ya integrado. La lógica de `recoveredEvaluationDescription` se validó a mano
  contra el texto exacto de la captura real que mandó el docente (evaluación id=35, "CE"
  "SA2-I2"): el string tenía 3 niveles de anidamiento y la extracción del `description=` más
  interno recupera correctamente "Instrumento importado desde instrumentos_evaluacion.docx para
  SA 5: Ultimate Frisbee — Torneo Inclusivo".

### Lo que NO se ha podido verificar

- La sincronización real Mac ↔ iPad. Requiere el helper Command Center corriendo en un Mac y un
  iPad emparejado en la misma red; aquí solo hay Simulador.
- La app en macOS ejecutándose. El target compila, pero este entorno no tiene `Simulator.app` ni
  la app de Mac instalada, y no se ha lanzado.
- Un instrumento de tipo Rúbrica abierto en pantalla. Se descartó daño colateral por inspección
  del diff: las únicas apariciones de "rubric" en los tres commits externos son la entidad
  `rubric_assessment` dentro de listas de nombres, sin cambios en su contenido; la evaluación por
  rúbrica usa `rubricEvaluationViewModel` y `rubricsRepository`, un camino que ninguno de esos
  commits toca.
- La reparación del dato corrompido (punto 5) **solo se ha verificado por lectura de código y
  compilación**, no ejecutándola en el Simulador contra un registro corrompido de verdad. El
  primer agente se quedó sin cupo antes de poder montar ese escenario en el arnés de diagnóstico.
  La lógica se revisó a mano contra el texto real de la captura (arriba), pero falta el paso de
  abrir la hoja en el Simulador con una evaluación corrompida y comprobar en pantalla que
  "Criterio:" sale limpio y que el registro en base de datos queda reescrito.

## Qué no se ha tocado

- No se revierten ni reescriben `cb31aae`, `77dcb6c` ni `c16a79e`: siguen en `main` y en
  `origin/main`. Esta rama corrige encima.
- No se toca `kmp/shared/`, `kmp/data/src/commonMain/sqldelight/` ni el esquema.
- No se toca el importador de instrumentos ni el cálculo de nota derivada.

## Riesgos y pendientes

- La emisión de las tres entidades nuevas en `enqueueNotebookSnapshot` **no se ha podido probar
  extremo a extremo**: hace falta un Mac con el helper Command Center y un iPad emparejado en la
  misma red, y este entorno solo tiene un Simulador. Se ha verificado que compila en ambos
  targets y que los nombres de campo del payload coinciden exactamente con los que ya esperan
  los dos lados receptores (`KmpBridge.applyPulledChanges` y `SqlDelightSyncAdapter`).
- `notebook_instrument_template` comparte prioridad de aplicación (2) con `notebook_column`.
  Las claves ajenas no están activadas en Apple (`PRAGMA foreign_keys` nunca se enciende), así
  que no rompe, pero convendría bajar la plantilla a una prioridad estrictamente posterior a la
  columna.
- La aplicación de `notebook_instrument_item` deduce la columna destino recortando el prefijo
  `template_` del id de la plantilla. Si algún día una plantilla no sigue esa convención, sus
  ítems se descartan en silencio.
- El docente que ya haya abierto la rejilla en iPad con el build de `main` tendrá en su base de
  datos una plantilla `source = "auto_repair"` con los indicadores inventados. Al desaparecer la
  fabricación no se regenera, pero **la existente no se borra sola**: habrá que decidir si se
  limpia (`source = "auto_repair"`) o se deja que la sobrescriba la plantilla real al sincronizar.
