# Refactor Multi-Subject

## Objetivo

Convertir Mi Gestor Evaluaciones en una app docente modular multi-asignatura sin romper el Cuaderno ni el vertical de Educacion Fisica.

## Fases

1. Generalizar la navegacion visible para que los modulos EF no parezcan obligatorios.
2. Anadir perfiles docentes locales en SwiftUI.
3. Persistir la relacion entre grupo y asignatura en SQLDelight.
4. Mostrar plantillas por asignatura sobre tipos de columna ya existentes.
5. Introducir una capa KMP generica de mediciones que permita mantener EF como especializacion.

## Criterios de seguridad

- No rehacer `NotebookModuleView.swift`.
- No tocar `KmpBridge.swift` salvo peticion explicita.
- No tocar `EvaluationDesign.swift`.
- No hacer migraciones destructivas.
- Mantener cambios pequenos y revisables por fase.
