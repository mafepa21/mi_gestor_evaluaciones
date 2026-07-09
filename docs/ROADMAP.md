# Roadmap

Este roadmap es un documento vivo. Su objetivo es ordenar el trabajo por valor y riesgo, no prometer fechas cerradas.

## Norte del producto

Mi Gestor Evaluaciones debe ser una app docente fiable para uso diario, con una experiencia Apple premium en iOS/iPadOS/macOS y una arquitectura KMP estable para reglas de negocio, datos y evoluciones futuras.

## Fase 0 - Orden y trazabilidad

Estado: casi cerrada.

- Crear gobierno documental del repo.
- Mantener changelog desde el estado actual.
- Usar PRs pequenos con plantilla.
- Separar documentacion canonica de auditorias temporales.
- Agrupar el trabajo historico pendiente en paquetes revisables.
- Mantener CI minimo para KMP/data y builds Apple antes de avanzar hacia releases.
- Mantener `docs/VERSIONING.md` y `release-check.yml` como base del registro automatico de ramas, commits, PRs y releases.

## Fase 1 - Estabilizacion funcional critica

Prioridad: alta.

- Cuaderno: carga rapida, grid estable, columnas ocultas seguras, medias explicables y categorias claras.
  Avance: el grid SwiftUI reduce coste de scroll y actualizacion con filas lazy, fingerprints precomputados por panel y celdas desacopladas del bridge global mediante snapshots/actions.
  Avance: Media explicable con desglose de columnas incluidas, pendientes, exclusiones y aportaciones ponderadas ya integrada en KMP y SwiftUI.
  Avance: pruebas físicas separan dato bruto (`Marca`/`Nivel`) y nota baremada (`Nota`) para evitar contaminar la Media.
  Avance: inspector convertido en ficha rápida del alumno con Media, pendientes, observaciones, rúbricas y acciones.
  Avance: inspector incorpora Inteligencia Educativa local estructurada para resumir fortalezas, riesgos, recomendaciones y lectura docente de la media sin recalcular los datos KMP.
