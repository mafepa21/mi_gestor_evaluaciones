# Avances y madurez premium de Mi Gestor Evaluaciones

Fecha: 2026-05-31

## 1. Proposito del documento

Este documento consolida los avances detectados en el repositorio y en los hilos recientes de Codex, y convierte ese historial en una hoja de ruta para llevar la app a una experiencia madura, premium y fiable de uso diario en iOS, iPadOS y macOS.

Fuentes revisadas:

- `memoria`
- `progress.md`
- `findings.md`
- `task_plan.md`
- `.workflow/*/final-report.md`
- `kmp/docs/architecture/MACOS_PARITY_MATRIX.md`
- Estructura actual de `kmp/iosApp/App`, `kmp/iosApp/MacApp`, `kmp/iosApp/AppleShared`, `kmp/shared` y `kmp/data`
- Hilos recientes accesibles desde Codex: auditoria de bugs iOS/macOS, auditoria UI macOS, aplicacion de recomendaciones UI macOS, split de servicios monoliticos e importador de situaciones de aprendizaje.

Limitacion: algunos hilos antiguos aparecen como `notLoaded` en Codex y no se pudieron leer completos desde la herramienta de hilos. En esos casos se han usado el titulo, preview y los artefactos locales `.workflow/` cuando existen.

## 2. Resumen ejecutivo

La app ha evolucionado desde una base Flutter historica hacia una arquitectura KMP + SwiftUI mucho mas ambiciosa. El nucleo actual apunta bien: dominio compartido, SQLDelight, app Apple nativa, macOS especifico, sync LAN, backups, informes, cuaderno avanzado, planificacion, asistencia, rubricas, diario, alumnado, Educacion Fisica y situaciones de aprendizaje.

El salto pendiente no es "anadir muchas pantallas", sino cerrar madurez operativa:

- Fiabilidad de persistencia y migraciones.
- Paridad real entre iPad y macOS en los flujos diarios.
- Cuaderno rapido, estable y explicable.
- Sync/backup robustos fuera del entorno de desarrollo.
- UI Apple premium con menos ruido visual, jerarquia mas clara y acciones diarias mejor priorizadas.
- Verificacion repetible: builds, pruebas de repositorio, pruebas de smoke UI y fixtures de datos reales.

El repositorio tiene una senal clara de crecimiento: hay 151 archivos Apple Swift en `App`, `MacApp` y `AppleShared`, con varios archivos grandes. Esto no es necesariamente malo, pero indica que la siguiente fase debe priorizar estabilidad, modularidad quirurgica y verificacion antes que expansion indiscriminada.

## 3. Avances consolidados

### 3.1 Arquitectura KMP y persistencia

Avances:

- Reescritura KMP activa con modulos `shared`, `data`, `desktopApp`, `androidApp` y `commandCenterHelper`.
- SQLDelight con migraciones numeradas hasta `24.sqm`.
- Dominio compartido para alumnado, clases, cuaderno, planificacion, rubricas, asistencia, informes, sync y modulos de Educacion Fisica.
- Campos de auditoria/sync en varias entidades, senalando preparacion para reconciliacion futura.
- Repositorios SQLDelight especializados, con nuevas areas como situaciones de aprendizaje.

Valor de producto:

- La app ya no depende solo de UI; tiene una base de dominio y persistencia preparada para crecer.
- La estrategia local-first es adecuada para profesorado: uso en aula, continuidad sin red y control de datos.

Pendiente para madurez:

- Cubrir migraciones 23/24 y repositorios nuevos con tests de compatibilidad.
- Reducir monolitos de inyeccion/repositorios con facades pequenas y verificables.
- Documentar contrato de sync/conflictos antes de seguir ampliando datos sincronizables.

### 3.2 App Apple iOS/iPadOS

Avances:

- Shell iPad/iOS amplio con workspace docente.
- Cuaderno con grid, categorias, formulas, columnas configurables, columnas ocultas, rubricas, evidencias y acciones compactas.
- Planificacion didactica con sesiones, unidades, trazas y plantillas.
- Asistencia, alumnado, diario, informes, rubricas, Educacion Fisica y perfiles de alumnado.
- Acciones recientes en Cuaderno:
  - Duplicar estructura entre clases.
  - Preservar vinculaciones evaluacion/rubrica al duplicar columnas.
  - Copiar/pegar valoraciones en evaluacion masiva por rubrica.
  - Evitar reemplazo silencioso de grupos de trabajo duplicados.
  - Reordenar columnas por drag-and-drop.
  - Redimensionar columnas con anchuras sincronizadas entre cabecera y celdas.
  - Menu de color por long-press separado del gesto de arrastre.

