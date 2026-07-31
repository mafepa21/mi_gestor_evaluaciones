# Integración de entregas web en main — 2026-07-31

## Alcance

Se integra en `main` el circuito de publicación e importación de entregas del alumnado:

- La app genera un manifiesto firmado, un alias por alumno y enlaces con `#f=<formInstanceId>&a=<alias>`.
- La PWA carga el manifiesto indicado por el enlace, cifra la respuesta y la app la importa en el curso, columna y alumno correspondientes.
- Las migraciones 39 y 40 almacenan la correspondencia privada y el manifiesto publicado.

## Incidencia corregida

Los enlaces creados por el generador web contenían solo `#a=<alias>`. La PWA, por compatibilidad, abría el pasaporte de bádminton al faltar `f`. El generador incluye ahora ambos valores.

Un 404 posterior no era un error de enlace: el manifiesto recién generado aún no estaba publicado en `public/manifiestos/<formInstanceId>.json`. Se validó y publicó el manifiesto `7A7D8AD0-9EA5-4BAD-9CF2-110304580A11` sin correo de entrega.

## Repositorios y commits

- App: `mafepa21/mi_gestor_evaluaciones`, integración en `main` mediante `6d463ba3`.
- PWA: `marfepa/entregas-alumnado`, enlace corregido en `0c94a49` y manifiesto publicado en `82142f1`.

## Verificación

- `./gradlew :data:verifyCommonMainAppDatabaseMigration`: correcto.
- `scripts/interop_entregas_web/verificar.sh`: 64 comprobaciones correctas.
- `scripts/verify_apple_builds.sh`: macOS e iOS Simulator compilados correctamente.
- Vercel sirve `https://entregas-alumnado.vercel.app/manifiestos/7A7D8AD0-9EA5-4BAD-9CF2-110304580A11.json` con el identificador esperado.

## Riesgos y operación

- No se edita nunca un manifiesto publicado: invalidaría su firma. Para cambiar un dato se publica otro formulario y se reparten sus enlaces nuevos.
- El manifiesto es público; la hoja de enlaces y la tabla alias-alumnado no lo son.
- La batería completa `:data:desktopTest` conserva un fallo ajeno al flujo web en la prueba de derivación de puntuación de una rejilla de observación.
