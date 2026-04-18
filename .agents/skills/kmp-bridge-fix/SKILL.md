---
name: kmp-bridge-fix
description: Corrige un fallo puntual de binding entre Swift y Kotlin en KmpBridge.swift con cambios minimos y seguros.
version: 1.0.0
---

# kmp-bridge-fix

## Rol
Eres el unico skill autorizado a tocar `KmpBridge.swift`.
Tu mision es corregir UN fallo de binding entre Swift y Kotlin, sin alterar
la arquitectura del puente ni los ViewModels KMP.

## Arquitectura del puente (no modificar estructura)
- `KmpBridge.swift` expone los ViewModels Kotlin como `@Published` observables Swift
- Los `StateFlow` de Kotlin se convierten con `collect` en coroutines -> `@MainActor`
- Los modelos Kotlin llegan como clases con prefijo `Shared` (ej: `SharedStudent`)
- Nulos Kotlin = opcionales Swift: tratar siempre con `guard let` o `??`

## Causas de fallo mas comunes
- `collect` de `StateFlow` no cancelado -> memory leak o estado obsoleto
- Modelo Kotlin actualizado en `kmp/shared/` pero wrapper Swift no sincronizado
- Thread incorrecto: llamada a UI desde background thread KMP
- `Kotlinx.coroutines` lanzando en `Dispatchers.Main` pero Swift esperando en otro actor

## Proceso
1. Identifica que `StateFlow` / ViewModel esta fallando.
2. Busca su wrapper `@Published` en `KmpBridge.swift`.
3. Verifica que el `collect` usa `@MainActor` y cancela con `Task`.
4. Corrige SOLO el binding afectado - no reorganices otros.

## Limites DUROS
- No anadir nuevos ViewModels al puente sin peticion explicita.
- No cambiar los modelos en `kmp/shared/domain/`.
- No modificar queries SQLDelight en `kmp/data/`.
- Cambio minimo posible - este archivo tiene 335 KB, un error rompe toda la app.

## Salida esperada
Lineas exactas a cambiar + explicacion del fallo de binding en <=4 lineas.
