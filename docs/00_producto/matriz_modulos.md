# Matriz de Modulos

Objetivo: mantener una vista ejecutiva de que existe, cual es su fuente de
verdad, que riesgo tiene y cual es la siguiente accion revisable.

## Producto

| Modulo | Estado | Fuente de verdad | Riesgos | Pruebas | Proxima accion |
|---|---|---|---|---|---|
| Dashboard | Activo en Apple. | `DashboardView.swift`, KMP snapshots. | Mostrar metricas no verificadas o demasiado densas. | Build Apple y revision visual. | Confirmar metricas docentes imprescindibles. |
| Cuaderno | Critico y activo. | `NotebookModuleView.swift`, grid SwiftUI, use cases KMP. | Rendimiento, medias, formulas, columnas ocultas y rubricas. | `:shared:test`, build Apple, pruebas manuales con grupos. | Mantener cambios pequenos por flujo. |
| Rubricas | Activo. | `RubricsBuilderScreen.swift`, `RubricEvaluationView.swift`, ViewModels KMP. | Integracion con cuaderno e informes. | Tests KMP de viewmodels/use cases cuando aplique. | Auditar flujo masivo y reporte final. |
| Asistencia | Activo Apple. | `AttendanceWorkspaceView.swift`, Mac attendance views. | Rapidez diaria y persistencia consistente. | Build Apple y prueba manual de sesion. | Definir pruebas de caso de uso. |
| Alumnado | Activo. | `StudentProfilesWorkspaceView.swift`, importadores KMP. | Duplicados, borrado y privacidad. | Tests de importacion y borrado. | Verificar supresion y exportacion por alumno. |
| Planificacion | Activo. | `PlannerWorkspaceIOS.swift`, `PlannerViewModel.kt`. | Continuidad semanal y movimientos de sesiones. | Tests KMP de planner si cambian reglas. | Documentar flujo docente principal. |
| Informes | Activo parcial. | `AppleFoundationReportService.swift`, exportadores data/desktop. | Exportar datos sensibles o calculos sin trazabilidad. | Prueba de PDF/Excel con fixtures. | Crear evidencias de exportacion. |
| Backups | Activo parcial. | `BackupsWorkspaceView.swift`, Mac backups. | Restauracion destructiva o fuga de datos. | Prueba backup/restauracion con fixtures. | Definir checklist de backup por release. |
| Sync local/LAN | En curso o futuro. | `sync/SyncCoordinator.kt`, servicios desktop. | Transferencia no documentada y conflictos. | Tests de contrato antes de activar. | ADR antes de sync externo o comercial. |
| Educacion Fisica | Activo. | `PhysicalTestsWorkspaceView.swift`, escalas y perfiles. | Interpretacion de marcas y datos sensibles de salud/rendimiento. | Tests de dominio fisico y revision UX. | Separar datos brutos de evaluables. |
| IA contextual | Activo parcial. | Servicios Apple Foundation y casos KMP de tendencias. | Transparencia, minimizacion y salida externa. | Build Apple y fixtures anonimos. | Documentar cada flujo de IA. |
| Ajustes | Activo. | `SettingsWorkspaceView.swift`, Mac settings. | Opciones sin utilidad diaria o configuracion no persistida. | Build Apple y prueba manual. | Mantener solo controles necesarios. |

## Capas tecnicas

| Capa | Estado | Fuente de verdad | Riesgos | Pruebas | Proxima accion |
|---|---|---|---|---|---|
| SwiftUI iOS/iPadOS | Target principal. | `kmp/iosApp/App/`. | Vistas grandes y regresiones visuales. | Build iOS Simulator. | Pulir por View y flujo. |
| SwiftUI macOS | Target activo. | `kmp/iosApp/MacApp/`. | Paridad incompleta y convenciones desktop. | Build macOS. | Actualizar matriz de paridad. |
| AppleShared | Compartido Apple. | `kmp/iosApp/AppleShared/`. | Acoplar servicios o duplicar logica. | Build Apple. | Usar para piezas compartidas reales. |
| KMP shared | Logica de negocio. | `kmp/shared/`. | Meter reglas en SwiftUI o romper contratos. | `./gradlew :shared:test`. | Mantener casos de uso testables. |
| KMP data | Persistencia. | `kmp/data/`. | Migraciones, drivers y datos existentes. | `./gradlew :data:desktopTest`. | Auditar esquema real y migraciones. |
| Compose Desktop | Target separado. | `kmp/desktopApp/`. | Versionado y alcance distinto a Apple. | Build desktop cuando se toque. | Alinear packageVersion antes de release. |
| Flutter legado | Referencia historica. | `lib/`, targets Flutter. | Confusion sobre fuente activa. | No aplicar salvo decision explicita. | Decidir legado, referencia o target activo. |
| CI | Basico activo. | `.github/workflows/`. | CI verde no cubre todos los flujos manuales. | PR/push a `main`. | Adjuntar evidencias reales por release. |

## Regla de mantenimiento

Actualizar esta matriz cuando un PR:

- Cambie el estado de un modulo.
- Mueva fuente de verdad entre SwiftUI, KMP, data o desktop.
- Introduzca sync, backup, IA o exportacion nueva.
- Cierre una deuda del roadmap.
- Descubra un riesgo comercial, legal o de privacidad.
