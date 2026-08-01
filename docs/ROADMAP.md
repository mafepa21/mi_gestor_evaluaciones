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
  Pendiente: los quizzes no se autocorrigen. `QuizQuestionDraft` importa pregunta y opciones pero no la respuesta correcta, y `saveResponses` solo deriva nota para la rejilla de observacion 1-4 y la checklist proporcional. Faltan clave de respuestas, contrato de autoria en el DOCX, puntuacion por pregunta, versionado de la clave y derivacion local verificable. Detalle en `docs/importacion_documentos_sa.md`.
- Asistencia: flujo diario rapido y consistente.
- Alumnado: perfiles utiles, busqueda y datos relevantes.
  Avance: registro y seguimiento de medidas de respuesta educativa Nivel III/IV (Decreto 104/2018 + Orden 20/2019, CV) en la ficha de alumno de iOS/iPadOS y macOS, con badge en el Cuaderno y aviso determinista de revision anual, sin IA generativa ni contenido clinico persistido. Verificado con builds reales macOS e iOS Simulator (BUILD SUCCEEDED en ambos).
- Planificacion: sesiones, situaciones de aprendizaje y continuidad docente.
  Avance: Planificación inicia su rediseño iPad/macOS con cuatro secciones claras (Semana, Día, Secuencia, Resumen), tab bar flotante en iOS/iPadOS y macOS sin inspector lateral invasivo.
  Avance: Semana de Planificación en iOS/iPadOS usa miniatura semafórica de 200pt con detalle contextual por sesión, franja o día, reduciendo densidad visual sin tocar lógica KMP.
  Avance: Secuencia de Planificación adopta un Gantt horizontal por trimestre con situaciones, grupos colapsables y navegación directa a sesiones planificadas.
  Avance: Resumen de Planificación concentra métricas semanales, próximas sesiones, cobertura diaria y alertas en un dashboard operativo sin añadir lógica KMP.
  Avance: Planificación macOS reutiliza el toolbar y las vistas iPadOS para mantener una estética uniforme; sus botones flotantes usan `.glass`/`.glassProminent` y las pestañas se agrupan con `GlassEffectContainer`, selección transparente superpuesta y morphing `glassEffectID` en iOS/macOS 26, con fallback material.
  Avance: macOS incorpora "Diario de aula" como módulo de primer nivel en la barra lateral (paridad iPadOS reutilizando `DiaryWorkspaceView`), al que "Abrir ejecución" del Planner navega con el contexto de la sesión; el detalle de sesión se presenta como sheet propio de ancho completo en vez de un inspector genérico estrecho. La vista Día suma una etiqueta derivada "Confirmar impartida" para franjas ya pasadas (sin escribir estado en BD en automático) y un sheet de "Diario rápido" para cerrar el diario de todas las sesiones del día (impartida, pulso, participación y nota corta) con el mínimo de gestos.
  Avance: el Gantt macOS se convierte en superficie de seguimiento accionable: carga secuencias
  aún no agendadas, separa estados reales, identifica grupos retrasados y permite ubicar pendientes
  mediante el composer existente. Su carril fijo y línea temporal única quedan cubiertos por pruebas
  de proyección; se mantiene fuera de alcance la edición directa por drag & drop.
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
  Avance: Gestión de datos en Ajustes rediseñada con menús colapsables por áreas (Estructura Escolar, Cuaderno, Planificación e Instrumentos) y borrado granular en lote/swipe de Cursos, Asignaturas, Cuadernos por curso, Pestañas, Columnas, Sesiones planificadas del Planner, Situaciones de Aprendizaje y Rúbricas.


## Fase 3 - Datos, sync y seguridad

Prioridad: media-alta.

- SQLDelight: migraciones seguras y pruebas de repositorio.
- Curso escolar activo: `AcademicYear` pasa a ser frontera estructural de trabajo diario y `StudentEnrollment` conserva historico de matriculas sin duplicar alumnado.
- Multi-asignatura: relación real grupo-asignatura con catálogo visible y presets aplicables por materia; siguiente paso, usarla en filtros y onboarding.
- Backups: restauracion fiable y trazable.
- Sync: estrategia clara para LAN/local y futuras opciones.
  Avance: entregas del alumnado vía web multi-grupo. El Mac mantiene la autoridad de claves, alias, mapas y ledger; la bandeja lista todos los formularios, publica con revisión guiada y enruta lotes mixtos por `formInstanceId`. La previsualización separa válidos, asignaciones manuales, conflictos, inválidos y ya importados; la escritura pasa por `saveResponses` y las respuestas resultantes llegan al Cuaderno iPad mediante SyncLAN. Las tablas privadas `web_*` siguen fuera de SyncLAN. Diseño y decisión en `kmp/docs/architecture/ADR-2026-08-01-entregas-web-centro-mac.md`.
  Pendiente: transporte en la nube de archivos originales y QA manual extremo a extremo Mac → lote mixto → SyncLAN → Cuaderno iPad.
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
