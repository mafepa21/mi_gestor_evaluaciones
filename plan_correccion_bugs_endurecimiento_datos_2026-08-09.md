# Plan de corrección: endurecimiento de datos críticos

Fecha: 2026-08-09
Rama: `codex/fix-critical-data-hardening`

## Objetivo

Cerrar los riesgos críticos detectados en pairing SyncLAN, restore Apple y
trazabilidad de la cadena SQLDelight con cambios aditivos y compatibles.

## Alcance y estado

- [x] Eliminar secretos e identificadores de los logs de red SyncLAN.
- [x] Añadir expiración/rotación del PIN, limitación por origen y límites de body.
- [x] Añadir tests unitarios del PIN, limitador y lector acotado.
- [x] Validar backups con checksum, cabecera e integridad/foreign keys de SQLite.
- [x] Preparar restore completo en staging y revertirlo ante fallo parcial.
- [x] Añadir tests Swift de validación, snapshot y rollback.
- [x] Probar la cadena SQLDelight soportada sin `RescueMigrations` y compararla con
  una base fresca.
- [x] Confirmar que no existe un gap canónico que justifique otra `.sqm`.
- [x] Documentar decisiones y cifrado de exportaciones pendiente.
- [x] Completar verificación Apple macOS/iOS.
- [ ] Publicar PR.

## Fuera de alcance

- Nuevo formato cifrado de `.migestorbackup` o UX improvisada de contraseña.
- Sustituir el IPC stdout del helper por XPC.
- Eliminar `RescueMigrations`, necesario para instalaciones históricas con drift.
- Cambios de UI, `KmpBridge.swift`, dominio compartido o migraciones destructivas.

## Evidencia prevista

- `:shared:desktopTest` y `:data:desktopTest`.
- XCTest dirigido `AppleBackupIntegrityTests`.
- `scripts/verify_apple_builds.sh`.
- Revisión `git diff --check`, diff final y estado limpio tras los commits.
