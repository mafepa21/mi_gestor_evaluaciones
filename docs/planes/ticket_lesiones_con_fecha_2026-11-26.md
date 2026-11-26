# Ticket L: Lesiones con fecha de fin

Estado: aprobado por el docente el 2026-11-26 («Casilla, APROBADO»). Maqueta: `docs/maquetas/lesiones-con-fecha/mockup/index.html` (pendiente de aprobar, puerta 1).
Rama: `codex/lesiones-con-fecha` (worktree `.claude/worktrees/lesiones-con-fecha`).
Decisión del docente: el justificante es una **casilla «Justificante entregado»**. No se guardan fotos ni documentos médicos.

## 1. Objetivo y contexto

Hoy la lesión es un sí/no por alumno (`students.is_injured`), sin fechas ni papel en clase. El docente tiene que acordarse de quitarla a mano y no queda historial. Objetivo: una lesión con desde/hasta y papel alternativo, que se quite sola al terminar y avise en «Hoy».

## 2. Alcance

1. Hoja «Lesión» (iPad y Mac) desde la ficha del alumno y desde Asistencia: desde, hasta (o «Sin fecha de fin»), papel en clase, casilla «Justificante entregado» y nota corta sin datos médicos.
2. Papeles: Árbitro, Cronometrador, Ayudante de material, Ficha teórica, Otro.
3. `students.is_injured` se mantiene como **marca derivada**: «tiene una lesión activa hoy». Se recalcula al abrir la app, al cambiar de día, al guardar una lesión y al recibir datos de SyncLAN. Los ~30 usos actuales siguen funcionando sin cambios.
4. El interruptor actual «Lesión motriz activa» de Asistencia pasa a abrir la hoja. Activar rápido crea una lesión desde hoy sin fecha de fin.
5. El día siguiente al «hasta», la lesión deja de estar activa sola. «Hoy» avisa en Atención: «Vuelve hoy: <alumno> (<grupo>)».
6. Asistencia y ficha muestran «Lesionado hasta el 12 dic · Árbitro» (o «sin fecha de fin»).
7. Historial de lesiones en la ficha del alumno (las terminadas, plegadas).
8. Las lesiones viajan por SyncLAN entre iPad y Mac.

## 3. Fuera de alcance

- Quitar de la media las notas de los días de lesión (toca la regla protegida de la media). Fase 2.
- Diagnósticos, partes médicos o fotos del justificante.
- iPhone: se compila pero no se diseña para él.
- Compose Desktop (`kmp/desktopApp/`).

## 4. Modelo de datos

- Migración 51, solo aditiva. Tabla `student_injuries`:
  `id TEXT PK`, `student_id INTEGER NOT NULL`, `starts_on TEXT NOT NULL` (ISO `yyyy-MM-dd`), `ends_on TEXT` (NULL = sin fecha de fin), `alternate_role TEXT NOT NULL DEFAULT 'NONE'`, `note TEXT NOT NULL DEFAULT ''`, `proof_delivered INTEGER NOT NULL DEFAULT 0`, `is_deleted INTEGER NOT NULL DEFAULT 0`, `updated_at_epoch_ms`, `device_id`, `sync_version`.
- Índice por `student_id`.
- Patrón de sincronización y borrado lógico igual que `quick_note_phrases` (migración 50).
- Alumnos ya marcados como lesionados: la migración crea una lesión «desde hoy, sin fecha de fin» por cada `is_injured = 1`, para que no pierdan la marca.
- KMP: paquete propio `com.migestor.shared.injury` (modelo, contrato, reglas de fechas, caso de uso). Sin tocar `shared/domain/`.

## 5. Plan

1. Maqueta con estados (sin lesión, activa, termina hoy, sin fecha, historial, error de guardado) y revisión `ui-reviewer`. **Puerta 1: aprobación del docente.**
2. Tabla, migración 51 y repositorio + pruebas en `data`.
3. Reglas de fechas y caso de uso (activa hoy, recalcular marca, quién vuelve hoy) + pruebas en `shared`.
4. SyncLAN de la tabla nueva + prueba.
5. Puente en `App/Bridge/KmpBridge+Injuries.swift` (no se toca `KmpBridge.swift`).
6. SwiftUI: hoja «Lesión», etiqueta en Asistencia y ficha, historial, aviso en «Hoy».
7. Compilar, probar, QA con datos inventados, registro y PR.

## 6. Agentes

- `worker` (Sonnet): implementación por capas con `kmp-feature-vertical` y `sqldelight-migration`.
- `architect` (Opus): revisión de la migración y de SyncLAN.
- `ui-reviewer`: maqueta y código final. `reviewer` antes de la PR. `janitor` antes de fusionar.

## 7. Criterios de aceptación

- Una lesión «hasta el 12» está activa el 12 y deja de estarlo sola el 13.
- «Hoy» avisa el día de la vuelta.
- Lo creado en iPad aparece en Mac y al revés.
- Tras actualizar la app, los alumnos ya lesionados siguen marcados.
- No existe ningún campo de diagnóstico ni foto.
- La hoja funciona con VoiceOver y con teclado en Mac.

## 8. Validación

- `./gradlew :data:desktopTest` (migración 51, repositorio, SyncLAN).
- `./gradlew :shared:test` (reglas de fechas y caso de uso).
- `./scripts/verify_apple_builds.sh` (Mac e iOS simulador).
- QA manual en iPad (simulador) y Mac con alumnos inventados y capturas de ventana.

## 9. Riesgos y puertas humanas

- **Privacidad**: datos de salud de menores. Se guarda lo mínimo; la nota avisa «sin datos médicos».
- **Marca derivada vieja**: si un aparato no se abre en días, se recalcula al abrir y al sincronizar.
- **Conflicto de sync**: gana el `updated_at` más reciente, como en el resto de tablas.
- **Migración en aparatos reales**: solo aditiva; se prueba desde la versión 50.
- Puertas: 1) maqueta aprobada; 2) prueba en el iPad del docente; 3) fusión por el docente.

## 10. Entregables

- Maqueta viva, migración 51, código y pruebas.
- Changelog, Trampas en `docs/ambitos/alumnado.md`, PR en español.