Valor de producto:

- El Cuaderno esta pasando de prototipo funcional a herramienta operativa real.
- La duplicacion de estructura y la mejora de rubricas atacan tareas diarias de alto valor docente.

Pendiente para madurez:

- Pasada especifica de rendimiento del grid con dataset grande.
- Batch backend para visibilidad/reordenacion de columnas; ya hay TODOs en `NotebookModuleColumnModel.swift`.
- Smoke test de edicion de celda, guardado pendiente, categorias, formulas, columnas ocultas y rubricas.
- Simplificar barras/acciones para que la tarea principal sea obvia en cada modo.

### 3.3 App macOS

Avances:

- App macOS nativa con `MacRootView`, vistas especificas, `NavigationSplitView`, inspector y modulos adaptados.
- Auditoria de bugs iOS/macOS completada con builds Debug correctos.
- Fixes aplicados:
  - Settings de macOS ya no abre una ventana vacia.
  - Persistencia de visibilidad de sidebar restaurada.
  - `MiGestorCommandCenter.app` se embebe en recursos de la app macOS.
  - Fases de build KMP forzadas para reducir riesgo de frameworks obsoletos.
- Auditoria UI macOS completada:
  - Fundacion macOS correcta.
  - Necesidad principal: reducir chrome, clarificar jerarquia y usar motion sobrio.
- Primer slice UI aplicado:
  - `MacAppStyle` incorpora tokens de motion pequena.
  - `MacPremiumControlStrip` como alternativa menos pesada.
  - Transiciones pequenas en estados/loading.
  - Asistencia adopta el control strip ligero.

Valor de producto:

- macOS deja de ser solo "adaptacion" y empieza a tener criterios de app de escritorio: inspector, sidebar, settings, helper embebido y controles mas densos.

Pendiente para madurez:

- Dashboard focus pass: que "Ahora" sea el centro operativo diario.
- Simplificacion de toolbar del Cuaderno en macOS.
- Inspector continuity en alumnado/asistencia/pruebas fisicas.
- Screenshot audit runtime con datos reales, no solo inspeccion estatica.
- Verificacion signed/notarized para distribucion.

### 3.4 IA Apple, informes y servicios

Avances:

- Servicios Apple Foundation para IA contextual e informes.
- Split de servicio monolitico:
  - `PhysicalScaleProfileService.swift` extrae catalogo/perfiles deterministicos de escalas fisicas.
  - `AppleFoundationContextualAIService.swift` queda mas centrado en orquestacion IA, prompts, generacion y fallback.
- Builds iOS y macOS pasaron en el hilo de split segun resumen de Codex, aunque el `final-report.md` local no quedo tan actualizado como el cierre del hilo.

Valor de producto:

- La IA empieza a separarse de reglas deterministicamente testeables, lo cual mejora mantenibilidad y confianza.

Pendiente para madurez:

- Separar builders de evidencias docentes en archivo/servicio dedicado.
- Anadir fixtures para validar informes sin depender de ejecucion manual.
- Definir degradacion clara cuando Apple Intelligence no este disponible.

### 3.5 Sync, pairing y backups

Avances:

- Sync LAN visible en macOS con Command Center helper.
- Pairing iPad/macOS y observabilidad basica.
- Backup service Apple compartido.
- Fix relevante: helper macOS embebido en el bundle, evitando que funcione solo desde el arbol de desarrollo.

Valor de producto:

- Sync y backup son diferenciales para uso diario: continuidad entre dispositivos y confianza ante perdida de datos.

Pendiente para madurez:

- Pruebas de app relocada/packaged.
- Tests de backup/restore con fixture real.
- Matriz de conflictos sync: mismo alumno/celda/sesion editado en dos dispositivos.
- UI de estado de sync que distinga "guardado local", "pendiente", "sincronizado" y "conflicto".

### 3.6 Situaciones de aprendizaje

Avances detectados:

