---
name: apple-intelligence-service
description: Crea, modifica o depura los servicios de IA local basados en Apple Foundation Models - insights de alumnado, resúmenes de tutoría, informes, EarlyWarning, análisis de EF y el AppleAIOrchestrator con sus agentes internos Tutor/Evaluador/EF. Usar siempre que la tarea mencione IA, inteligencia educativa, Foundation Models, insights, resúmenes generados, señales preventivas, briefing del dashboard o "que la app analice/redacte/resuma algo", aunque no se nombre ningún servicio concreto.
version: 1.0.0
---

# apple-intelligence-service

## Por qué existe esta skill

La capa de IA de la app tiene un contrato de diseño muy estricto: todo es local (Foundation Models on-device), estructurado, trazable, con fallback determinista y sin lenguaje diagnóstico. Un cambio bienintencionado que devuelva texto libre, invente datos o presente una señal como diagnóstico rompe el producto y su posición legal/ética con datos de menores. Esta skill fija ese contrato.

## Mapa de servicios

Todos en `kmp/iosApp/App/`:

| Servicio | Responsabilidad |
|---|---|
| `AppleAIOrchestrator.swift` | Router tipado con catálogo de capacidades; agentes internos Tutor, Evaluador y EF. Sin interfaz de chat. |
| `AppleFoundationContextualAIService.swift` | Generación contextual (inspector del Cuaderno, drafts) |
| `AppleFoundationStudentInsightService.swift` | `StudentInsightDraft`, `EarlyWarning` |
| `AppleFoundationAnalyticsService.swift` | Análisis agregados (EF: `PhysicalProgressAnalysis`) |
| `AppleFoundationReportService.swift` | `StudentReportSummary` para informes nativos/PDF |
| `AppleAIPremiumSupport.swift` | Soporte premium/estado |
| `AppleAIReadinessFixtures.swift` | Fixtures DEBUG de readiness sin datos reales |

## Los 7 principios del contrato (no negociables)

1. **Estructurado, nunca texto libre como contrato.** Cada capacidad devuelve un modelo tipado (`StudentInsightDraft`, `AverageExplanationDraft`, `TutorMeetingSummaryDraft`, `StudentReportSummary`, `PhysicalProgressAnalysis`, `EarlyWarning`). El texto libre solo puede ser un campo dentro de un modelo, jamás el contrato entero. `AIReportDraft` sobrevive solo como envoltorio de compatibilidad.
2. **Fallback determinista siempre.** Foundation Models puede no estar disponible (hardware, OS, ajustes). Cada capacidad tiene una rama determinista basada en reglas sobre la misma evidencia que produce un resultado útil, no un error. El briefing del Dashboard tiene contrato estable: 3 alertas, 2 acciones, resumen evaluativo y aviso de datos incompletos — el fallback también lo cumple.
3. **La IA lee evidencia, no recalcula.** Los servicios consumen datos ya calculados por KMP (media, snapshots de pruebas físicas, celdas persistidas). Si un servicio necesita re-derivar una métrica que KMP ya calcula, es un bug de arquitectura: pedir el dato al bridge, no recomputarlo.
4. **Señal preventiva, no diagnóstico.** `EarlyWarning` se presenta con severidad, causas, evidencia, recomendación y confianza *cualitativa y revisable*, con procedencia visible. Prohibido lenguaje clínico o determinista ("el alumno tiene...", "diagnóstico"). Siempre revisable por el docente.
5. **Trazabilidad visible.** Todo resultado de IA en UI lleva `AppleAIStatusBadge` (u origen equivalente) indicando si vino de Foundation Models o del fallback de reglas. El docente siempre sabe qué está leyendo.
6. **Sin datos reales en fixtures.** Los fixtures y previews DEBUG usan `AppleAIReadinessFixtures.swift`; nunca nombres, notas ni evidencias reales de alumnado.
7. **No bloquear la UI.** La generación es asíncrona y no bloqueante; la vista muestra estado útil mientras tanto y el resultado llega cuando llega.

## Cómo añadir una capacidad nueva

1. Definir primero el modelo estructurado de salida (campos, no prosa).
2. Registrarla en el catálogo tipado del `AppleAIOrchestrator` bajo el agente que corresponda (Tutor / Evaluador / EF) para que sea descubrible y trazable; no crear rutas paralelas al orchestrator.
3. Implementar las dos ramas: Foundation Models y fallback determinista, ambas devolviendo el mismo modelo.
4. Añadir la superficie UI con badge de trazabilidad y framing revisable.
5. Fixture DEBUG de readiness.
6. Verificar con `./scripts/verify_apple_builds.sh`. La lógica de reglas del fallback que sea pura y compartible puede merecer vivir en KMP — si es el caso, escalar a `kmp-feature-vertical`.

## Depuración habitual

- "No genera nada": revisar readiness/disponibilidad del modelo y que el fallback esté cableado — la ausencia de Foundation Models nunca debe dejar la tarjeta vacía.
- "Genera pero no se ve": el draft estructurado puede estar fallando el mapeo a la vista; revisar el modelo campo a campo antes de tocar el servicio.
- "Resultado incoherente con el Cuaderno": el servicio está recibiendo evidencia desactualizada o recalculando por su cuenta (principio 3).

## Límites

- No introducir llamadas de red ni servicios cloud: todo on-device.
- No añadir interfaz de chat: los agentes son internos y tipados.
- No presentar salida de IA sin badge de origen ni sin posibilidad de revisión docente.

## Salida esperada

Capacidad tratada, modelo estructurado de salida, estado de ambas ramas (FM + fallback), superficie UI con trazabilidad, y confirmación de que no se recalcula nada que KMP ya provea.
