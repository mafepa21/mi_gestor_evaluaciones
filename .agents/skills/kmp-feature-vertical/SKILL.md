---
name: kmp-feature-vertical
description: Implementa una funcionalidad completa de extremo a extremo atravesando todas las capas del stack - tabla SQLDelight, repositorio, contrato KMP, ViewModel, KmpBridge y SwiftUI. Usar siempre que el usuario pida una feature nueva que necesite persistencia o lógica compartida nueva, aunque no mencione las capas explícitamente ("quiero poder guardar X", "añade un historial de Y", "la app debería recordar Z"). No usar para bugs de una sola capa - para eso están sqldelight-fix, kmp-logic-fix, kmp-bridge-fix y swiftui-bugfix.
version: 1.0.0
---

# kmp-feature-vertical

## Por qué existe esta skill

Las skills por capa (`sqldelight-fix`, `kmp-logic-fix`, `kmp-bridge-fix`, `swiftui-*`) asumen que el problema vive en un solo sitio. Una feature vertical atraviesa 5-6 capas y los bugs más graves del proyecto han nacido justo en las costuras entre capas, no dentro de ellas. Esta skill codifica el camino completo y las lecciones ya pagadas para que no se repitan.

Esta skill SÍ está autorizada a tocar archivos protegidos (`KmpBridge.swift`, `kmp/shared/`, `kmp/data/`) porque una feature vertical lo exige por definición. A cambio, cada capa se toca con el cambio mínimo y siguiendo los patrones existentes de esa capa.

## El camino vertical (en este orden)

Trabajar de datos hacia UI. Cada capa debe compilar y tener sentido antes de subir a la siguiente:

1. **Esquema** — `kmp/data/src/commonMain/sqldelight/*.sq`
2. **Repositorio** — `kmp/data/.../SqlDelightRepositories.kt`
3. **Contrato** — interfaz del repositorio en `kmp/shared/` (`Contracts.kt`)
4. **Dominio/ViewModel** — modelos y casos de uso en `kmp/shared/`
5. **Puente** — `kmp/iosApp/App/KmpBridge.swift`
6. **UI** — vista SwiftUI en `kmp/iosApp/App/` (y `MacApp/` si hay divergencia macOS)

### Capa 1 — Esquema SQLDelight

- El esquema es idempotente por diseño: usar `IF NOT EXISTS`, no quitarlo nunca.
- Columnas nuevas sobre tablas existentes: `ALTER TABLE ... ADD COLUMN ... DEFAULT ...` para no romper datos ya persistidos en dispositivos reales de docentes.
- Queries `.sq` en `camelCase`, sin lógica condicional compleja embebida.
- Si la query nueva filtra o hace JOIN por columnas nuevas, añadir índice.
- Si la feature toca migraciones o evolución de esquema con riesgo, leer también `sqldelight-migration` antes de escribir el `.sq`.

### Capa 2 — Repositorio

- **Lección pagada (bug `rubricId = 0`)**: cualquier inserción que necesite `lastInsertedId` DEBE ir dentro de `db.transactionWithResult { }`. Sin transacción, el driver JDBC devuelve 0 y crea relaciones huérfanas silenciosas.
- Seguir los patrones ya presentes en `SqlDelightRepositories.kt`; no inventar un estilo de repositorio nuevo.

### Capa 3 — Contrato en `kmp/shared`

- **Lección pagada (crash SIGABRT en SyncLAN, 2026-06-28)**: todo método `suspend` de repositorio expuesto a Swift DEBE anotarse con `@Throws(Exception::class)` en la interfaz de `Contracts.kt`. Sin la anotación, una excepción Kotlin no se traduce a `NSError` y mata la app iOS/macOS con `runCompletionFailure` en runtime, sin stack útil.
- Revisar los métodos vecinos de la misma interfaz: si añades uno nuevo, comprueba que los existentes también llevan la anotación (el crash de AcademicYears vino de métodos antiguos sin anotar).

### Capa 4 — Dominio y ViewModel

- La lógica de negocio vive aquí, no en la View ni en el bridge. Si te encuentras calculando medias, progreso o agregados en Swift, párate: probablemente pertenece a KMP.
- Modelos nuevos: revisar si el dato cruza a Swift; los nulos Kotlin llegan como opcionales Swift.

### Capa 5 — KmpBridge

- `KmpBridge.swift` tiene ~335 KB; un error aquí rompe toda la app. Cambio quirúrgico: añadir la función/wrapper nuevo junto a los de su misma área funcional, sin reorganizar nada.
- Patrón del proyecto: los `StateFlow` de Kotlin se recogen con `collect` bajo `@MainActor` y se cancelan con `Task`. Los modelos llegan con prefijo `Shared` (ej. `SharedStudent`).
- Ejemplo real de referencia: el enriquecimiento de Secuencia añadió `learningSituationSessionPlans(sequenceVersionId:)` y `plannerListAllSessions()` como funciones puntuales de consulta, sin tocar ViewModels existentes del puente.
- Nulos: siempre `guard let` o `??` al cruzar la frontera.

### Capa 6 — SwiftUI

- Aplicar los criterios de `swiftui-native-feature` y `jobs-design-philosophy`: una pantalla, una tarea principal, rejilla 8pt, colores solo desde `EvaluationDesign.swift`.
- Si la vista debe funcionar en iPad y macOS, usar el patrón de `adaptive-layout-apple` (dos zonas con `ViewThatFits` + fallback compacto) en lugar de frames fijos.
- Antes de crear un helper de compatibilidad nuevo, mirar si ya existe en `kmp/iosApp/AppleShared/AppleViewCompatibility.swift` (`appFullScreenCover`, `appSearchable`, `appOnChange`, ...).

## Verificación por capas

Ejecutar lo que aplique según lo tocado, en este orden:

```bash
./gradlew :shared:test          # si se tocó kmp/shared
./gradlew :data:desktopTest     # si se tocó kmp/data o .sq
./scripts/verify_apple_builds.sh  # siempre que haya Swift nuevo o modificado
```

Si se creó un archivo `.swift` nuevo, el script ya ejecuta `xcodegen generate`; no darlo por compilado sin correrlo. Si el entorno no tiene Xcode completo, registrar el motivo exacto y dejar la compilación como pendiente explícito (patrón ya usado en `memoria`).

## Alcance y commits

- Una feature vertical se agrupa en commits por capa/intención: `data:` para `.sq` y repositorios, `kmp:` para shared, `feat:`/`ui:` para bridge y SwiftUI. No mezclar capas en un commit salvo dependencia real de compilación.
- No aprovechar el viaje para refactorizar capas vecinas.
- Cerrar siempre con `registrar-avance-app`: changelog, roadmap si cierra fase, ADR si la decisión condiciona arquitectura o persistencia.

## Salida esperada

1. Resumen de la feature y del camino de datos (tabla → UI).
2. Archivos tocados por capa.
3. Anotaciones `@Throws` y transacciones verificadas (decirlo explícitamente).
4. Comprobaciones ejecutadas y no ejecutadas con motivo.
5. Riesgos de migración o compatibilidad con datos existentes.