- Hilo especifico para importar situaciones de aprendizaje.
- Archivos nuevos en el worktree:
  - `LearningSituationsWorkspaceView.swift`
  - `LearningSituationDocumentImportService.swift`
  - `LearningSituationsRepositorySqlDelight.kt`
  - migraciones `23.sqm` y `24.sqm`
- Integracion aparente con `IOSFeatureRegistry`, `MacFeatureRegistry`, `KmpContainer`, dominio y repositorios.

Valor de producto:

- Es una pieza importante para convertir la app en sistema docente completo, no solo cuaderno.

Pendiente para madurez:

- Validar parsing con documentos reales variados.
- Definir revision humana antes de guardar datos importados.
- Tests de migracion y repositorio.
- UI de asociacion a curso/grupo/pantallas con errores recuperables.

## 4. Hilos y conversaciones organizadas

### Hilos principales recientes

| Categoria | Hilo | Estado | Resultado util |
| --- | --- | --- | --- |
| Direccion actual | `Organiza avances y hilos` | activo | Este documento y organizacion del historial. |
| UI macOS | `Mejora UI macOS` | idle | Auditoria UI macOS y primer slice aplicado. |
| Calidad iOS/macOS | `Busca bugs iOS y macOS` | idle | Auditoria de bugs y fixes posteriores documentados en `.workflow/`. |
| Arquitectura | `Split monoliths into mini services` | idle | Split de `PhysicalScaleProfileService`; candidatos futuros documentados. |
| Producto/datos | `Anade importador de situaciones` | notLoaded | Cambios de situaciones de aprendizaje visibles en worktree. |
| Cuaderno | `Optimiza cuaderno y sync` | notLoaded | Contexto de rendimiento del Cuaderno, categorias iOS y sync pendiente. |
| Runtime macOS/iOS | `Corrige constraints conflictivas` | notLoaded | Logs de constraints y crash index out of range; revisar si ya quedo cubierto por fixes. |
| Bridge | `Corrige KmpBridge faltante` | notLoaded | Problema previo de `EnvironmentObject` faltante en KmpBridge. |

### Artefactos `.workflow/`

| Workflow | Tipo | Estado |
| --- | --- | --- |
| `find-bugs-in-ios-and-macos-app` | Auditoria | Completado; detecto 4 issues aceptados. |
| `fix-found-ios-and-macos-bugs` | Implementacion | Completado; aplico fixes macOS/build. |
| `macos-ui-improvement-audit` | Auditoria UI | Completado; priorizo chrome reduction, foco y motion sobrio. |
| `apply-macos-ui-recommendations` | Implementacion UI | Completado; primer slice en componentes macOS y Asistencia. |
| `monolithic-services-to-mini-services` | Arquitectura | Completado; split fisico de servicio IA/EF. |

### Reglas de organizacion para siguientes hilos

Usar una taxonomia fija en titulos:

- `MiGestor | Cuaderno | ...`
- `MiGestor | macOS | ...`
- `MiGestor | iPadOS | ...`
- `MiGestor | KMP/Data | ...`
- `MiGestor | Sync/Backup | ...`
- `MiGestor | IA/Informes | ...`
- `MiGestor | Auditoria | ...`

Cada hilo deberia cerrar con:

- Resumen ejecutivo.
- Archivos tocados.
- Comandos probados.
- Riesgos.
- Entrada en `memoria` si hubo avance significativo.
- Link al workflow si se uso `.workflow/`.

## 5. Lo que falta para una app madura y premium

### P0: Fiabilidad diaria

Objetivo: que un docente pueda usar la app sin miedo a perder datos.

Pendiente:

- Tests de migracion SQLDelight, especialmente 23/24.
- Backup/restore probado con base real.
- Sync LAN probado con app empaquetada y app relocalizada.
- Estados claros de guardado local y sync pendiente.
- Manejo de errores recuperable en importaciones y servicios IA.

Criterio de salida:

- Crear datos, cerrar app, reabrir, modificar desde otro dispositivo, sincronizar, restaurar backup y verificar integridad sin pasos manuales fragiles.

### P1: Cuaderno premium

Objetivo: que el Cuaderno sea rapido, estable y explicable con grupos reales.

Pendiente:

- Perfilado de grid con muchas filas/columnas.
- Batch persistence para cambios masivos de columnas.
- Test de formulas/promedios/rubricas/ocultas.
- Inspector no invasivo y contextual.
- Toolbar por tareas: evaluar, configurar, analizar, importar/exportar.

