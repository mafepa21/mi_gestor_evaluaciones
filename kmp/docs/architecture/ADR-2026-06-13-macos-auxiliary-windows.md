# ADR-2026-06-13: Ventanas auxiliares macOS

## Estado

Aprobado

## Contexto

La version macOS ya usa una ventana principal con `NavigationSplitView`, inspector contextual, comandos de menu y modulos especificos para Cuaderno, Informes, Backups y Sync LAN. Informes, Backups y Sync son flujos de escritorio que pueden necesitar permanecer abiertos mientras el docente trabaja en el Cuaderno.

## Decision

La app macOS mantiene una unica `MacAppSessionController` como owner de `KmpBridge`, `MacCommandCenterCoordinator` y `MacBackupStore`. Las ventanas auxiliares de Informes, Backups y Sync LAN se declaran como escenas `Window(id:)` y reutilizan esa misma sesion en lugar de crear bridges o servicios nuevos.

## Consecuencias

- La ventana principal puede seguir en Cuaderno mientras Informes, Backups o Sync LAN se usan en paralelo.
- El estado de backup y Command Center no se duplica entre ventanas.
- La navegacion embebida por sidebar sigue disponible como fallback.
- Las siguientes fases de macOS deben respetar este ownership antes de introducir stores Apple-only adicionales.
