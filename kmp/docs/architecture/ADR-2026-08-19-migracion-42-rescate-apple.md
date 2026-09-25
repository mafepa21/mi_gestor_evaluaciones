# ADR-2026-08-19: Migración 42 compatible con rescate Apple

## Estado

Aprobado

## Contexto

La migración 42 de SQLDelight reservaba una nueva versión para añadir campos de
puntuación a `physical_test_scales`, pero usaba `SELECT 1` como no-op y dejaba la
adición real para `runRescueMigrations()`. En el driver Apple, una base existente
en la versión anterior podía fallar durante la apertura y ser apartada como
rescate, tras lo cual la app arrancaba con una base vacía y el onboarding se
presentaba encima del aviso de recuperación.

## Decisión

La migración 42 ejecuta una secuencia DDL temporal idempotente que crea y elimina
una tabla auxiliar durante la propia migración. Así evita consultas de solo
lectura y tampoco depende de que una fixture parcial contenga ya
`physical_test_scales`. Las columnas nuevas siguen siendo añadidas de forma
segura por `runRescueMigrations()`, que permite cubrir instalaciones antiguas sin
alterar la historia de datos.

En macOS, mientras exista un `rescue_marker`, el shell no inicia el onboarding.
La recuperación de la base rescatada permanece bajo la acción explícita de la
docente y exige reiniciar la app después de sustituir la base activa.

## Consecuencias

- Las bases en versión 42 pueden alcanzar el esquema actual sin ejecutar una
  consulta de resultados ni dejar una tabla auxiliar persistente.
- La reparación de columnas continúa siendo idempotente para instalaciones
  históricas.
- El aviso de rescate mantiene el foco y evita introducir datos en una base de
  fallback vacía.
