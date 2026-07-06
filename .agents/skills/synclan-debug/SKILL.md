---
name: synclan-debug
description: Diagnostica y corrige problemas de SyncLAN - la sincronización local entre el Mac (helper Command Center) y los iPads enlazados via SSE con fallback de polling. Usar siempre que la tarea mencione sync, sincronización LAN, emparejamiento de dispositivos, el helper de macOS, cambios que no llegan al iPad, SSE, o crashes/cuelgues durante una sincronización, aunque el usuario solo diga "los datos no se actualizan en el otro dispositivo".
version: 1.0.0
---

# synclan-debug

## Por qué existe esta skill

SyncLAN cruza cuatro fronteras a la vez (SwiftUI → KmpBridge → repositorios KMP → helper HTTP → otro dispositivo), así que sus síntomas aparecen lejos de sus causas. Ya hubo un crash SIGABRT en producción cuya causa era una anotación ausente en Kotlin. Esta skill recoge la topología y las causas conocidas para no rediagnosticarlas desde cero.

## Topología

```
Mac (app + helper)                        iPad(s) enlazados
┌─────────────────────────────┐           ┌──────────────┐
│ KmpBridge                   │           │ App iPad     │
│  └─ mutación local          │           │  └─ SSE      │◄─── eventos
│  └─ debounce corto agrupa   │           │  └─ polling  │◄─── fallback
│  └─ POST /sync/local-changes│──────────►│              │
│       (solo loopback)       │  helper   └──────────────┘
│ kmp/commandCenterHelper     │  emite SSE
└─────────────────────────────┘
```

- El helper vive en `kmp/commandCenterHelper/` (proceso macOS propio, con su ciclo de vida).
- `KmpBridge.swift` agrupa mutaciones locales con **debounce corto** y notifica al helper con `POST /sync/local-changes` (buscar `sync/local-changes` en `KmpBridge.swift`, zona ~10990). El helper **solo acepta ese POST desde loopback** — es una decisión de seguridad, no un bug.
- El helper emite SSE a los iPads enlazados; el polling existe solo como fallback, no como mecanismo principal.
- Emparejamiento y diagnóstico tienen UI propia (workspace Sync LAN, layout de dos zonas: emparejamiento | actividad/diagnóstico).

## Causas conocidas (revisar en este orden)

1. **Crash SIGABRT `runCompletionFailure` durante sync** → método `suspend` de repositorio sin `@Throws(Exception::class)` en `Contracts.kt` (`kmp/shared`). Caso real: `AcademicYearsRepository.upsertAcademicYear`/`deleteArchivedAcademicYear`. La excepción Kotlin no se traduce a `NSError` y aborta el runtime. Ante cualquier crash en sync, auditar las anotaciones del repositorio implicado ANTES de buscar en Swift.
2. **Los cambios tardan en llegar** → distinguir si el iPad está recibiendo por SSE o cayó a polling. Si es polling: el helper no recibió el POST local (¿helper vivo?, ¿URL loopback correcta?) o la conexión SSE se cerró.
3. **Cambios agrupados que no se emiten** → el debounce del bridge agrupa mutaciones; verificar que la mutación en cuestión pasa por el camino que dispara la notificación local y no por una ruta de escritura que lo omita.
4. **Helper zombi o duplicado** → hay historial de trabajo sobre el ciclo de vida del helper (rama `codex/fix-synclan-helper-lifecycle`); si el síntoma es "funciona tras reiniciar el Mac", sospechar del lifecycle antes que del protocolo.
5. **Rechazo del POST** → solo se acepta desde 127.0.0.1; si alguien parametrizó el host, el helper responderá como si no llegara nada.

## Cómo trabajar aquí

1. Reproducir y localizar la frontera donde se pierde el dato: ¿la mutación local persiste? ¿el POST sale? ¿el SSE llega? ¿el iPad aplica?
2. Cambio mínimo en la frontera culpable. Tocar `Contracts.kt` o repositorios exige coordinar con `kmp-logic-fix`/`sqldelight-fix`; tocar el wrapper del bridge, con `kmp-bridge-fix`.
3. No debilitar seguridad para "arreglar" síntomas: ni abrir el POST más allá de loopback ni alargar el debounce hasta ocultar el problema.
4. Verificar: `./gradlew :shared:test` si se tocó Kotlin, `./scripts/verify_apple_builds.sh` si se tocó Swift, y prueba manual del flujo Mac→iPad si el entorno lo permite (si no, registrar qué quedó sin probar).
5. Cerrar con `registrar-avance-app`; si la decisión afecta al protocolo de sync, valorar ADR.

## Límites

- No introducir sync por internet/cloud: la estrategia actual es LAN/local por decisión de roadmap (Fase 3).
- No convertir el polling de fallback en mecanismo principal.
- No tocar el esquema de emparejamiento sin petición explícita.

## Salida esperada

Frontera donde se perdía el dato, causa raíz, fix mínimo, anotaciones `@Throws` auditadas (sí/no y resultado), pruebas ejecutadas y qué quedó sin poder probar en el entorno.
