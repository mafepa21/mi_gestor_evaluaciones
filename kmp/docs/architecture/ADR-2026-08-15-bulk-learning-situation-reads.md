# ADR-2026-08-15: Lecturas bulk de Situaciones de aprendizaje

## Estado

Aprobado

## Contexto

Situaciones de aprendizaje, Cuaderno y Planificador necesitaban cargar relaciones entre situaciones,
grupos, versiones y planes de sesión. La implementación Apple resolvía algunas relaciones con
consultas dentro de bucles: al crecer el número de situaciones, un cambio de contexto podía generar
muchos viajes SQLite consecutivos y degradar la respuesta del iPad.

## Decisión

- El repositorio SQLDelight expone lecturas bulk para enlaces de grupo, versiones de secuencia y planes
  de sesión.
- El contrato KMP mantiene métodos suspendidos y declarados con `@Throws` para el puente Swift.
- Las capas Apple cargan cada colección una vez, construyen índices en memoria y filtran o enriquecen
  los modelos sin volver a consultar por cada situación, versión o sesión.
- No se modifica el esquema ni se crea migración: son consultas sobre tablas existentes.
- La primera versión prioriza eliminar el patrón N+1; si el volumen real lo exige, el siguiente paso
  será añadir lecturas bulk acotadas por grupo sin cambiar el contrato funcional.

## Consecuencias

- Menos viajes SQLite al abrir o cambiar de grupo en los flujos críticos.
- El código de presentación queda más determinista y fácil de perfilar.
- Las colecciones bulk usan más memoria temporal, acotada al conjunto ya cargado del workspace.
- La lógica de negocio y las tablas existentes permanecen compatibles con datos actuales.

## Verificación

- `:data:desktopTest --tests com.migestor.data.repository.LearningSituationsRepositorySqlDelightTest`
- `:shared:desktopTest`
- `scripts/verify_apple_builds.sh` para macOS Native, Catalyst e iOS Simulator.
