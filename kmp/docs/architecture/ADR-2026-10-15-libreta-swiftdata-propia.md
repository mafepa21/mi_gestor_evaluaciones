# ADR-2026-10-15: La Libreta guarda sus datos en SwiftData, fuera de KMP

## Estado

Aprobado (ticket `docs/planes/ticket_libreta_integrada_2026-10-15.md`).

## Contexto

La app Cuadernos (libretas a mano con Apple Pencil) entra en Mi Gestor como módulo «Libreta». Cuadernos guarda sus datos con SwiftData: libretas, grupos, hojas con su dibujo de PencilKit e imágenes. Mi Gestor guarda todo lo demás en SQLDelight a través de KMP.

Los dibujos e imágenes son datos binarios grandes que solo usa iPad. Ningún otro módulo los lee, y ni el Mac ni el escritorio Compose pueden dibujarlos.

## Decisión

- La Libreta conserva SwiftData con su esquema tal cual (`Notebook`, `NotebookGroup`, `Page`, `PageElement`).
- Usa su propio archivo, `Libreta.store` (`ModelConfiguration("Libreta", …)`), sin iCloud.
- El contenedor se crea la primera vez que se entra en el módulo (`LibretaStore`), no al arrancar la app.
- Si no se puede abrir, se muestra un aviso con «Reintentar». No hay `fatalError` y no se borra nada.
- No pasa por `KmpBridge` ni por SQLDelight. No hay migración de esquema en `kmp/data`.
- La copia JSON propia de Cuadernos se mantiene, y se pueden importar las copias antiguas (`.cuaderno.json`).

## Consecuencias

- La Libreta solo existe en iPad. El target de Mac excluye `App/Libreta/**`.
- Las libretas no viajan por SyncLAN y no entran en las copias de Seguridad de Mi Gestor. Hasta la fase 2, su copia es la propia JSON del módulo.
- Ligar una libreta a un grupo de Mi Gestor (fase 2) exigirá guardar un identificador de grupo en SwiftData, sin relación real con SQLDelight.
- Si en el futuro se quisiera sincronizar o respaldar junto al resto, habrá que decidir entre exportar a la copia de Mi Gestor o pasar a iCloud (CloudKit). El esquema ya es compatible con CloudKit.
