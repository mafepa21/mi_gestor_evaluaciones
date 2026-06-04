# Guia visual interna Apple UI

Esta guia fija el criterio visual para nuevas pantallas iOS/iPadOS de Mi Gestor Evaluaciones. Antes de crear estilos locales, reutiliza los tokens de `kmp/iosApp/App/IOSAppStyle.swift` y los componentes de `kmp/iosApp/App/IOSPremiumComponents.swift`.

## 1. Espaciado

Usa una rejilla de 8 pt. Los valores base viven en `IOSAppStyle`:

- Pantalla: `IOSAppStyle.pagePadding` en iPad y `IOSAppStyle.compactPagePadding` en iPhone.
- Secciones: `IOSAppStyle.sectionSpacing`.
- Contenido interno de cards: `IOSAppStyle.cardSpacing`.
- Controles relacionados: 8-12 pt.

Ejemplo:

```swift
VStack(alignment: .leading, spacing: IOSAppStyle.sectionSpacing) {
    header
    IOSSectionCard(title: "Resumen", systemImage: "chart.bar") {
        VStack(alignment: .leading, spacing: IOSAppStyle.cardSpacing) {
            metricRow
            recentActivity
        }
    }
}
.padding(IOSAppStyle.pagePadding)
```

No usar:

- `padding(17)`, `spacing: 13` o valores arbitrarios sin motivo.
- Divisores para separar todo; primero intenta resolverlo con aire.
- Margenes distintos por pantalla si `IOSAppStyle` ya cubre el caso.

## 2. Cards

Las cards son contenedores de informacion o acciones agrupadas, no decoracion. Usa `IOSSectionCard` para secciones generales y componentes especificos del modulo cuando existan, como `NotebookSurface`.

Ejemplo:

```swift
IOSSectionCard(title: "Alumnado", systemImage: "person.3") {
    HStack(spacing: IOSAppStyle.cardSpacing) {
        IOSMetricCard(title: "Activos", value: "28", systemImage: "checkmark.circle")
        IOSMetricCard(title: "Alertas", value: "3", systemImage: "exclamationmark.triangle", tint: IOSAppStyle.warning)
    }
}
```

No usar:

- Cards dentro de cards salvo que sean items repetidos con una razon clara.
- Sombras fuertes, bordes opacos o glass decorativo.
- Radios locales incompatibles con `IOSAppStyle.cardRadius`, `innerRadius` y `controlRadius`.

## 3. Tipografia

La jerarquia tipografica se toma de `IOSAppStyle`:

- Titulo de pagina: `IOSAppStyle.pageTitle`.
- Titulo de seccion: `IOSAppStyle.sectionTitle`.
- Titulo de card: `IOSAppStyle.cardTitle`.
- Texto principal: `IOSAppStyle.bodyText`.
- Metadatos y chips: `IOSAppStyle.captionText`.

Ejemplo:

```swift
VStack(alignment: .leading, spacing: 4) {
    Text("Cuaderno")
        .font(IOSAppStyle.pageTitle)
    Text("2 ESO A - 28 alumnos")
        .font(IOSAppStyle.captionText)
        .foregroundStyle(.secondary)
}
```

No usar:

- Titulos gigantes dentro de paneles densos.
- `.font(.system(size: ...))` local para jerarquia comun si ya existe un token.
- Tracking negativo o escalados dependientes del ancho de pantalla.

## 4. Toolbars

Cada pantalla debe tener una sola barra superior dominante. La toolbar global posee acciones de modulo; las barras locales solo conservan controles acoplados a la superficie actual, como busqueda, filtros o vista activa.

Ejemplo:

```swift
.toolbar {
    ToolbarItem(placement: .primaryAction) {
        Button {
            addColumnContext = NotebookAddColumnContext(categoryId: nil, startsCreatingCategory: false)
        } label: {
            Label("Nueva columna", systemImage: "plus")
        }
    }

    ToolbarItem(placement: .secondaryAction) {
        Button {
            isInspectorPresented.toggle()
        } label: {
            Label("Inspector", systemImage: "sidebar.squares.right")
        }
    }
}
```

Patron aceptado en Cuaderno: `NotebookCompactCommandBar` concentra clase, busqueda, anadir columna, organizar columnas, inspector y menu secundario sin duplicar otro header visible.

No usar:

- Header global mas header local con las mismas acciones.
- Botones con texto largo cuando un icono SF Symbol y accesibilidad bastan.
- Acciones destructivas como botones primarios.

## 5. Empty states

Usa `IOSEmptyState` o `NotebookStateCard` segun contexto. El empty state debe explicar el estado y ofrecer una accion solo si desbloquea el flujo principal.

Ejemplo:

```swift
IOSEmptyState(
    title: "Sin alumnos visibles",
    subtitle: "Ajusta la busqueda o el filtro de grupo para ver filas del cuaderno.",
    systemImage: "person.3.sequence"
)
```

No usar:

- Ilustraciones decorativas que ocupen la superficie de trabajo.
- Tres o mas acciones en un estado vacio.
- Mensajes vagos como "No hay datos" sin siguiente paso.

