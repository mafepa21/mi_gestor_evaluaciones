# Ticket M: Alumnos invisibles

Estado: aprobado por el docente el 2026-11-27 («APROBADO», reglas por defecto). Maqueta: `docs/maquetas/alumnos-invisibles/mockup/index.html` (pendiente de aprobar, puerta 1).
Rama: `codex/alumnos-invisibles` (worktree `.claude/worktrees/alumnos-invisibles`).

## 1. Objetivo y contexto

Que ningún alumno pase dos semanas sin una nota, una observación o un comentario del docente. Son los alumnos callados, los que nunca dan problemas. Sirve para preparar las juntas y como tutor de inclusión.

## 2. Alcance

1. «Hoy» › Atención, los viernes: una fila por grupo («2º ESO B: 4 alumnos sin mirar en 2 semanas») que abre la lista.
2. Lista «Sin mirar» (iPad y Mac): nombre, días sin registro y último registro («Nota en Hockey, 10 nov»). Primero el alumnado con medidas de nivel III/IV, con su etiqueta.
3. Acciones por alumno: «Observación rápida», «Abrir ficha» y «Visto» (lo esconde 7 días).
4. Alumnado: filtro «Sin mirar» y dato «Último registro: hace 16 días» en la ficha.
5. Se calcula por grupo.

## 3. Fuera de alcance

- Notificaciones del sistema.
- Cambiar la media o las notas.
- IA: es una cuenta de fechas.
- iPhone.

## 4. Reglas (aprobadas con los valores por defecto)

- Cuenta como «mirarle»: nota o rúbrica, comentario o sello en celda, incidencia, nota individual del diario de sesión, prueba física, «Tu valoración» del trimestre, reunión con la familia (tutoría).
- No cuenta: pasar lista sin nota; entregas web del propio alumno.
- Ventana: 14 días sin contar los no lectivos del calendario docente.
- Alumnos que entraron al grupo hace menos de 14 días no salen hasta cumplir el plazo.
- «Visto»: local al dispositivo (`UserDefaults`), 7 días.

## 5. Modelo de datos

- Sin tablas nuevas ni migraciones.
- Consultas nuevas de solo lectura («último registro por alumno en este grupo»), por lotes de grupo. Van en `kmp/data/src/commonMain/sqldelight/` sin cambiar el esquema: permiso explícito de este ticket.
- Lógica en paquete propio `com.migestor.shared.attention`. Sin tocar `shared/domain/`.

## 6. Plan

1. Maqueta (fila en Hoy, lista, vacío, cargando, error, filtro de Alumnado, Mac) + `ui-reviewer`. **Puerta 1.**
2. Consultas de solo lectura + pruebas en `data`.
3. Reglas y caso de uso + pruebas en `shared` (ventana, no lectivos, altas recientes, varios grupos).
4. Puente `App/Bridge/KmpBridge+Attention.swift`.
5. SwiftUI: fila en Hoy, lista, filtro y dato en Alumnado.
6. Compilar, probar, revisar, registrar y PR.

## 7. Agentes

- Implementación: agente principal (`kmp-feature-vertical`).
- `ui-reviewer` (maqueta), `reviewer` (código), `janitor` (antes de fusionar).

## 8. Criterios de aceptación

- Sin registros en 14 días lectivos → sale en la lista de su grupo; un registro lo saca.
- Pasar lista sin nota no lo saca.
- Las vacaciones no cuentan.
- «Visto» lo esconde 7 días.
- Con 8 grupos de 30, «Hoy» no se ralentiza (cálculo en segundo plano y por lotes).
- VoiceOver y teclado en Mac.

## 9. Validación

- `./gradlew :data:desktopTest` y `./gradlew :shared:desktopTest`.
- `./scripts/verify_apple_builds.sh`.
- `xcodebuild test -scheme MiGestorPlannerTests`.
- QA manual con datos inventados (la copia aislada del Mac puede atascarse en el permiso del llavero: si pasa, se registra).
