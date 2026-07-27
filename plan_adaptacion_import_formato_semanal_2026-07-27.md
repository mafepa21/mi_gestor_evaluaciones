# Plan de adaptación: importación del formato semanal y checklists ponderadas (2026-07-27)

## Contexto

Continúa `plan_correccion_import_sa_2026-07-25.md`, cuyos bloques A, B y C ya están en `main`.
Quedaban tres cosas pendientes tras auditar los tres importadores contra los documentos reales
de `~/Desktop/Programaciones/output/Programación aula/Situaciones de aprendizaje/`:

1. Las checklists con peso se tipan bien (`checklistProportional`) pero **bloqueaban el import**.
2. El nuevo formato de sesiones por semana (`sesiones_por_semana.docx`, piloto de SA 5)
   importaba **0 sesiones**.
3. El peso porcentual de una columna importada seguía pintándose como `×0,4` (D1 del plan
   anterior, dado por hecho en el changelog pero no implementado).

La guía de autoría del formato semanal vive fuera del repo, en
`Knowledge/estructuras/GUIA_AUTORIA_SESIONES_SEMANALES.md`.

---

## Bloque 1 — Checklists ponderadas: de bloqueo a nota real

### Diagnóstico

`AssessmentInstrumentScoreStrategy.CHECKLIST_PROPORTIONAL` no estaba en
`materializableAverageStrategies`, `validationIssues()` emitía un issue con
`blocksMaterialization = true`, y `LearningSituationsWorkspaceView` lo traducía en un error de
validación que dejaba `canConfirm == false`. El docente tenía que desmarcar "cuenta en la media"
instrumento a instrumento (en SA 4, 3 instrumentos y el 50 % de la nota).

La causa de fondo era real: la nota no se calculaba en ningún sitio.
`NotebookInstrumentsRepositorySqlDelight.saveResponses` solo derivaba nota para las rejillas de
observación (`obs_s<sesión>_i<indicador>`).

### Fix

- `saveResponses` deriva también `ítems marcados ÷ ítems totales × 10` para los ítems con clave
  `chkp_<n>`.
- El importador Apple genera esa clave **solo** para `checklistProportional`; las checklists de
  entrega y las de todo/nada siguen con `check_<n>`, así que nada ya importado cambia.
- `CHECKLIST_PROPORTIONAL` entra en `materializableAverageStrategies` y desaparece el issue
  bloqueante.
- La columna materializada pasa a numérica con escala 0-10 (entrada: checklist estructurada).

### Verificación

Simulación sobre los 8 `instrumentos_evaluacion*.docx` reales, compilando el importador de
`origin/main` y el de esta rama y comparando salida:

| SA | Antes (auto-calculable) | Después |
|---|---|---|
| SA 1 | 100 % | 100 % |
| SA 2 | 90 % | **100 %** |
| SA 3 | 95 % | **100 %** |
| SA 4 | 50 % | **100 %** |
| SA 4b | 90 % | **100 %** |
| SA 5 | 100 % | 100 % |
| SA 5 PILOTO | 100 % | 100 % |
| SA 6 | 65 % | **100 %** |

---

## Bloque 2 — Formato semanal (BLOQUE LARGO / BLOQUE CORTO)

### Diagnóstico

`LearningSituationSessionSequenceDocumentImportService` reconoce las fichas con
`^(?:SESI|SESSI)(?:ÓN|ON|ONES|ONS)\s+N`. El documento semanal usa `SEMANA N` y
`BLOQUE LARGO`/`BLOQUE CORTO`: 0 encabezados → 0 sesiones y el aviso "No se han reconocido
fichas de sesión". Además, el modelo asumía "una sesión con dos versiones" y ante ellas tomaba
30′ con aviso — justo lo que el formato semanal viene a sustituir.

### Fix

- Nuevo patrón `SEMANA|SETMANA|WEEK N` con separador explícito (mismo criterio anti-falsos
  positivos que B3).
- Detección de `BLOQUE LARGO`/`BLOQUE CORTO` (y `LONG`/`SHORT BLOCK`) con sus minutos.
- Tabla de dos variantes (`Variante PREPARA` / `Variante CONSOLIDA`) → dos secciones de
  desarrollo, conservando franja horaria y fase.
