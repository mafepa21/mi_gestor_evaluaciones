---
name: sqldelight-fix
description: Corrige problemas de persistencia en la capa SQLDelight respetando el esquema, las transacciones y los patrones ya establecidos.
version: 1.0.0
---

# sqldelight-fix

## Rol
Corriges UN problema de persistencia en la capa de datos SQLDelight,
respetando el esquema existente y los patrones de transaccion establecidos.

## Estructura de datos
```text
kmp/data/
├── SqlDelightRepositories.kt   <- Implementaciones de repositorio
├── DesktopDriver.kt            <- Driver JDBC macOS (usa IF NOT EXISTS)
└── *.sq                        <- Queries SQLDelight tipadas
```

## Reglas criticas de este proyecto
- **SIEMPRE** usar `db.transactionWithResult { }` cuando necesites `lastInsertedId`
  -> Bug conocido: sin transaccion, JDBC devuelve 0 y rompe relaciones (`rubricId = 0`)
- El esquema usa `IF NOT EXISTS` - es idempotente por diseno, no lo quites
- Las queries `.sq` deben ser nombradas con `camelCase` y sin logica condicional compleja
- `DesktopDriver` para macOS standalone, driver estandar SQLDelight para iOS/Android

## Causas comunes
- Relacion huerfana (criterios sin rubrica): falta `transactionWithResult`
- Query devuelve lista vacia: revisar `JOIN` vs `LEFT JOIN` segun nullabilidad
- Crash al migrar: falta `ALTER TABLE ... ADD COLUMN ... DEFAULT`
- ID duplicado: secuencia `AUTOINCREMENT` no reiniciada en tests

## Limites
- No cambies el esquema de tablas existentes salvo que sea el fix pedido.
- No toques `KmpBridge.swift` - si cambias un modelo de datos, coordina con `kmp-bridge-fix`.
- No alteres `DesktopDriver.kt` salvo fix de conexion JDBC explicito.

## Salida esperada
Query o transaccion corregida + descripcion del fallo en <=3 lineas.
