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
  Avance: Media explicable con desglose de columnas incluidas, pendientes, exclusiones y aportaciones ponderadas ya integrada en KMP y SwiftUI.
- Rubricas: evaluacion fiable, integracion con cuaderno e informes.
- Asistencia: flujo diario rapido y consistente.
- Alumnado: perfiles utiles, busqueda y datos relevantes.
- Planificacion: sesiones, situaciones de aprendizaje y continuidad docente.
- Dashboard: Radar docente proactivo para priorizar que pasa ahora, por que importa y que accion diaria ejecutar.

## Fase 2 - Apple premium

Prioridad: alta.

- iPad: shell de trabajo clara, inspector no invasivo y acciones principales visibles.
- macOS: paridad progresiva con convenciones desktop reales.
- Dashboard Apple: briefing local no bloqueante con fallback determinista y acciones reales por plataforma.
- Accesibilidad: contraste, foco, labels y navegacion por teclado donde aplique.
- UI/UX: reducir ruido visual, reforzar jerarquia y mantener rejilla disciplinada.

## Fase 3 - Datos, sync y seguridad

Prioridad: media-alta.

- SQLDelight: migraciones seguras y pruebas de repositorio.
- Multi-asignatura: relación real grupo-asignatura con catálogo visible y presets aplicables por materia; siguiente paso, usarla en filtros y onboarding.
- Backups: restauracion fiable y trazable.
- Sync: estrategia clara para LAN/local y futuras opciones.
- Exportaciones: informes utiles y reproducibles.
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
