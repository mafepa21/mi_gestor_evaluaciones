# Ámbito: Alumnado (Mac)

## Estado actual

- Tabla de alumnado a todo el ancho con filtros en una línea encima (seguimiento, clase, grupo de trabajo) y búsqueda en la cabecera. Solo se pintan las excepciones (lesión, seguimiento, faltas, incidencias, observaciones).

## Terreno de juego

- `kmp/iosApp/MacApp/MacStudentsView.swift` (lista, filtros, inspector) y `MacPremiumComponents.swift` (`MacPremiumTableContainer`, `MacPremiumModuleHeader`).
- Datos de fila: `KmpBridge.MacStudentRowSnapshot` en `App/Bridge/KmpBridgeModels.swift`, construido en `KmpBridge+Students.swift`.
- iOS/iPad usa otra vista: `App/StudentProfilesWorkspaceView.swift`.

## Trampas

- `reloadRows` puede resolverse tarde: descarta la respuesta si `selectedClassId` cambió durante la carga. Cualquier carga nueva debe hacer lo mismo.
- `handleClassIdChange` también actúa durante el arranque (`isBootstrapping`).
- Un `Picker` segmentado no encoge: si no cabe, desborda su contenedor (antes se metía bajo la barra lateral). Usar `ViewThatFits` o menú.
- `averageText` llega como texto con punto («9.63» o «--»): se formatea en la vista con `formattedAverage`.
- `recentAttendanceLabel` es texto libre del estado; `notableAttendanceLabel` oculta «presente» y «Sin registro».
- `lastObservationText` vale «Sin observaciones» cuando no hay nada: se compara literal.
- Importador de correos (`AppleShared/StudentEmailImportService.swift`): el curso de la hoja puede ser una ruta sin grupo («/Alumnes/ESO/1ESO 2026-27»), así que se busca en todos los grupos del nivel y decide el nombre del correo. No volver a quedarse con la primera clase que encaje.

## Lesiones con fecha (migración 51, 2026-11-26)

- Tabla `student_injuries` (`StudentInjury.sq` + `51.sqm`), lógica en `kmp/shared/.../injury/`, puente `App/Bridge/KmpBridge+Injuries.swift`, hoja `App/StudentInjurySheet.swift` y bloque `App/StudentInjuryCard.swift` (ficha iPad, inspector de Asistencia iPad/Mac e inspector de Alumnado Mac).
- `students.is_injured` es una **marca derivada** («lesión activa hoy»). Solo la escribe `StudentInjuryUseCase` con `setStudentInjuredFlag`, que **no** toca `updated_at` del alumno. No escribir la marca a mano con `saveStudent`: `reconcileFlags()` la deshará en alumnos con lesiones. Para marcar o quitar, usar `bridge.setStudentInjured` (o `updateStudentInjuryStatus`, que ya pasa por ahí).
- La marca se recalcula: al abrir «Hoy» o cualquier `refreshDashboard()` si cambió el día, al final de cada lote de Sync LAN (Apple en `applyPulledChanges`, Mac en `applyIncomingChangesLww`) y al recoger cambios en el helper. Si añades otra vía de entrada de datos, recalcula al final.
- `reconcileFlags()` solo toca alumnos con alguna fila en `student_injuries`. Una marca antigua sin lesiones se respeta; quitarla deja una fila `legacy-<id>` borrada para que viaje.
- Sync: las lesiones se mandan **siempre todas** (Mac en `collect`, Apple al primer `refreshInjuries()` de cada arranque) para que un aparato actualizado tarde se ponga al día. Los empates de fecha se desempatan por `deviceId`.
- Las filas `legacy-<id>` de la migración tienen `updated_at = 0` y «Desde» = último cambio del alumno.
- Nota de versión: actualizar iPad y Mac antes de volver a sincronizar.
- Sin diagnósticos ni fotos: el justificante es solo una casilla (decisión del docente, 2026-11-26).
