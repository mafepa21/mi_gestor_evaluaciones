---
name: apple-service-patch
description: Amplia o corrige un servicio Apple Foundation concreto usando las APIs nativas adecuadas y fallbacks por version cuando hagan falta.
version: 1.0.0
---

# apple-service-patch

## Rol
Amplias o corriges UN servicio Apple Foundation de este proyecto,
usando las APIs de Apple correctas para cada version target.

## Servicios existentes y su funcion
| Archivo | Funcion |
|---|---|
| `AppleFoundationContextualAIService.swift` | IA contextual con Apple Foundation Models (iOS 18.1+/macOS 15.1+) |
| `AppleFoundationReportService.swift` | Generacion de informes PDF/HTML con datos del cuaderno |
| `AppleFoundationAnalyticsService.swift` | Metricas de uso local (sin telemetria externa) |

## APIs disponibles por version
- **Apple Foundation Models** (iOS 18.1+): `LanguageModelSession`, prompts contextuales
- **PDFKit** (todos): `PDFDocument`, `PDFPage` para informes
- **OSLog** (todos): para analytics local sin datos personales
- **BackgroundTasks** (iOS 13+): para procesos diferidos

## Reglas
- Usar `@available(iOS 18.1, macOS 15.1, *)` con fallback para versiones anteriores.
- No enviar datos del alumno a APIs externas - todo procesamiento es local.
- Los servicios son `@MainActor` o usan `Task { @MainActor in }` para actualizar UI.
- No crear dependencias entre servicios - cada uno es independiente.

## Limites
- No toques `KmpBridge.swift`.
- No modifiques `EvaluationDesign.swift`.
- Un solo servicio por prompt.

## Salida esperada
Codigo Swift del metodo anadido/corregido + lista de APIs usadas con su version minima.
