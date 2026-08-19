# ADR-2026-08-19: detalle enriquecido de sesiones DOCX en Planificación

- Estado: aceptado
- Fecha: 2026-08-19
- Ámbito: targets Apple del Planificador

## Contexto

El detalle de una sesión importada desde DOCX debe servir como guía operativa durante la clase. QuickLook conserva una previsualización fiel del archivo original, pero obliga a salir del flujo del Planificador y no ofrece una lectura rápida integrada junto al resto de la ficha.

## Decisión

El detalle de sesión reconstruye localmente el bloque de la sesión desde el OOXML ya descargado:

- `ZIPFoundation` lee el contenedor DOCX y `XMLParser` interpreta `word/document.xml` y sus relaciones.
- El renderer compartido de Apple convierte títulos, párrafos, listas, formato básico, tablas e imágenes embebidas en HTML autocontenido.
- `WKWebView` muestra ese HTML tanto en iOS/iPadOS como en macOS, manteniendo el comportamiento de desplazamiento dentro de la ficha.
- La selección prioriza la etiqueta y el número de sesión importados; si el documento no tiene una cabecera canónica, se muestra el contenido disponible completo.
- QuickLook permanece disponible como respaldo para documentos con maquetación avanzada o para consultar el original exacto.

La mejora se mantiene en SwiftUI/AppleShared: no añade tablas, campos ni lógica nueva al dominio KMP y no modifica la persistencia del documento importado.

## Consecuencias

Positivas:

- El profesor puede recordar en Semana y Día la SA, la sesión, el objetivo y la actividad sin abrir el inspector completo.
- El detalle integra el material habitual de un DOCX —incluidas tablas e imágenes— sin depender de una conexión.
- iOS/iPadOS y macOS comparten el renderer y conservan el acceso al original.

Límites:

- No se pretende sustituir un motor completo de Word: elementos de maquetación avanzada, objetos flotantes, SmartArt, campos o contenido no soportado pueden requerir QuickLook.
- El HTML se muestra en una superficie desplazable acotada para no bloquear la navegación del inspector.

## Verificación

- Fixture DOCX sintético con tabla e imagen: `LearningSituationDocumentImportTests.testSessionDocxRendererKeepsTablesAndImagesInSessionOrder`.
- Suite `MiGestorPlannerTests`: 41 tests, 0 fallos.
- Builds macOS native e iOS Simulator: `scripts/verify_apple_builds.sh`, ambos `BUILD SUCCEEDED`.
