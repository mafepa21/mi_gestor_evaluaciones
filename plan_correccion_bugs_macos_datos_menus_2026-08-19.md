# Plan de corrección: datos macOS y menús PR208/PR209

## Objetivo

Recuperar la apertura fiable de bases existentes en macOS y restaurar el layout y
los menús de Alumnado e Informes sin tocar datos reales ni `KmpBridge.swift`.

## Diagnóstico

- `develop` estaba en el PR207; los cambios efectivos de PR208 y PR209 vivían en
  ramas separadas.
- La migración 42 usaba `SELECT 1` como no-op, una forma que podía fallar durante
  la cadena SQLDelight de los drivers Apple/Android.
- El shell macOS materializaba demasiadas columnas y el módulo Alumnado mantenía
  acciones y mínimos de ancho que podían provocar solapamientos.

## Cambios aplicados

- Integrado PR209 como `fix(data)`: migración 42 DDL temporal compatible, regresión
  de camino de actualización y bloqueo del onboarding mientras hay rescate.
- Integrado PR208 como `fix(mac)`: inspector condicional por ancho, Alumnado con
  acciones agrupadas y layout compacto/expandido de Informes.
- Añadido el escaneo de cuarentenas al shell macOS nativo para que una base
  apartada siga siendo visible y recuperable aunque ya no quede `rescue_marker`.
- Conservado el ADR de migración y actualizado el changelog con evidencias reales.

## Validación

- `cd kmp && ./gradlew :data:desktopTest`: correcto.
- `cd kmp && ./gradlew :shared:desktopTest`: correcto.
- `./scripts/verify_apple_builds.sh`: XcodeGen, macOS e iOS correctos.
- `:shared:test` queda pendiente del entorno por ausencia de Android SDK.

## Fuera de alcance

- No se abrió, restauró ni modificó la base de datos real de la persona usuaria.
- No se tocó `KmpBridge.swift`, el dominio protegido ni `main`.