- Rubricas: evaluacion fiable, integracion con cuaderno e informes.
- Asistencia: flujo diario rapido y consistente.
- Alumnado: perfiles utiles, busqueda y datos relevantes.
- Planificacion: sesiones, situaciones de aprendizaje y continuidad docente.
  Avance: El importador de instrumentos de situaciones de aprendizaje se ha mejorado para soportar extracción de anotaciones, ítems de checklist inline y un nuevo tipo de instrumento `quizQuestions` para pruebas tipo test, previsualizando el detalle estructurado de cada uno antes de crear las columnas en el cuaderno.
  Avance: Se implementó un visualizador y evaluador interactivo premium para instrumentos estructurados en el Cuaderno, mostrando un banner con anotaciones de contexto, cuestionarios de opción múltiple como tarjetas táctiles interactivas y rejillas de observación con escala 1-4 en colores semafóricos.
  Avance: Se completó la resolución automática de fórmulas de calificación final de la SA, enlazando dinámicamente las columnas de los instrumentos mediante un parseador de términos y pesos ponderados para crear la columna `.calculated` asociada en el Cuaderno.
  Avance: Corregida la detección de encabezados del importador DOCX, que confundía párrafos narrativos con nuevos instrumentos en documentos reales; verificado contra el documento de prueba SA 1 - Building Health (4 instrumentos + fórmula final se reconstruyen correctamente).
  Pendiente: no existe cálculo automático de nota 0-10 a partir de respuestas de instrumentos estructurados (rejilla 1-4, quiz) — el motor de medias (`GetNotebookUseCase.computeFinalAverage`, kmp/shared) lee `cell.value` en crudo sin reescalar por `scaleKind`, y el quiz no tiene clave de respuestas correctas en el DOCX. Requiere decisión de producto sobre la convención de reescalado antes de implementarse.
  Avance: La rejilla de observación graduable 1-4 pasa de una celda numérica única a un formulario estructurado por alumno con sus momentos (S3/S7/S9) e indicadores reales de la tabla del DOCX; calcula media por momento y media final en escala 1-4 cruda al guardar, a la espera del reescalado 0-10 del motor de medias (pendiente anterior).
  Avance: Reimportar un instrumento DOCX ya vinculado a una situación de aprendizaje ahora refresca su columna (tipo/entrada/escala/pestaña) y su plantilla estructurada en el sitio en vez de no hacer nada, permitiendo que un profesor recoja mejoras del parser o mueva instrumentos ya creados a otra pestaña sin duplicar evaluaciones/columnas.
  Avance: Corregida una corrupción de datos por sincronización LAN que sobrescribía la descripción de evaluaciones/pestañas con un volcado recursivo del objeto Kotlin (bug de `.description` vs `.description_`); se añade salvaguarda receptora y reparación única de datos ya corrompidos.
  Avance: El refresco de instrumentos ya vinculados deja de regenerar plantillas estructuradas que ya existen (evita orfanar respuestas de alumnado) y deja de sobrescribir con `nil` el `rubricId` de columnas de rúbrica ya materializadas cuando el lookup de enlace falla.
  Pendiente: `saveTemplate` (kmp/data) sigue borrando y reinsertando ítems en cada regeneración; hoy es seguro porque las foreign keys están desactivadas en el driver Apple, pero conviene convertirlo en un diff no destructivo antes de activar `foreignKeyConstraints`. Los enlaces de instrumento a situación (`learning_situation_links`) tampoco se deduplican nunca (siempre insertan). Ver tarea de seguimiento.
  Avance: Planificación inicia su rediseño iPad/macOS con cuatro secciones claras (Semana, Día, Secuencia, Resumen), tab bar flotante en iOS/iPadOS and macOS sin inspector lateral invasivo.
  Avance: Semana de Planificación en iOS/iPadOS usa miniatura semafórica de 200pt con detalle contextual por sesión, franja o día, reduciendo densidad visual sin tocar lógica KMP.
  Avance: Secuencia de Planificación adopta un Gantt horizontal por trimestre con situaciones, grupos colapsables y navegación directa a sesiones planificadas.
  Avance: Resumen de Planificación concentra métricas semanales, próximas sesiones, cobertura diaria y alertas en un dashboard operativo sin añadir lógica KMP.
  Avance: Planificación macOS reutiliza el toolbar y las vistas iPadOS para mantener una estética uniforme; sus botones flotantes usan `.glass`/`.glassProminent` y las pestañas se agrupan con `GlassEffectContainer`, selección transparente superpuesta y morphing `glassEffectID` en iOS/macOS 26, con fallback material.
- Dashboard: Radar docente proactivo para priorizar que pasa ahora, por que importa y que accion diaria ejecutar.
  Avance: las recargas por filtros del Dashboard se cancelan y debouncean para evitar tareas solapadas durante cambios rápidos de contexto.
  Avance: Dashboard macOS "Hoy" prioriza la clase actual o próxima, pendiente principal y acción recomendada antes que los paneles secundarios.
  Avance: Dashboard iOS/iPadOS y macOS fusionan Radar y cockpit diario en una unica entrada "Hoy"; se retira Radar del menu visible y el flujo queda centrado en acciones, sesiones, pendientes, riesgo y agenda.
  Avance: el estado sin horario de "Hoy" en macOS muestra una explicación breve y accesos directos de trabajo diario para que la pantalla no parezca vacía.

## Fase 2 - Apple premium

Prioridad: alta.

- iPad: shell de trabajo clara, inspector no invasivo y acciones principales visibles.
  Avance: `Cursos` queda como acceso visible de primer nivel en iOS/iPadOS para gestionar curso escolar activo, grupos e historico.
- macOS: paridad progresiva con convenciones desktop reales.
  Avance: la barra lateral de macOS se organiza en secciones agrupadas (Hoy, Evaluación, Planificación, Sistema) para una experiencia de escritorio real.
  Avance: `Cursos` aparece en la barra lateral macOS y abre la misma gestion de curso escolar activo que iOS/iPadOS.
  Avance: Informes, Backups y Sync LAN pueden abrirse como ventanas auxiliares nativas para trabajar en paralelo con el Cuaderno.
  Avance: la toolbar del Cuaderno macOS queda centrada en acciones diarias y `⌘F` enfoca la búsqueda sin cambiar de módulo inesperadamente.
  Avance: el Cuaderno macOS usa una sola toolbar propiedad de la shell, evitando acciones duplicadas entre `MacRootView` y `NotebookModuleView`.
  Avance: las pestañas del Cuaderno vuelven a ser visibles y creables en macOS sin reintroducir botones duplicados en la toolbar.
  Avance: la capa Liquid Glass macOS se concentra en shell, banners, inspectores, componentes premium y Dashboard, sin aplicar translucencia al grid del Cuaderno.