## 6. Sheets

Usa sheets para tareas acotadas: crear, editar, configurar, organizar o confirmar. En iOS, define detents; en macOS, define ancho y alto minimos. Las sheets deben tener cierre claro y no duplicar el workspace completo.

Ejemplo:

```swift
.sheet(item: $addColumnContext) { context in
    AddColumnSheet(
        bridge: bridge,
        initialCategoryId: context.categoryId,
        startsCreatingCategory: context.startsCreatingCategory,
        onCreatedColumn: handleCreatedColumn,
        onCreatedSummaryColumn: handleCreatedSummaryColumn
    )
    .presentationDetents([.large])
}
```

No usar:

- Sheets para informacion que debe vivir como inspector lateral en iPad.
- Sheets sin detent en iPhone/iPad cuando el contenido es largo.
- Navegacion completa dentro de una sheet si basta con una tarea lineal.

## 7. Inspectores

El inspector es contextual y secundario. En iPad regular debe ser lateral; en iPhone debe presentarse como sheet. Debe abrirse desde una intencion clara: boton de inspector, celda seleccionada con accion contextual o target de alto valor.

Ejemplo:

```swift
if shouldUseSideInspector && isInspectorPresented {
    Divider().opacity(0.16)
    NotebookInspectorPanel(...)
        .frame(width: 360)
        .background(NotebookStyle.surfaceMuted)
}
```

```swift
.sheet(isPresented: Binding(
    get: { !shouldUseSideInspector && isInspectorPresented },
    set: { if !$0 { closeInspectorAndTransientState() } }
)) {
    NotebookInspectorPanel(...)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
}
```

No usar:

- Inspector como columna permanente en iPhone.
- Apertura automatica por cualquier tap incidental.
- Estados de seleccion que sobreviven al cambio de clase, grupo o contexto.

## 8. Estados de carga

La carga debe reservar estructura y evitar saltos. Usa skeletons especificos cuando la pantalla sea densa; en Cuaderno el patron es `NotebookSkeletonGridView`.

Ejemplo:

```swift
if bridge.notebookState is NotebookUiStateLoading {
    NotebookSkeletonGridView(rowCount: 14, columnCount: 7)
}
```

No usar:

- `ProgressView` aislado en una pantalla tabular grande.
- Spinners que bloquean lectura si ya hay datos anteriores utiles.
- Cambios de layout entre loading y loaded.

## 9. Estados de error

Los errores deben ser visibles, breves y recuperables. Usa `NotebookStateCard` o una card equivalente con `IOSAppStyle.warning` o `IOSAppStyle.danger` segun gravedad.

Ejemplo:

```swift
NotebookStateCard(
    systemImage: "exclamationmark.triangle",
    title: "No se pudo cargar el cuaderno",
    message: error.message,
    tint: NotebookStyle.warningTint
)
```

No usar:

- Errores en texto rojo suelto sin contenedor.
- Stack traces o mensajes tecnicos crudos en UI final.
- Alertas bloqueantes para errores recuperables de carga.

## 10. Acciones destructivas

Toda accion destructiva debe tener friccion proporcional al impacto. Usa `confirmationDialog` para borrados simples y una sheet de impacto para borrados con datos asociados.

Ejemplo:

```swift
.confirmationDialog(
    "Eliminar pestana",
    isPresented: $isDeletePresented,
    titleVisibility: .visible
) {
    Button("Eliminar pestana", role: .destructive) {
        deleteTab()
    }
    Button("Cancelar", role: .cancel) {}
} message: {
    Text("Se eliminaran las columnas que solo pertenezcan a esta pestana.")
}
```

Para impactos complejos, sigue el patron `NotebookDeletionImpactSheet`.

No usar:

- Borrado inmediato desde un tap.
- Botones destructivos con estilo prominente azul.
- Confirmaciones genericas que no nombren el objeto afectado.

## Referencias obligatorias

Antes de crear una nueva pantalla o componente:

- Revisa `kmp/iosApp/App/IOSAppStyle.swift` para tokens de espaciado, radios, tipografia y color.
- Revisa `kmp/iosApp/App/IOSPremiumComponents.swift` para cards, command bars, search fields, pills, metric cards, empty states y sheet headers.
- Si el modulo ya tiene componentes propios, reutilizalos antes de crear variantes. En Cuaderno, empieza por `NotebookStyle`, `NotebookSurface`, `NotebookPill`, `NotebookIconButton`, `NotebookPrimaryButton`, `NotebookCompactCommandBar` y `NotebookStateCard`.

## Checklist antes de enviar una pantalla nueva

- Hay una tarea principal clara.
- No hay barras superiores duplicadas.
- Las acciones primarias estan en el nivel correcto.
- El contenido usa la rejilla de 8 pt.
- El estado vacio, loading y error estan definidos.
- iPad regular usa inspector lateral cuando aporta contexto.
- iPhone usa sheets para inspectores y tareas secundarias.
- Las acciones destructivas usan role destructive y confirmacion.
- No hay estilos locales que dupliquen `IOSAppStyle` o `IOSPremiumComponents`.