Criterio de salida:

- Cambiar de grupo, editar notas, usar formulas y rubricas, ocultar columnas y revisar medias sin lag perceptible ni dudas sobre que dato se esta evaluando.

### P1: macOS de escritorio real

Objetivo: que macOS no parezca una version agrandada de iPad.

Pendiente:

- Dashboard con foco diario.
- Menus, shortcuts y toolbar nativos.
- Inspector consistente.
- Preferencias completas.
- Smoke visual con capturas en ventanas pequena, media y grande.
- Build firmado/notarizado de prueba.

Criterio de salida:

- La app puede vivir abierta todo el dia en macOS, con navegacion rapida, acciones de teclado y estados visibles sin saturar la pantalla.

### P1: iPadOS de aula

Objetivo: que iPad sea rapido en clase, con pocas decisiones por pantalla.

Pendiente:

- Reducir ruido en workspaces densos.
- Revisar acciones principales por modulo.
- Gestos claros en Cuaderno sin conflicto entre drag, long-press y edicion.
- Estados offline/sync visibles pero discretos.

Criterio de salida:

- Registrar asistencia, editar cuaderno, evaluar rubrica y consultar planificacion en menos de tres gestos claros por tarea habitual.

### P2: IA e informes confiables

Objetivo: que la IA sea util sin invadir ni inventar decisiones docentes.

Pendiente:

- Fallbacks deterministas y mensajes claros cuando IA no este disponible.
- Evidencias e informes con trazabilidad de datos usados.
- Plantillas verificables.
- Revision humana antes de guardar o exportar.

Criterio de salida:

- El usuario sabe que datos entran al informe, puede corregirlos y puede generar una salida consistente aunque no haya IA disponible.

### P2: Modularidad y mantenibilidad

Objetivo: sostener el crecimiento sin convertir cada cambio en riesgo transversal.

Pendiente:

- Extraer `DemoDataSeeder` desde `KmpContainer`.
- Separar builders de informes/evidencias.
- Seguir dividiendo vistas grandes por ownership real, no por estetica.
- Mantener `KmpBridge.swift` estable y tocarlo solo cuando sea imprescindible.

Criterio de salida:

- Cambios pequenos en un modulo no obligan a compilar mentalmente toda la app.

## 6. Roadmap recomendado por cortes

### Corte 1: Cierre de fiabilidad base

- Verificar migraciones 23/24.
- Test de repositorio de situaciones de aprendizaje.
- Smoke backup/restore.
- Smoke sync helper en app empaquetada.

### Corte 2: Cuaderno sin lag

- Perfilado del grid.
- Batch save de visibilidad/reordenacion.
- Smoke de edicion, categorias, formulas y rubricas.
- Revision de toolbar del Cuaderno.

### Corte 3: macOS premium operativo

- Dashboard focus pass.
- Adoptar `MacPremiumControlStrip` en un segundo modulo.
- Inspector continuity.
- Capturas runtime y correcciones visuales.

### Corte 4: iPadOS aula

- Pasada de simplicidad en `IPadWorkspaceShell`.
- Acciones primarias por modulo.
- Reduccion de chrome y divisores.
- Verificacion con flujo real de clase.

### Corte 5: IA, informes y documentos

- Separar builders.
- Fixtures de informes.
- Fallbacks de IA.
- Exportacion revisable.

## 7. Riesgos actuales

- Worktree sucio con cambios amplios, incluidos archivos protegidos como `KmpBridge.swift`, `kmp/shared` y `kmp/data`.
- `project.pbxproj` puede recoger cambios preexistentes al regenerar con XcodeGen.
- Algunos reportes locales `.workflow/` no reflejan todo lo que el cierre del hilo indica; conviene actualizar final-reports cuando se retomen.
- Hay archivos Swift muy grandes; cualquier refactor debe ser por flujo y con build despues.
- Falta evidencia visual runtime para varias recomendaciones UI.

## 8. Proxima accion recomendada

La accion mas rentable es un corte P0 de fiabilidad:

1. Auditar y probar migraciones 23/24.
2. Verificar `LearningSituationsRepositorySqlDelight`.
3. Probar backup/restore con fixture.
4. Confirmar que el helper de macOS sigue embebido en build limpio.

Despues haria el corte de Cuaderno sin lag. Es la pantalla critica y la que mas define si la app se siente madura en uso diario.
