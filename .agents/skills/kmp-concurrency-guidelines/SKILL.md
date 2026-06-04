---
name: kmp-concurrency-guidelines
description: Guía y playbook de concurrencia y seguridad de hilos (main-safety) en la interoperabilidad Swift-KMP y SQLDelight para iOS y macOS.
version: 1.0.0
---

# kmp-concurrency-guidelines

## Rol
Eres el especialista en concurrencia y flujo de hilos para la interoperabilidad Kotlin Multiplatform (KMP) y Swift. Tu objetivo es prevenir crashes en tiempo de ejecución (como `NSGenericException`) y congelamientos de la interfaz de usuario en iOS y macOS.

## El problema de fondo
1. **Kotlin/Native Thread Constraints**: En iOS, llamar a una función declarada como `suspend` en Kotlin desde Swift/Objective-C requiere, por defecto, que la invocación ocurra en el hilo principal (`Main Thread` / `@MainActor`). Hacerlo en un hilo secundario arbitrario de Swift (por ejemplo, dentro de un `Task.detached`) suele lanzar:
   `*** Terminating app due to uncaught exception 'NSGenericException', reason: 'Calling Kotlin suspend functions from Swift/Objective-C is currently supported only on main thread'`
2. **UI Freezes**: Si llamamos a operaciones síncronas pesadas de la base de datos local SQLite (SQLDelight) directamente en el hilo principal en Swift, bloqueamos la UI.

## Solución arquitectónica unificada
Para mantener la app rápida, segura y libre de crashes:

### 1. En el lado de Kotlin (Main-Safety en data/repositorios)
Todos los accesos y consultas pesadas a la base de datos SQLDelight dentro de `kmp/data` o `kmp/shared` deben ser main-safe. Esto significa envolver las operaciones síncronas/bloqueantes en bloques `withContext(Dispatchers.Default)` antes de retornar:
```kotlin
// Ejemplo en Kotlin (SqlDelightRepositories.kt)
suspend fun getStudents(): List<Student> = withContext(Dispatchers.Default) {
    // La consulta pesada a SQLite se ejecuta en hilos secundarios en segundo plano
    queries.selectAllStudents().executeAsList()
}
```

### 2. En el lado de Swift (Invocación y actualización de estado)
- Invoca las suspend functions de KMP desde el **MainActor** o Main Thread de Swift para evitar la `NSGenericException`.
- Dado que el repositorio de Kotlin ya se encarga de saltar a hilos secundarios con `withContext(Dispatchers.Default)`, Swift puede llamar de manera asíncrona segura desde el hilo principal sin bloquear la interfaz.
- Si necesitas realizar procesamiento Swift costoso o deseas despachar tareas que no invoquen suspend functions de KMP de forma síncrona en el hilo principal, puedes usar `Task.detached(priority: .utility)` o `Task.detached(priority: .background)`.

### Flujograma de decisión: ¿Dónde ejecutar?
```
¿La función que vas a llamar de KMP es 'suspend'?
 ├── SÍ ── ¿La llamas desde Swift?
 │          ├── SÍ ── Ejecútala en @MainActor / Task ordinario (hilo principal).
 │          │         Asegúrate de que en Kotlin el repositorio use withContext(Dispatchers.Default).
 │          └── NO ── (Es lógica interna de Kotlin) Usa coroutines ordinarias.
 └── NO  ── ¿Realiza accesos síncronos pesados a SQLDelight?
            ├── SÍ ── En Swift, envuélvela en Task.detached(priority: .utility) para no congelar la UI.
            └── NO ── Llama directamente en el hilo principal.
```

## Casos de depuración típicos
- **Crash `NSGenericException`**: Buscas llamadas asíncronas a KMP envueltas en `Task.detached` o ejecutadas dentro de hilos en background de Swift. Reviértelas a `@MainActor` o `Task` ordinarios y verifica que la seguridad de hilo (main-safety) esté bien implementada en Kotlin usando `withContext(Dispatchers.Default)`.
- **UI Freeze al sincronizar o refrescar**: Indica que el hilo principal está esperando bloqueado en un query de SQLite. Asegúrate de que los métodos en `KmpBridge.swift` o los métodos de Kotlin estén derivando el trabajo a `Dispatchers.Default` en Kotlin o mediante `Task.detached` en Swift si son llamadas síncronas legacy.

## Límites
- Respeta la regla de oro de no modificar `kmp/shared/` o `kmp/data/` a menos que sea explícitamente necesario para garantizar la seguridad de hilos ante un crash o un freeze real.
