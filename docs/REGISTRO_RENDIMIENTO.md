# Registro de lentitud

La app apunta lo que tarda demasiado con `PerfLog` (`kmp/iosApp/AppleShared/PerfLog.swift`). Solo se apunta lo que supera el límite, así que si no hay nada lento no sale nada.

## Qué se apunta

| Mensaje | Cuándo | Límite |
|---|---|---|
| `Lento: arranque hasta Hoy visible N ms` | Desde que arranca el proceso (hora del kernel) hasta el primer resumen de Hoy pintado | 2 s |
| `Lento: cambio de pantalla a <pantalla> N ms` | Al elegir otra pantalla (iPhone, iPad, Mac) | 150 ms |
| `Lento: Planner: primera carga N ms` | Primera vez que se abre el Planner | 150 ms |
| `Lento: Planner: carga de semana N ms semana S/A` | Cada carga de semana del Planner | 150 ms |
| `Lento: Planner: semana visible N ms` | Primera carga, hasta que la semana ya se ve | 150 ms |
| `Lento: Planner: paso <nombre> N ms` | Cada paso de la carga (franjas, grupos, horario, sesiones de la semana, diarios, festivos, exámenes 1º Bach, planes de sesión, reparar planes) | 100 ms |
| `Lento: Cuaderno: cambio de grupo N ms` | Desde elegir otro grupo hasta que llegan sus datos (se publican en cuanto llegan sus filas, sin la espera fija de 150 ms) | 400 ms |
| `Lento: EF: primera carga N ms` | Al abrir Pruebas físicas, hasta tener pruebas, baremos y asignaciones | 150 ms |
| `Lento: Entregas web: lista N ms` | Al entrar en Entregas web, hasta tener la lista | 150 ms |
| `Lento: Entregas web: detalle N ms K tareas` | Detalle de las tareas para importar (por detrás, tras pintar la lista) | 150 ms |
| `Lento: Entregas web: enlaces N ms` | Leer los enlaces del alumnado al pulsar «Enviar enlaces» | 150 ms |
| `Lento: Entregas web: instrumentos publicables N ms` | Al abrir la hoja «Nueva tarea web» | 150 ms |
| `Lento: Cuaderno: preparar columnas N ms` | Construir el dibujo de columnas (solo si no estaba ya preparado) | 30 ms |
| `Lento: Cuaderno: navegación de celdas N ms` | Cálculo que se rehace en cada dibujo de la tabla | 30 ms |
| `Lento: Cuaderno: situaciones de aprendizaje N ms` | Leer las SA del grupo (por detrás) | 30 ms |
| `Lento: Cuaderno: barra de herramientas N ms` | Ajustar la barra de herramientas | 30 ms |
| `Lento: Copia de seguridad N ms` | Cada copia creada | 150 ms |
| `Lento: Sync LAN N ms <motivo>` | Cada sincronización | 1 s |
| `Pantalla congelada N ms` | El hilo de la pantalla no responde (solo versiones Debug) | 250 ms |

## Cómo verlo

- **Xcode:** en la consola, escribe `rendimiento` o `Lento` en el filtro.
- **App Consola de macOS:** elige el dispositivo y busca `subsystem:com.migestor.app category:rendimiento`.
- **Terminal (Mac):**

```bash
log stream --level info --predicate 'subsystem == "com.migestor.app" AND category == "rendimiento"'
```

- **Apuntarlo todo:** lanza la app con `-perf.logAll YES` para que salga cada medida, aunque no sea lenta (útil para una línea base).
- **Instruments:** las mismas operaciones salen como intervalos (`os_signpost`) en la plantilla *Logging* o *Time Profiler*.

## Añadir una medida

```swift
let start = DispatchTime.now()
defer { PerfLog.finish("Nombre corto", start: start) }
```

O, para un bloque: `try await PerfLog.measure("Nombre corto") { ... }`.


## Antes y después: repintados y congelaciones (2026-10-31)

Rama `codex/optimizacion-repintados`. App de Mac en Debug con datos inventados
(2 grupos de 25 alumnos), casa aislada (`HOME` temporal) y `-perf.logAll YES`.
«Antes» = `develop` (e87ba43b) más solo los commits de medida; «Después» = la rama.
Recorrido automático con Accesibilidad: módulos por la barra lateral y grupos por el
menú del Cuaderno. Medianas en ms.

| Medida | Antes | Después | Muestras |
|---|---|---|---|
| Arranque hasta Hoy visible | 294 (media 318) | 298 (media 306) | 10 + 10 arranques alternos |
| Cambio de módulo: Hoy | 158 | 157 | 12 + 12 |
| Cambio de módulo: Asistencia | 221 | 212 | 12 + 10 |
| Cambio de módulo: Cuaderno | 244 (máx. 459) | 112 (máx. 275) | 12 + 11 |
| Cambio de módulo: Pruebas físicas | 101 | 98 | 12 + 11 |
| Cambio de grupo del Cuaderno | 226 | 108 | 6 + 6 |
| Abrir EF (primera carga) | 120 | 120 | 12 + 11 |
| «Pantalla congelada» en 5 min por Hoy, Cuaderno, Asistencia, Planner y EF | 1 (413 ms) | 0 | 1 recorrido de 5 min cada uno |

- El arranque y Hoy quedan igual: la diferencia está dentro del ruido entre arranques.
- La congelación de antes era siempre la primera apertura del Cuaderno (unos 470 ms
  en una sola vuelta del bucle principal). Ahora se reparte en tres vueltas (estructura,
  tabla, filas); la primera ronda los 270 ms en Debug.
- El cambio de grupo ya no espera el debounce fijo de 150 ms: el grupo nuevo se publica
  en cuanto llegan sus filas (`KmpBridge+Notebook.publishNotebookDataWhenReady`).
- EF: la carga ya no bloquea la pantalla (consultas en `Dispatchers.Default`), pero con
  pocos datos el tiempo total es el mismo.
- Solo Mac. En iPad no se midió (no hay recorrido automático allí).

Cómo repetirlo: los scripts del recorrido no están en el repo. El método es lanzar el
binario con `HOME=<carpeta temporal> CFFIXED_USER_HOME=<igual>
XCTestConfigurationFilePath=/dev/null -ApplePersistenceIgnoreState YES -perf.logAll YES`
desde Terminal (desde un proceso sin sesión gráfica no abre ventana) y escuchar con
`/usr/bin/log stream` filtrando por `processImagePath`, porque la app real escribe en el
mismo subsistema.
