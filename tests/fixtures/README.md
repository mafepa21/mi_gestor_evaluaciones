# Fixtures sinteticas de regresion

Todo lo que vive aqui son datos INVENTADOS (prefijos `demo_` o `anonymous_`,
los unicos que `scripts/verify_no_sensitive_files.sh` permite commitear).
Nunca colocar aqui una base de datos con alumnado real.

## Fixture de camino de actualizacion

`demo_canonical_teacher.db` es una base de datos real generada por una version
anterior de la app (esquema y `PRAGMA user_version` del dia en que se genero),
poblada con `CanonicalTeacherDataset`: un curso en miniatura con los casos que
historicamente rompen (eñes y tildes, comas decimales en formulas, celdas
vacias, notas con evidencia pero sin valor, tombstones de sync).

`UpgradePathRegressionTest` (en `kmp/data/src/desktopTest`) abre una copia de
este fichero con el mismo camino que usa produccion
(`createSharedDesktopDriver`: migraciones `.sqm` + migraciones de rescate +
tablas del planner) y verifica que:

1. La base llega a la version de esquema actual con `integrity_check` y
   `foreign_key_check` limpios.
2. Cada dato del curso sobrevive con sus valores exactos.
3. Una instalacion nueva y una instalacion migrada exponen el mismo esquema.

## Reglas

- **No borrar ni regenerar esta fixture al añadir una migracion.** Su valor es
  precisamente estar congelada en una version antigua: cuando se añada
  `34.sqm`, los tests ejecutaran esa migracion sobre estos datos.
- Regenerar solo cuando se quiera avanzar la "version antigua" de referencia
  (por ejemplo, tras varias migraciones ya verificadas en verde): borrar el
  `.db`, ejecutar `cd kmp && ./gradlew :data:desktopTest --rerun-tasks`, y
  commitear el fichero nuevo.
- Si un test del harness falla tras escribir una migracion, la migracion
  pierde o corrompe datos, o deja el esquema distinto al de una instalacion
  nueva. Arreglar la migracion, no el test.
