# Evidencias: UI legible en Hoy y en las hojas del Cuaderno

Rama `codex/ui-legible`, 2026-10-30. Solo datos de prueba: la clase de ejemplo (más una rúbrica del catálogo de plantillas, creada en el simulador) que crea la app («3 ESO A», con Ana López y Pablo García). En Hoy, la clase de «Siguiente clase» y las tres filas de Atención son inventadas: las inyectó un parche temporal de capturas que **no está en la rama**.

Dispositivos: simulador iOS 27 (iPhone 17 Pro, iPad Air 11" M4) y la app de Mac con una carpeta de usuario temporal (sin la base real). «AX3» = tamaño de texto Accesibilidad XL.

## Las 6 mejoras HIG del Dashboard

| Mejora | Antes | Después | Nota |
|---|---|---|---|
| No atenuar el contenido con error de carga | `iphone-error-antes.png`, `iphone-atencion-error-antes.png` | `iphone-error-despues.png`, `iphone-atencion-error-despues.png` | Error forzado con el parche temporal. Antes, los iconos de Atención salían desaturados. |
| Cabecera compacta en iPhone | `iphone-hoy-antes.png` | `iphone-hoy-despues.png` | «Buenas tardes» pasa de `largeTitle` a `title2`. |
| Explicar el botón principal desactivado | `iphone-hoy-antes.png` | `iphone-hoy-despues.png` | El texto visible ya estaba en develop; se añade la pista de VoiceOver y la ayuda de Mac. La imagen apenas cambia. |
| Bordes visibles en iOS < 26 | `iphone-cristal-viejo-antes.png` | `iphone-cristal-viejo-despues.png` | Rama antigua forzada en iOS 27 (no hay simulador < 26). La píldora de sync pasa a borde opaco; la diferencia es pequeña. |
| Severidad visible en Atención | `iphone-atencion-error-antes.png` | `iphone-atencion-error-despues.png` | «Prioridad alta» con icono en línea propia; «Prioridad media» en la línea de tipo. |
| Trait del banner de error | — | — | Es un cambio para VoiceOver (`.isHeader`, `.isSummaryElement`): no se ve en una captura. |

## Tamaño normal y AX3

| Pantalla | Normal | AX3 |
|---|---|---|
| Hoy, iPhone | `iphone-hoy-despues.png` | `iphone-hoy-ax3-despues.png` (antes: `iphone-hoy-ax3-antes.png`) |
| Cuaderno, iPhone | — | `iphone-cuaderno-ax3.png` |
| Plano de clase, iPhone | `iphone-plano-normal.png` | `iphone-plano-ax3.png` |
| Ficha 360, iPhone | `iphone-ficha360-normal.png` | `iphone-ficha360-ax3.png` |
| Hoy, iPad | `ipad-hoy-despues.png` | `ipad-hoy-ax3-despues.png` (antes: `ipad-hoy-ax3-antes.png`) |
| Plano de clase, iPad | `ipad-plano-normal.png` | `ipad-plano-ax3.png` |
| Estadísticas de columna, iPad | `ipad-estadisticas-normal.png` | `ipad-estadisticas-ax3.png`, `ipad-estadisticas-tramos-ax3.png` |
| Inspector de alumno, iPad | — | `ipad-inspector-ax3.png` |
| Ficha 360, iPad | `ipad-ficha360-normal.png` | `ipad-ficha360-ax3.png` |
| Evaluación masiva de rúbricas, iPad | `ipad-rubricas-masiva-normal.png` | `ipad-rubricas-masiva-ax3.png` |
| Tarjetas del shell (Evaluación), iPad | `ipad-evaluacion-normal.png` | `ipad-evaluacion-ax3.png` |
| Menú lateral, iPad | — | `ipad-menu-lateral-ax3.png` |
| Hoy, Mac | `mac-hoy-despues.png` (antes: `mac-hoy-antes.png`) | No aplica: macOS no tiene Dynamic Type. |

## Lo que no se pudo capturar

- Resto de hojas del Cuaderno en iPhone (estadísticas, inspector, evaluación masiva): se dejó el iPhone a petición del usuario, que no usa la app en iPhone.
- Hojas del Cuaderno en Mac: la app de Mac aislada arranca en el Cuaderno, pero abrir una clase y sus hojas exige clics, y sin el permiso de Accesibilidad de macOS no se puede desde la terminal.
- Estados forzados (error, Atención inventada) en Mac: el Mac usa su propia vista de Hoy, sin el parche.
