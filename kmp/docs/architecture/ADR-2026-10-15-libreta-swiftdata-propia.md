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
- Las libretas no viajan por SyncLAN.
- Si en el futuro se quisiera sincronizar o respaldar junto al resto, habrá que decidir entre exportar a la copia de Mi Gestor o pasar a iCloud (CloudKit). El esquema ya es compatible con CloudKit.

## Ampliación fase 2 (2026-10-15)

- **Clase:** `Notebook.linkedClassId: Int64?` guarda solo el número de la clase de Mi Gestor. El nombre se lee cada vez de `shellStore.classes`; si la clase ya no existe, la libreta se trata como «sin clase». No hay relación real con SQLDelight.
- **Ruta fija:** `LibretaStorage` (AppleShared) fija `Application Support/Libreta.store`, la misma ruta que SwiftData usaba por defecto. La comparten la Libreta y el servicio de copias.
- **Copias:** el paquete `.migestorbackup` del iPad lleva `libreta/Libreta.sqlite` (instantánea con la API de copia de SQLite) y `libreta/support/` (copia de `.Libreta_SUPPORT`, donde Core Data guarda los datos grandes). Todo entra en `checksums.json`. Restaurar solo instala la Libreta si `checksums.json` tiene `libreta/Libreta.sqlite`, y lo hace en la misma `AppleBackupRestoreTransaction`. Sin esa clave, la Libreta activa no se toca.
- **Compatibilidad:** `AppleBackupSummary.libretaCount` es opcional: las copias antiguas se siguen leyendo. El Mac (`isSupportedOnThisPlatform == false`) ni guarda ni restaura libretas.
- **Riesgo aceptado:** el nombre `.Libreta_SUPPORT` es interno de Core Data. Si cambiara, las copias perderían dibujos e imágenes grandes. Hay que comprobarlo en un iPad real.
