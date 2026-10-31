# ADR-2026-10-31: Vistas sin observar el bridge entero

## Estado

Aprobado

## Contexto

`KmpBridge` publica unos 50 valores (`@Published`). 62 vistas lo observaban entero con `@EnvironmentObject var bridge`. Cualquier cambio, como una nota guardándose, el estado de SyncLAN cada pocos segundos o un estado nuevo del Cuaderno, las obligaba a recalcularse todas, se vieran o no. El Planner ya lo había resuelto a mano con `@Environment(\.kmpBridgeReference)` y un store propio (`PlannerWorkspaceViewModel`). Crear un store por módulo para las 62 vistas era mucho cambio y mucho riesgo.

## Decisión

- Ninguna vista observa `KmpBridge` con `@EnvironmentObject`. Todas leen la referencia sin suscripción: `@Environment(\.kmpBridgeReference)`.
- Las vistas que solo llaman acciones del bridge no se suscriben a nada.
- Las vistas que pintan datos publicados usan `KmpBridgeWatch` (`KmpBridgeObservationStores.swift`): un `@StateObject` que escucha `objectWillChange` del bridge, en la vuelta siguiente compara solo los valores que la vista declara y avisa a la vista si alguno cambió. La lista de valores va junto a la vista: `bridgeWatch.bridge(bridgeReference) { [.init($0.classes), .init($0.rubrics)] }`.
- Los estados Kotlin grandes (`notebookState`) se comparan por identidad (`ObjectIdentifier`), no por contenido.
- Si la vista pasa el bridge a una hija con `let bridge` (sin observarlo), la lista incluye lo que lee la hija.
- Las raíces, ventanas y hojas ponen el bridge con `kmpBridgeEnvironment(_:)`, que lo inyecta como objeto y como referencia. La app de Mac solo inyectaba el objeto.
- Los stores existentes (`NotebookBridgeStore`, `DashboardBridgeStore`, `ShellBridgeStore`, el del Planner…) siguen igual: son la opción preferida cuando un módulo lee mucho estado.

## Alternativas descartadas

- Un store por módulo para todas las vistas: más limpio, pero obliga a reescribir 42 archivos y a duplicar en cada store el estado que ya tiene el bridge.
- Mantener `@EnvironmentObject` y quitar `@Published` del bridge: obliga a tocar `KmpBridge.swift` (protegido) y rompe las vistas que sí necesitan refrescarse.
- Vigilar con `[AnyHashable]`: algunos tipos de Swift del bridge (`AcademicYearSnapshot`, `SyncDivergenceReport`) solo son `Equatable`.

## Consecuencias

- Un cambio del Cuaderno o de SyncLAN ya no redibuja Rúbricas, Cursos, Ajustes, Entregas web, etc.
- Riesgo: si una vista lee una propiedad publicada que no está en su lista, deja de refrescarse con ella. Al añadir una lectura del bridge en una vista con `KmpBridgeWatch`, hay que añadirla a la lista.
- `bridgeReference!` falla si una vista se monta sin `kmpBridgeEnvironment`, igual que antes fallaba `@EnvironmentObject`.
- Comprobación: `grep -rn "@EnvironmentObject.*KmpBridge" kmp/iosApp` debe dar 0.
- Medidas antes y después: `docs/REGISTRO_RENDIMIENTO.md`.
