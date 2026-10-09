# Registro de lentitud

La app apunta lo que tarda demasiado con `PerfLog` (`kmp/iosApp/AppleShared/PerfLog.swift`). Solo se apunta lo que supera el límite, así que si no hay nada lento no sale nada.

## Qué se apunta

| Mensaje | Cuándo | Límite |
|---|---|---|
| `Lento: cambio de pantalla a <pantalla> N ms` | Al elegir otra pantalla (iPhone, iPad, Mac) | 150 ms |
| `Lento: Planner: primera carga N ms` | Primera vez que se abre el Planner | 150 ms |
| `Lento: Planner: carga de semana N ms semana S/A` | Cada carga de semana del Planner | 150 ms |
| `Lento: Cuaderno: cambio de grupo N ms` | Desde elegir grupo hasta que llegan sus datos | 150 ms |
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

- **Instruments:** las mismas operaciones salen como intervalos (`os_signpost`) en la plantilla *Logging* o *Time Profiler*.

## Añadir una medida

```swift
let start = DispatchTime.now()
defer { PerfLog.finish("Nombre corto", start: start) }
```

O, para un bloque: `try await PerfLog.measure("Nombre corto") { ... }`.
