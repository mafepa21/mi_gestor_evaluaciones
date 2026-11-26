# ADR-2026-11-26 · Lesiones con fecha y marca derivada `is_injured`

Estado: aceptado (ticket `docs/planes/ticket_lesiones_con_fecha_2026-11-26.md`).

## Contexto

La lesión era un sí/no por alumno (`students.is_injured`) usado en ~30 sitios (Asistencia, Cuaderno, rúbricas, grupos, ficha). No tenía fechas, ni papel en clase, ni historial, y el docente tenía que quitarla a mano.

## Decisión

1. Tabla nueva `student_injuries` (migración 51, solo aditiva): desde, hasta (opcional), papel, nota corta, casilla de justificante, borrado lógico y campos de sync. Sin diagnósticos ni fotos (decisión del docente).
2. `students.is_injured` se mantiene como **marca derivada** («tiene una lesión activa hoy»). La escribe solo `StudentInjuryUseCase` con una consulta que **no** toca `updated_at` del alumno, para que no compita en Sync LAN con otras ediciones del alumno. Los usos existentes no cambian.
3. Cada dispositivo recalcula la marca: al abrir «Hoy» o volver a primer plano si cambió el día, tras guardar, al final de cada lote de Sync LAN (Apple y Mac) y al recoger cambios en el helper.
4. `reconcileFlags()` solo gestiona alumnos con alguna fila de lesión. Las marcas antiguas se convierten en la migración en una lesión `legacy-<studentId>` sin fecha de fin (id fijo para que iPad y Mac no dupliquen).
5. Sync LAN por `SchoolRecordsSync` (entidad `student_injuries`, LWW con desempate por `deviceId`). Las lesiones se mandan siempre todas (pocas filas), para que un aparato actualizado tarde converja.
6. Lógica en un paquete propio `com.migestor.shared.injury`; no se toca `shared/domain/`.

## Alternativas descartadas

- Añadir columnas a `students`: no permite historial y obliga a tocar el modelo protegido.
- Quitar `is_injured` y leer siempre de la tabla nueva: obligaba a cambiar los ~30 usos a la vez.
- Mandar la marca dentro del registro `student`: dos aparatos recalculando el mismo día competirían por `updated_at` y podrían pisar ediciones del alumno.

## Consecuencias

- No escribir `is_injured` con `saveStudent` para marcar o quitar lesiones: usar `setStudentInjured`/`updateStudentInjuryStatus`.
- Un `Map<Long, …>` de Kotlin no se puede iterar en Swift (rompía al arrancar): el caso de uso devuelve listas.
- Hay que actualizar iPad y Mac antes de volver a sincronizar; si no, se ponen al día en el siguiente sync tras actualizar.
- Fase 2 posible: quitar de la media las notas de los días de lesión (toca la regla protegida de la media).
