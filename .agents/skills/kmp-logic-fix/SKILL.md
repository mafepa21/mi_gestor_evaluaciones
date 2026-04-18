---
name: kmp-logic-fix
description: Corrige un fallo de logica de negocio dentro de kmp/shared respetando la arquitectura Clean y sin tocar la UI Swift.
version: 1.0.0
---

# kmp-logic-fix

## Rol
Corriges UN fallo de logica de negocio en el modulo Kotlin compartido,
respetando la arquitectura Clean y sin tocar la capa de UI Swift.

## Arquitectura KMP de este proyecto
```text
kmp/shared/
├── domain/
│   ├── Models.kt          <- Entidades puras (Student, Evaluation, Rubric, Grade...)
│   ├── usecase/           <- Logica de aplicacion (StudentImporter, BuildNotebookSheet...)
│   └── formula/           <- FormulaEvaluator.kt (motor de calculo - alta complejidad)
└── viewmodel/
    ├── NotebookViewModel.kt
    ├── StudentsManagerViewModel.kt
    ├── RubricsViewModel.kt
    └── RubricEvaluationViewModel.kt
```

## Reglas de modificacion
- Los `Models.kt` son contratos - cambiarlos rompe `KmpBridge.swift`. Solo tocar si es el fix pedido.
- Los ViewModels usan `StateFlow` - no cambiar a `SharedFlow` sin motivo.
- `FormulaEvaluator.kt` tiene logica matematica compleja - cambios minimos y con test.
- Respetar `loadNotebookSnapshot` como patron de carga explicita (no observacion reactiva multiple).

## Causas comunes en este proyecto
- Calculo de nota final incorrecto: revisar ponderacion en `RubricEvaluationViewModel`
- Import de alumnos fallido: revisar heuristica en `StudentImporter.kt`
- `lastInsertedId = 0`: SIEMPRE usar `db.transactionWithResult {}` (fix ya aplicado)
- `StateFlow` no emite: verificar que `loadNotebookSnapshot()` se llama tras mutacion

## Limites
- No toques `kmp/data/` (esquema SQLDelight) salvo que sea el fix pedido.
- No modifiques `KmpBridge.swift` - si el fix requiere cambio de modelo, coordina con `kmp-bridge-fix`.

## Salida esperada
Diff Kotlin del fix + una linea explicando la causa raiz.
