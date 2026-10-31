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
| Arranque hasta Hoy visible | 315 (rango 288-473) | 311 (rango 280-329, más un caso de 3 s) | 20 + 20 arranques alternos |
| Cambio de módulo: Hoy | 160 | 160 | 12 + 12 |
| Cambio de módulo: Asistencia | 219 | 214 | 12 + 12 |
| Cambio de módulo: Cuaderno | 245 (máx. 461) | 112 (máx. 280) | 12 + 12 |
| Cambio de módulo: Pruebas físicas | 98 | 98 | 12 + 12 |
| Cambio de grupo del Cuaderno (a mano) | 240 | 97 | 19 + 19 (recorrido) |
| Abrir EF (primera carga) | 122 (media 121,7) | 124 (media 118,9) | 36 + 35 (tres tandas); sin diferencia (Mann-Whitney p = 0,74) |
| «Pantalla congelada» en 5 min por Hoy, Cuaderno, Asistencia, Planner y EF | 1 (413 ms) | 0 | 1 recorrido antes, 3 después (cada uno: 47 cambios de pantalla y 19 de grupo) |

- El arranque y Hoy quedan igual o algo mejor. En una primera versión el arranque salía 6 ms peor
  (276 → 282): la señal de «datos listos» del Cuaderno también adelantaba la carga inicial y
  competía con el primer pintado de Hoy. Ahora solo actúa al pasar de un grupo a otro.
- EF: juntando tres tandas no hay diferencia medible (mediana +2 ms, media −2,8 ms, p = 0,74).
  El cambio de pantalla a EF pasa de 100 a 99 ms (p = 0,28). Lo que sí cambia: las consultas van
  en `Dispatchers.Default` y la pantalla ya no se bloquea mientras carga.
- Asistencia (213 frente a 221 ms, p < 0,01) y Cuaderno (112 frente a 245 ms, p < 0,01) mejoran
  de forma clara; Hoy queda igual (159 y 159, p = 1,0).
- Los casos sueltos de unos 3 s al arrancar salen en las dos versiones (primer arranque tras
  copiar la base).
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