- Ficha `Item | Detail` de la semana → objetivo, criterios, saberes, materiales y `Assessment`
  (etiqueta nueva) para los dos bloques; preguntas guía, variantes y adaptaciones también.
- Cada semana `N` genera dos sesiones: `2N-1` (largo, 90′) y `2N` (corto, 30′).
- El resumen final de la SA (`Resumen de momentos de evaluación`) deja de absorberse dentro de
  la última semana.
- Encabezado de desarrollo propio del formato semanal: no se reutiliza `isDevelopmentHeading`,
  que acepta cualquier párrafo con un rango numérico y convertía prosa ("3-4 comisiones") en
  secciones vacías.

### Lo que NO hace (y por qué)

La colocación automática **no** está implementada. La app no ubica hoy las sesiones de una
secuencia contra el horario del grupo: la ubicación es manual, sesión a sesión, desde el Planner
("Pendiente de ubicar" → "Ubicar S*n*"). Implementar `bloque + horario del grupo → día` es una
funcionalidad nueva del Planner (emparejamiento por slots consecutivos del grupo, no por semana
ISO), no un cambio del importador, y queda fuera de esta tarea. El import deja un aviso
explicando la regla: el bloque largo va en el día de sesión doble y el corto en el simple.

### Verificación

- `sesiones_por_semana_PILOTO.docx`: de **0** sesiones a **8 bloques** (4 semanas × 2), todos
  con objetivo, criterios, material y desarrollo.
- Los **11** documentos del formato antiguo producen una salida **idéntica byte a byte** a la de
  `origin/main` (mismo binario de comparación, mismos `.docx`).

---

## Bloque 3 — Peso porcentual en la cabecera del cuaderno (D1)

`columnWeightBadge` pintaba `×0,4` para un instrumento del 40 %. Se añade la rama de porcentaje
para columnas ligadas a una evaluación importada con peso fraccionario; los multiplicadores
manuales no cambian.

---

## Archivos tocados

- `kmp/data/src/commonMain/kotlin/com/migestor/data/repository/NotebookInstrumentsRepositorySqlDelight.kt`
- `kmp/data/src/desktopTest/kotlin/com/migestor/data/repository/NotebookInstrumentsRepositorySqlDelightTest.kt`
- `kmp/shared/src/commonMain/kotlin/com/migestor/shared/domain/AssessmentInstrumentSpec.kt` (protegido)
- `kmp/shared/src/commonTest/kotlin/com/migestor/shared/AssessmentInstrumentSpecTest.kt`
- `kmp/iosApp/App/KmpBridge.swift` (protegido)
- `kmp/iosApp/App/LearningSituationsWorkspaceView.swift`
- `kmp/iosApp/App/NotebookModuleGridCells.swift`
- `kmp/iosApp/AppleShared/LearningSituationAssessmentInstrumentsImportService.swift`
- `kmp/iosApp/AppleShared/LearningSituationDocumentImportService.swift`

Los dos archivos protegidos se tocan porque el bloqueo vive exactamente ahí: `canMaterializeAverage`
y el prefijo de clave de los ítems (`KmpBridge`) y el conjunto de estrategias materializables
(`AssessmentInstrumentSpec`). Los cambios son mínimos y acotados a la checklist ponderada.

## Verificación ejecutada

- `xcodebuild -scheme MiGestorKMPMac -configuration Debug -destination 'platform=macOS,arch=arm64'`
  → **BUILD SUCCEEDED**.
- `./gradlew :shared:desktopTest` → **BUILD SUCCESSFUL**.
- `./gradlew :data:desktopTest` → 92 tests, **1 fallo preexistente** (`saveResponses derives an
  observation grid score…`, 6,944 vs 3,083 esperado). Comprobado sobre `origin/main` sin ningún
  cambio: mismo fallo (90 tests, 1 fallo). No lo introduce esta rama y no se toca aquí.
- Simulación de los tres importadores sobre los `.docx` reales compilando el código de esta rama
  y el de `origin/main` (banco de pruebas fuera del repo).