- Dashboard Apple: briefing local no bloqueante con fallback determinista y acciones reales por plataforma.
  Avance: el briefing diario usa contrato estable de 3 alertas, 2 acciones, resumen evaluativo y aviso de datos incompletos.
- Educación Física: análisis local de progreso físico por grupo.
  Avance: `PhysicalProgressAnalysis` empieza a leer snapshots de pruebas físicas para resumir estado, fortalezas, debilidades, recomendaciones y alertas desde la pestaña Informes.
- IA preventiva: señal local no diagnóstica desde evidencias del Cuaderno.
  Avance: `EarlyWarning` se muestra dentro del inspector del alumno con severidad, causas, recomendación y confianza revisable.
  Avance: el inspector presenta `EarlyWarning` como señal preventiva revisable y no como diagnóstico, con confianza cualitativa y procedencia visible.
- Agentes educativos internos: agrupar capacidades de Tutor, Evaluador y EF sin interfaz de chat.
  Avance: `AppleAIOrchestrator` completa el router tipado con catálogo de capacidades, trazabilidad y consumo desde Cuaderno/EF sobre servicios estructurados ya implementados.
- Accesibilidad: contraste, foco, labels y navegacion por teclado donde aplique.
- UI/UX: reducir ruido visual, reforzar jerarquia y mantener rejilla disciplinada.

## Fase 3 - Datos, sync y seguridad

Prioridad: media-alta.

- SQLDelight: migraciones seguras y pruebas de repositorio.
- Curso escolar activo: `AcademicYear` pasa a ser frontera estructural de trabajo diario y `StudentEnrollment` conserva historico de matriculas sin duplicar alumnado.
- Multi-asignatura: relación real grupo-asignatura con catálogo visible y presets aplicables por materia; siguiente paso, usarla en filtros y onboarding.
- Backups: restauracion fiable y trazable.
- Sync: estrategia clara para LAN/local y futuras opciones.
- Exportaciones: informes utiles y reproducibles.
  Avance: Informes Apple IA dispone de `StudentReportSummary` estructurado como base para renderizar informes nativos y PDFs sin depender de texto libre como contrato principal.
- Privacidad: mantener `PRIVACY.md` y `docs/04_legal_comercial/datos_personales.md` como base operativa pendiente de revision juridica.

## Fase 4 - Preparacion comercial

Prioridad: futura, con base documental inicial creada.

- Onboarding y datos de ejemplo.
- Posicionamiento multi-asignatura: core docente como producto principal y EF como vertical opcional.
- Guia de uso para docentes.
- Release notes publicables.
- Evidencias de calidad: builds, tests, capturas, auditorias.
- Documentacion de arquitectura y mantenimiento para terceros.
- Checklist legal y privacidad antes de distribucion o venta en `docs/04_legal_comercial/due_diligence.md`.

## Backlog de documentacion pendiente

- Mantener la matriz de modulos viva cuando cambie el estado, fuente de verdad, riesgos, pruebas o proxima accion.
- Consolidar guia de release interna con evidencias reales de CI verde.
- Probar la primera candidata `v0.3.0-alpha.1` con PR de release, tag anotado y GitHub Release.
- Crear guia de arquitectura KMP + Apple actualizada.
- Completar due diligence con revision legal, licencias transitivas y evidencias de release.
- Revisar si la app Flutter original queda como legado, referencia o target activo.
- Convertir el borrador de privacidad y datos personales en documentos publicables revisados.
- Revisar limpieza de ramas remotas historicas cuando no haya PRs abiertos dependientes.
- Migrar PhysicalTests de forma gradual hacia mediciones genéricas después del piloto `READING_FLUENCY`, sin tocar tablas físicas hasta necesitar persistencia compartida.
