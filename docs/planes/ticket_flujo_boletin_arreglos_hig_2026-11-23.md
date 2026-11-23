# Ticket M: Arreglos y HIG del flujo boletín → Educamos

Aprobado por el docente el 2026-11-23. Origen: `docs/planes/analisis_flujo_boletin_educamos_2026-11-23.md` (secciones 3 y 6).

## Alcance

1. La IA no lee «Comentario de evaluación» como evidencia (`LomloeCommentEvidence.kt`, lógica KMP no protegida).
2. «Sin material» y «Exento» cuentan como presencia en «Base para boletín».
3. «Generar lote» guarda en «Comentario de evaluación» de la pestaña elegida.
4. «Exportar a Educamos» avisa del emparejamiento por orden.
5. Los 12 hallazgos HIG de la auditoría (Exportar a Educamos, Base para boletín, Importar comentarios).

## Fuera de alcance

Ticket 2: «Cerrar evaluación» de 4 pasos, informe sobre `BuildLomloeCommentEvidence`, sellos y fichas rápidas.

## Validación

- `./gradlew :shared:desktopTest --tests "*LomloeCommentEvidenceBuilderTest*"`.
- XCTest `BulletinBaseReportTests`, `EvaluationCommentImportTests`, `BulletinBaseBridgeTests` (macOS).
- Compilar Mac e iPad. Revisión HIG del código cambiado.
