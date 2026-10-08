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
