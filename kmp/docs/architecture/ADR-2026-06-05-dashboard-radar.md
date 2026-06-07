# ADR-2026-06-05: Radar docente proactivo en Dashboard Apple

## Estado

Aprobado

## Contexto

El Dashboard iOS/iPadOS y macOS ya muestra sesiones, pendientes, riesgo, sistema, evaluacion, EF y auditoria LOMLOE, pero el foco principal sigue siendo informativo. Para uso docente diario, la pantalla debe anticipar la prioridad operativa: que pasa ahora, por que importa y que accion concreta puede ejecutar el docente.

La app ya cuenta con evidencias y servicios Apple IA locales (`DailyBriefEvidenceBuilder`, `TeachingAssistantDraft` y fallback determinista), por lo que no es necesario crear una IA nueva ni mover logica de negocio a KMP en la primera entrega.

## Decision

Crear una capa Swift compartida en `AppleShared` para construir un Radar docente proactivo:

- Primero se calculan insights deterministas desde datos ya cargados del Dashboard, tendencias, sync y backup.
- Apple IA solo redacta o mejora el briefing cuando esta disponible y nunca inventa hechos.
- Si Apple IA no esta disponible o no hay datos suficientes, el Dashboard mantiene un briefing fallback generado por reglas.
- iOS/iPadOS y macOS comparten modelo, motor y tarjeta visual, pero cada plataforma conserva sus acciones reales y su layout nativo.
- No se toca `KmpBridge.swift`, KMP, SQLDelight, Compose Desktop ni `EvaluationDesign.swift` para esta primera version.

## Consecuencias

- El Dashboard pasa de portada informativa a radar operativo sin refactor global.
- La primera pantalla prioriza un maximo de tres senales visibles para reducir carga cognitiva.
- Las acciones se muestran solo si existe un flujo real en la plataforma actual.
- La logica puede migrarse a KMP mas adelante si Android o Compose Desktop necesitan compartir exactamente las mismas reglas.
- La evolucion avanzada de EF, media explicable y cobertura LOMLOE queda preparada como extension incremental del motor.
